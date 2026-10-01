#!/usr/bin/env bash
# Restore the configured demo with its disposable VMs and disks removed.
set -euo pipefail
set +x
# shellcheck source=../bootstrap/env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/env.sh"
[[ ${1:-} == --confirm-demo-reset && $# -eq 1 ]] || {
  echo 'Usage: reset-demo.sh --confirm-demo-reset' >&2
  exit 2
}

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
demo_verify_cluster
ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default \
  -o jsonpath='{.status.domain}')
omnigent_host=$(oc -n omnigent get route omnigent \
  -o jsonpath='{.status.ingress[0].host}')
[[ -n $ingress_domain && $omnigent_host == "omnigent.$ingress_domain" ]] || {
  echo 'Omnigent Route does not match this cluster ingress domain.' >&2
  exit 2
}
# shellcheck source=../bootstrap/model-env.sh
source "$repo_root/bootstrap/model-env.sh"
unset model_key

umask 077
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
demo_omnigent_connect "$scratch" "https://$omnigent_host"
omnigent_api="https://$omnigent_host/v1"
omnigent_get() {
  curl -fsS --config "$scratch/omnigent.conf" "$omnigent_api/$1"
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
  curl -fsS -o /dev/null -X DELETE --config "$scratch/omnigent.conf" \
    "$omnigent_api/sessions/$session_id"
done
rm -f -- "$scratch/omnigent.conf"
oc -n omnigent-sandboxes delete sandboxes \
  -l omnigent.ai/agent=automation-developer \
  --ignore-not-found --wait=true --timeout=5m
printf 'Removed %s automation-developer sessions.\n' "${#session_ids[@]}"

# Use the managed AAP playbooks while their Forgejo project still exists.
demo_wait_for_api
demo_aap reset-vms
# Stop developer sessions first so no test can recreate a VM during cleanup.
oc -n molecule-tests delete virtualmachines \
  -l app.kubernetes.io/part-of=molecule-tests \
  --ignore-not-found --cascade=foreground --wait=true --timeout=5m
for namespace in automation-vms webapp-vms molecule-tests; do
  remaining=$(oc -n "$namespace" get virtualmachines,virtualmachineinstances,datavolumes,persistentvolumeclaims -o name)
  [[ -z $remaining ]] || {
    echo "Demo resources remain in $namespace; inspect them before retrying reset." >&2
    exit 1
  }
done

# Recreate the bootstrap-owned model and agent configuration from the selected provider.
oc -n omnigent-sandboxes delete secret omnigent-model --ignore-not-found
oc -n omnigent delete secret omnigent-agent --ignore-not-found
bash "$repo_root/bootstrap/model-config.sh"
oc -n omnigent rollout status deployment/omnigent --timeout=5m

COLLECTION_SOURCE="$repo_root/cluster/forgejo/fixtures/collection" \
  bash "$repo_root/scripts/feature-demo.sh" reset --confirm-forgejo
bash "$repo_root/cluster/automation-orchestrator/reconcile-omnigent-workflow.sh"
# Refresh project, inventories and config against the new Forgejo baseline.
bash "$repo_root/bootstrap/aap-configure.sh"
echo 'Demo reset complete: VMs and test disks removed, Forgejo reseeded, AAP configured, and Omnigent ready.'
