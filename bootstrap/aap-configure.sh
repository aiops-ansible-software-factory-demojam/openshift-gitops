#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$demo_repo_root"
manifest=${AAP_LICENSE_FILE:-$demo_repo_root/aap_manifest.zip}
[[ -r $manifest ]] || { echo 'Place aap_manifest.zip in the repo root.' >&2; exit 2; }
demo_verify_cluster
demo_wait_for_api
namespace=ansible-automation-platform
for deployment in aap-gateway aap-controller-web aap-controller-task; do
  oc -n "$namespace" rollout status "deployment/$deployment" --timeout=15m
done
# Bootstrap creates these credentials directly; dispatch never owns their secrets.
python3 "$demo_repo_root/bootstrap/aap-runtime.py" credentials
# Resource Operator owns the initial inventory/project/template base fields.
# This operator ignores API dependency errors instead of retrying them.
# Wait for the real project before creating the template that references it.
oc apply -f "$demo_repo_root/bootstrap/aap-resources/demo-inventory-ansibleinventory.yaml" \
  -f "$demo_repo_root/bootstrap/aap-resources/demojam-ansible-ansibleproject.yaml"
for resource in ansibleinventory/demo-inventory ansibleproject/demojam-ansible; do
  oc -n "$namespace" wait --for=condition=Successful "$resource" --timeout=15m
done
python3 "$demo_repo_root/bootstrap/aap-runtime.py" wait-project
oc apply -f "$demo_repo_root/bootstrap/aap-resources/aap-configure-all-jobtemplate.yaml"
oc -n "$namespace" wait --for=condition=Successful jobtemplate/aap-configure-all --timeout=15m
python3 "$demo_repo_root/bootstrap/aap-runtime.py" wait-resources
forgejo_url=http://forgejo.forgejo.svc.cluster.local:3000
image=${AAP_EE_IMAGE:-image-registry.openshift-image-registry.svc:5000/$namespace/demo-aap-ee:latest}
oc -n "$namespace" delete job aap-configure --ignore-not-found --wait=true >/dev/null
yq '.' "$demo_repo_root/bootstrap/aap-configure-job.yaml" | jq \
  --arg image "$image" --arg repo "$forgejo_url/demo-owner/demojam-ansible.git" '
  .spec.template.spec.containers[0].image = $image |
  .spec.template.spec.containers[0].env |= map(
    if .name == "CONFIG_REPO_URL" then .value = $repo
    elif .name == "AAP_EE_IMAGE" then .value = $image
    else . end)' | oc -n "$namespace" apply -f -
oc -n "$namespace" logs job/aap-configure --follow --pod-running-timeout=10m ||
  echo 'Configuration log stream ended; waiting on the Job resource.' >&2
deadline=$((SECONDS + 1800))
while (( SECONDS < deadline )); do
  if ! job_status=$(oc -n "$namespace" get job aap-configure --request-timeout=30s -o json); then
    echo 'Configuration status is temporarily unavailable; retrying.' >&2
    sleep 10
    continue
  fi
  if jq -e '(.status.failed // 0) > 0' <<< "$job_status" >/dev/null; then
    echo 'AAP dispatch failed; inspect the aap-configure Job.' >&2; exit 1
  fi
  if jq -e '(.status.succeeded // 0) > 0' <<< "$job_status" >/dev/null; then
    echo 'AAP configuration from Forgejo completed.'; exit
  fi
  sleep 5
done
echo 'AAP Job did not report a final status.' >&2
exit 1
