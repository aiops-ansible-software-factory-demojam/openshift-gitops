#!/usr/bin/env bash
set -euo pipefail
set +x

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ingress_domain=${1:?Pass ingress domain}
server=$(oc whoami --show-server)
oc whoami

oc -n forgejo-demo rollout status deployment/forgejo-demo --timeout=10m
deadline=$((SECONDS + 600))
until forgejo_host=$(oc -n forgejo-demo get route forgejo-demo \
  -o jsonpath='{.status.ingress[0].host}' 2>/dev/null) &&
  [[ $forgejo_host == *".$ingress_domain" ]]; do
  if (( SECONDS >= deadline )); then
    echo 'Forgejo Route did not become ready.' >&2
    exit 1
  fi
  sleep 5
done

state_dir="$repo_root/cluster/forgejo-demo/.state/$ingress_domain"
FORGEJO_STATE_DIR=$state_dir \
  FORGEJO_URL="https://$forgejo_host" \
  EXPECTED_SERVER="$server" \
  bash "$repo_root/cluster/forgejo-demo/scripts/demo.sh" seed
export FORGEJO_URL="https://$forgejo_host"
FORGEJO_TOKEN=$(cat "$state_dir/admin-token")
export FORGEJO_TOKEN
bash "$repo_root/cluster/forgejo-demo/scripts/ensure-nginx-uid-issue.sh"
unset FORGEJO_TOKEN

umask 077
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
tr -d '\r\n' <"$state_dir/agent-token" >"$scratch/token"
tr -d '\r\n' <"$state_dir/rhdh-token" >"$scratch/rhdh-token"
printf 'demo-agent' >"$scratch/username"
printf 'http://forgejo-demo.forgejo-demo.svc.cluster.local:3000' >"$scratch/forgejo-url"
printf 'http://backstage-rhdh-developer-hub.rhdh.svc.cluster.local:80' >"$scratch/backstage-url"

oc -n rhdh create configmap rhdh-demo-endpoints \
  --from-literal="FORGEJO_HOST=$forgejo_host" \
  --from-literal="FORGEJO_URL=https://$forgejo_host" \
  --from-literal="RHDH_URL=https://rhdh.$ingress_domain" \
  --dry-run=client -o yaml | oc -n rhdh apply -f -
oc -n rhdh create secret generic rhdh-forgejo-credentials \
  --from-file=FORGEJO_TOKEN="$scratch/rhdh-token" \
  --from-file=FORGEJO_USERNAME="$scratch/username" \
  --dry-run=client -o yaml | oc -n rhdh apply -f -
oc -n omnigent create secret generic omnigent-feature-credentials \
  --from-file=FORGEJO_TOKEN="$scratch/token" \
  --from-file=FORGEJO_USERNAME="$scratch/username" \
  --from-file=FORGEJO_URL="$scratch/forgejo-url" \
  --from-file=BACKSTAGE_URL="$scratch/backstage-url" \
  --dry-run=client -o yaml | oc -n omnigent apply -f -
if oc -n rhdh get deployment backstage-rhdh-developer-hub >/dev/null 2>&1; then
  oc -n rhdh rollout restart deployment/backstage-rhdh-developer-hub
fi
if oc -n omnigent get deployment omnigent >/dev/null 2>&1; then
  oc -n omnigent rollout restart deployment/omnigent
fi
echo 'Forgejo demo data and Backstage/agent credentials are ready.'
