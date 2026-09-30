#!/usr/bin/env bash
# Reset only the disposable Forgejo repo and automation-developer sessions.
set -euo pipefail
set +x
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
[[ ${1:-} == --confirm-demo-reset && $# -eq 1 ]] || {
  echo 'Usage: reset-demo.sh --confirm-demo-reset' >&2
  exit 2
}

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
oc whoami --show-server
oc whoami
ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default \
  -o jsonpath='{.status.domain}')
omnigent_host=$(oc -n omnigent get route omnigent \
  -o jsonpath='{.status.ingress[0].host}')
[[ -n $ingress_domain && $omnigent_host == "omnigent.$ingress_domain" ]] || {
  echo 'Omnigent Route does not match this cluster ingress domain.' >&2
  exit 2
}
if [[ -z ${MODEL_API_KEY:-} ]]; then
  if ! command -v op >/dev/null ||
     ! op item get opencode-go-subscription-key --vault lab_agents \
       --format json >/dev/null; then
    echo 'An OpenCode Go key must be available through op or MODEL_API_KEY.' >&2
    exit 2
  fi
fi

client_id=$(oc -n automation-orchestrator get secret \
  omnigent-machine-client-credential \
  -o go-template='{{index .data "username" | base64decode}}')
client_secret=$(oc -n automation-orchestrator get secret \
  omnigent-machine-client-credential \
  -o go-template='{{index .data "password" | base64decode}}')
omnigent_api="https://$omnigent_host/v1"
omnigent_get() {
  curl -fsS --user "$client_id:$client_secret" "$omnigent_api/$1"
}
agent_id=$(omnigent_get agents | jq -er \
  '.data[] | select(.name == "automation-developer") | .id')

session_ids=()
cursor=
while :; do
  page=$(omnigent_get "sessions?limit=100${cursor:+&after=$cursor}")
  mapfile -t page_ids < <(jq -r --arg agent "$agent_id" \
    '.data[] | select(.agent_id == $agent) | .id' <<<"$page")
  session_ids+=("${page_ids[@]}")
  [[ $(jq -r '.has_more' <<<"$page") == true ]] || break
  cursor=$(jq -er '.last_id' <<<"$page")
done
for session_id in "${session_ids[@]}"; do
  curl -fsS -o /dev/null -X DELETE --user "$client_id:$client_secret" \
    "$omnigent_api/sessions/$session_id"
done
unset client_id client_secret
oc -n omnigent-sandboxes delete sandboxes \
  -l omnigent.ai/agent=automation-developer \
  --ignore-not-found --wait=true --timeout=5m
printf 'Removed %s automation-developer sessions.\n' "${#session_ids[@]}"

# Recreate the bootstrap-owned model and agent configuration from the Go key.
oc -n omnigent-sandboxes delete secret omnigent-model --ignore-not-found
oc -n omnigent delete secret omnigent-agent --ignore-not-found
MODEL_BASE_URL=https://opencode.ai/zen/go/v1 MODEL_NAME=gpt-6-luna \
  MODEL_PROVIDER='' bash "$repo_root/bootstrap/model-config.sh"
oc -n omnigent rollout status deployment/omnigent --timeout=5m

COLLECTION_SOURCE="$repo_root/cluster/forgejo-demo/fixtures/collection" \
  bash "$repo_root/scripts/feature-demo.sh" reset --confirm-forgejo-demo
bash "$repo_root/cluster/automation-orchestrator/reconcile-omnigent-workflow.sh"
echo 'Demo reset complete: Forgejo reseeded and Omnigent ready for a new AO session.'
