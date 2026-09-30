#!/usr/bin/env bash
# Reproduce the Forgejo issue and rotate the sandbox's demo-only Git credential.
set -euo pipefail
set +x
# shellcheck source=../bootstrap/env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/env.sh"

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
action=${1:-}
case "$action" in
  hydrate) [[ $# -eq 1 ]] ;;
  reset) [[ $# -eq 2 && $2 == --confirm-forgejo ]] ;;
  *) echo 'Usage: feature-demo.sh hydrate | reset --confirm-forgejo' >&2; exit 2 ;;
esac

server=$(oc whoami --show-server)
oc whoami
ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default \
  -o jsonpath='{.status.domain}')
[[ -n $ingress_domain ]] || { echo 'Ingress domain is unavailable.' >&2; exit 1; }
oc -n omnigent-sandboxes get secret omnigent-model >/dev/null
oc -n forgejo rollout status deployment/forgejo --timeout=10m
forgejo_host=$(oc -n forgejo get route forgejo \
  -o jsonpath='{.status.ingress[0].host}')
[[ $forgejo_host == "forgejo.$ingress_domain" ]] || {
  echo 'Forgejo Route does not match this cluster ingress domain.' >&2
  exit 1
}

state_dir=${FORGEJO_STATE_DIR:-"$repo_root/cluster/forgejo/.state/$ingress_domain"}
export FORGEJO_STATE_DIR="$state_dir"
export FORGEJO_URL="https://$forgejo_host"
export EXPECTED_SERVER="$server"
if [[ $action == reset ]]; then
  RHDH_URL="https://rhdh.$ingress_domain" FORGEJO_URL="$FORGEJO_URL" \
    bash "$repo_root/cluster/rhdh/scripts/clear-demo-catalog.sh"
  bash "$repo_root/cluster/forgejo/scripts/demo.sh" reset --confirm-forgejo
else
  bash "$repo_root/cluster/forgejo/scripts/demo.sh" seed
fi

FORGEJO_TOKEN=$(<"$state_dir/admin-token")
export FORGEJO_TOKEN
issue_url=$(bash "$repo_root/cluster/forgejo/scripts/ensure-readme-test-issue.sh")
unset FORGEJO_TOKEN

umask 077
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
tr -d '\r\n' <"$state_dir/agent-token" >"$scratch/agent-token"
jq -n --rawfile token "$scratch/agent-token" \
  --arg url 'http://forgejo.forgejo.svc.cluster.local:3000' \
  --arg backstage 'http://backstage-rhdh-developer-hub.rhdh.svc.cluster.local:80' \
  '{stringData:{FORGEJO_TOKEN:$token,FORGEJO_URL:$url,FORGEJO_USERNAME:"demo-agent",BACKSTAGE_URL:$backstage}}' \
  >"$scratch/forgejo-patch.json"
oc -n omnigent-sandboxes patch secret omnigent-model --type=merge \
  --patch-file="$scratch/forgejo-patch.json" >/dev/null

tr -d '\r\n' <"$state_dir/rhdh-token" >"$scratch/rhdh-token"
endpoints_status=$(oc -n rhdh create configmap rhdh-demo-endpoints \
  --from-literal="FORGEJO_HOST=$forgejo_host" \
  --from-literal="FORGEJO_URL=$FORGEJO_URL" \
  --from-literal="RHDH_URL=https://rhdh.$ingress_domain" \
  --dry-run=client -o yaml | oc -n rhdh apply -f -)
credentials_status=$(oc -n rhdh create secret generic rhdh-forgejo-credentials \
  --from-file=FORGEJO_TOKEN="$scratch/rhdh-token" \
  --from-literal=FORGEJO_USERNAME=demo-agent \
  --dry-run=client -o yaml | oc -n rhdh apply -f -)
printf '%s\n' "$endpoints_status" "$credentials_status"
if [[ $endpoints_status != *' unchanged' ||
      $credentials_status != *' unchanged' ]] &&
   oc -n rhdh get deployment backstage-rhdh-developer-hub >/dev/null 2>&1; then
  oc -n rhdh rollout restart deployment/backstage-rhdh-developer-hub
  oc -n rhdh rollout status deployment/backstage-rhdh-developer-hub --timeout=15m
fi

printf 'Forgejo demo ready: %s\n' "$issue_url"
echo 'New automation-developer sandboxes and Backstage receive current Forgejo credentials.'
