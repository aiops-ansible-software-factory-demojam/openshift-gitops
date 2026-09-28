#!/usr/bin/env bash
# Reproduce the Forgejo issue and rotate the sandbox's demo-only Git credential.
set -euo pipefail
set +x
: "${KUBECONFIG:?Set KUBECONFIG for the demo cluster}"

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
action=${1:-}
case "$action" in
  hydrate) [[ $# -eq 1 ]] ;;
  reset) [[ $# -eq 2 && $2 == --confirm-forgejo-demo ]] ;;
  *) echo 'Usage: feature-demo.sh hydrate | reset --confirm-forgejo-demo' >&2; exit 2 ;;
esac

server=$(oc whoami --show-server)
oc whoami
ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default \
  -o jsonpath='{.status.domain}')
[[ -n $ingress_domain ]] || { echo 'Ingress domain is unavailable.' >&2; exit 1; }
oc -n omnigent-sandboxes get secret omnigent-model >/dev/null
oc -n forgejo-demo rollout status deployment/forgejo-demo --timeout=10m
forgejo_host=$(oc -n forgejo-demo get route forgejo-demo \
  -o jsonpath='{.status.ingress[0].host}')
[[ $forgejo_host == "forgejo-demo.$ingress_domain" ]] || {
  echo 'Forgejo Route does not match this cluster ingress domain.' >&2
  exit 1
}

state_dir=${FORGEJO_STATE_DIR:-"$repo_root/cluster/forgejo-demo/.state/$ingress_domain"}
export FORGEJO_STATE_DIR="$state_dir"
export FORGEJO_URL="https://$forgejo_host"
export EXPECTED_SERVER="$server"
if [[ $action == reset ]]; then
  bash "$repo_root/cluster/forgejo-demo/scripts/demo.sh" reset --confirm-forgejo-demo
else
  bash "$repo_root/cluster/forgejo-demo/scripts/demo.sh" seed
fi

FORGEJO_TOKEN=$(<"$state_dir/admin-token")
export FORGEJO_TOKEN
issue_url=$(bash "$repo_root/cluster/forgejo-demo/scripts/ensure-nginx-uid-issue.sh")
unset FORGEJO_TOKEN

umask 077
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
tr -d '\r\n' <"$state_dir/agent-token" >"$scratch/agent-token"
jq -n --rawfile token "$scratch/agent-token" \
  --arg url 'http://forgejo-demo.forgejo-demo.svc.cluster.local:3000' \
  '{stringData:{FORGEJO_TOKEN:$token,FORGEJO_URL:$url,FORGEJO_USERNAME:"demo-agent"}}' \
  >"$scratch/forgejo-patch.json"
oc -n omnigent-sandboxes patch secret omnigent-model --type=merge \
  --patch-file="$scratch/forgejo-patch.json" >/dev/null

printf 'Forgejo demo ready: %s\n' "$issue_url"
echo 'New automation-developer sandboxes receive the current demo-agent token.'
