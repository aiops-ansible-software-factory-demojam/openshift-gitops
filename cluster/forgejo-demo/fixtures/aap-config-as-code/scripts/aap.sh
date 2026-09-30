#!/usr/bin/env bash
set -euo pipefail
set +x

project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
action=${1:-}
[[ $# -eq 1 && ( $action == build || $action == configure ) ]] || {
  echo 'Usage: aap.sh build | configure' >&2; exit 2;
}
env_file=${ENV_FILE:-$PWD/.env}
if [[ -f $env_file ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
fi
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
namespace=ansible-automation-platform
image=${AAP_EE_IMAGE:-image-registry.openshift-image-registry.svc:5000/$namespace/demo-aap-ee:latest}
manifest=${AAP_LICENSE_FILE:-$PWD/aap_manifest.zip}
if [[ $action == configure ]]; then
  [[ -f $manifest && -r $manifest ]] || {
    echo 'Place aap_manifest.zip in the repo root or set AAP_LICENSE_FILE.' >&2; exit 2;
  }
  : "${AAP_PASSWORD:?Populate AAP_PASSWORD in .env}"
  : "${FORGEJO_TOKEN:?Populate FORGEJO_TOKEN with the demo-agent token in .env}"
fi
server=$(oc whoami --show-server)
oc whoami
printf 'Cluster: %s\n' "$server"
[[ -z ${EXPECTED_SERVER:-} || $server == "$EXPECTED_SERVER" ]] || {
  echo 'Unexpected cluster; check EXPECTED_SERVER.' >&2; exit 2;
}

umask 077
scratch=$(mktemp -d)
# Called by the EXIT trap, including the explicit exits below.
# shellcheck disable=SC2317
cleanup() {
  find "$scratch" -type f -delete
  find "$scratch" -depth -type d -empty -delete
  if [[ $action == configure && ${inputs_created:-false} == true ]]; then
    oc -n "$namespace" delete secret aap-configure-inputs --ignore-not-found >/dev/null
  fi
}
trap 'cleanup' EXIT

if [[ $action == build ]]; then
  # Preserve the BuildConfig's Git contextDir without uploading local secrets.
  source_dir="$scratch/source/cluster/forgejo-demo/fixtures/aap-config-as-code"
  mkdir -p "$source_dir"
  cp "$project/Containerfile" "$project/requirements.yml" "$source_dir/"
  tar -czf "$scratch/source.tar.gz" -C "$scratch/source" .
  oc -n "$namespace" start-build demo-aap-ee \
    --from-archive="$scratch/source.tar.gz" --follow --wait
  exit
fi

host=${AAP_HOST:-https://$(oc -n "$namespace" get route aap -o jsonpath='{.status.ingress[0].host}')}
forgejo_url=${FORGEJO_URL:-https://$(oc -n forgejo-demo get route forgejo-demo -o jsonpath='{.status.ingress[0].host}')}
[[ $host != https:// && $forgejo_url != https:// ]] || {
  echo 'AAP and Forgejo Routes must have assigned hosts before configuration.' >&2; exit 2;
}
api_host=${K8S_AUTH_HOST:-$server}
api_token=${K8S_AUTH_API_KEY:-$(oc -n automation-vms create token aap-vm-admin --duration=8h)}
api_ca=${AAP_K8S_CA_CERT:-$(oc -n automation-vms get configmap kube-root-ca.crt -o go-template='{{index .data "ca.crt"}}')}

tar -czf "$scratch/project.tar.gz" -C "$project" \
  --exclude=.git --exclude=.env --exclude='.env.*' --exclude=.secrets \
  --exclude=aap_manifest.zip --exclude=.ansible --exclude=.venv \
  --exclude=context --exclude=artifacts --exclude='*.log' .
printf '%s' "$AAP_PASSWORD" > "$scratch/AAP_PASSWORD"
printf '%s' "$FORGEJO_TOKEN" > "$scratch/FORGEJO_TOKEN"
printf '%s' "$api_token" > "$scratch/K8S_AUTH_API_KEY"
printf '%s' "$api_ca" > "$scratch/AAP_K8S_CA_CERT"
unset api_token api_ca

oc -n "$namespace" delete job aap-configure --ignore-not-found --wait=true >/dev/null
oc -n "$namespace" create secret generic aap-configure-inputs \
  --from-file="AAP_PASSWORD=$scratch/AAP_PASSWORD" \
  --from-file="FORGEJO_TOKEN=$scratch/FORGEJO_TOKEN" \
  --from-file="K8S_AUTH_API_KEY=$scratch/K8S_AUTH_API_KEY" \
  --from-file="AAP_K8S_CA_CERT=$scratch/AAP_K8S_CA_CERT" \
  --from-file="project.tar.gz=$scratch/project.tar.gz" \
  --dry-run=client -o json | oc -n "$namespace" apply -f -
inputs_created=true
yq '.' "$project/scripts/configure-job.yaml" | jq \
  --arg image "$image" --arg host "$host" --arg username "${AAP_USERNAME:-admin}" \
  --arg forgejo "$forgejo_url" --arg api "$api_host" '
  .spec.template.spec.containers[0].image = $image |
  .spec.template.spec.containers[0].env |= map(
    if .name == "AAP_HOST" then .value = $host
    elif .name == "AAP_USERNAME" then .value = $username
    elif .name == "AAP_EE_IMAGE" then .value = $image
    elif .name == "FORGEJO_URL" then .value = $forgejo
    elif .name == "K8S_AUTH_HOST" then .value = $api
    else . end)' | oc -n "$namespace" apply -f -
oc -n "$namespace" wait --for=condition=Ready pod \
  -l job-name=aap-configure --timeout=10m
pod=$(oc -n "$namespace" get pod -l job-name=aap-configure -o jsonpath='{.items[0].metadata.name}')
# Manifests can exceed the Kubernetes Secret size limit; stream into the EE.
oc -n "$namespace" exec -i "$pod" -c configure -- /bin/bash -ceu \
  'umask 077; cat > /runner/aap_manifest.zip; touch /runner/manifest.ready' < "$manifest"
oc -n "$namespace" logs job/aap-configure --follow --pod-running-timeout=10m
for ((attempt = 0; attempt < 60; attempt++)); do
  job_status=$(oc -n "$namespace" get job aap-configure -o json)
  if jq -e '(.status.failed // 0) > 0' <<< "$job_status" >/dev/null; then
    echo 'AAP configuration failed.' >&2; exit 1
  fi
  if jq -e '(.status.succeeded // 0) > 0' <<< "$job_status" >/dev/null; then
    echo 'AAP configuration completed.'; exit
  fi
  sleep 1
done
echo 'AAP Job did not report a final status after its pod stopped.' >&2
exit 1
