#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
: "${RH_AUTOMATIONHUB_TOKEN:?Populate RH_AUTOMATIONHUB_TOKEN in .env}"
demo_verify_cluster
namespace=ansible-automation-platform
active_runs=$(oc -n "$namespace" get pipelineruns -l tekton.dev/pipeline=demojam-ee -o json |
  jq '[.items[] | select((.status.conditions[0].status // "Unknown") == "Unknown")] | length')
[[ $active_runs == 0 ]] || { echo 'An EE build is already active; inspect it before restarting.' >&2; exit 1; }
# Release caches from terminal runs, preserving the failed logs until this next run.
while read -r completed; do
  oc -n "$namespace" delete pod,pvc,statefulset -l "tekton.dev/pipelineRun=$completed" --ignore-not-found >/dev/null
done < <(oc -n "$namespace" get pipelineruns -l tekton.dev/pipeline=demojam-ee -o json |
  jq -r '.items[] | select(.status.conditions[0].status == "True" or .status.conditions[0].status == "False") | .metadata.name')
oc wait nodes --all --for='jsonpath={.status.conditions[?(@.type=="DiskPressure")].status}=False' --timeout=15m
umask 077
scratch=$(mktemp -d)
run=
# Invoked by the EXIT trap.
# shellcheck disable=SC2317
cleanup() {
  find "$scratch" -type f -delete
  find "$scratch" -depth -type d -empty -delete
  # Keep logs/status, but release large task caches and the workspace disk.
  # Leave credentials mounted if an interrupted script's build is still active.
  if [[ -n $run ]] && [[ $(oc -n "$namespace" get "$run" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null) =~ ^(True|False)$ ]]; then
    if [[ $(oc -n "$namespace" get "$run" -o jsonpath='{.status.conditions[0].status}') == True ]]; then
      oc -n "$namespace" delete pod,pvc,statefulset -l "tekton.dev/pipelineRun=${run##*/}" --ignore-not-found >/dev/null
    fi
    oc -n "$namespace" delete secret aap-ee-automation-hub --ignore-not-found >/dev/null
  fi
}
trap cleanup EXIT
cat > "$scratch/ansible.cfg" <<EOF
[galaxy]
server_list = rh_certified, community
[galaxy_server.rh_certified]
url = https://console.redhat.com/api/automation-hub/content/published/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token = $RH_AUTOMATIONHUB_TOKEN
[galaxy_server.community]
url = https://galaxy.ansible.com/
EOF
oc -n "$namespace" create secret generic aap-ee-automation-hub \
  --from-file="ansible.cfg=$scratch/ansible.cfg" --dry-run=client -o json |
  oc -n "$namespace" apply -f - >/dev/null
# One deliberate run; no trigger or automatic CI is installed.
run=$(oc -n "$namespace" create -f "$demo_repo_root/bootstrap/aap-ee-pipelinerun.yaml" -o name)
echo "Started $run"
deadline=$((SECONDS + 3600))
while (( SECONDS < deadline )); do
  if ! status=$(oc -n "$namespace" get "$run" --request-timeout=30s -o json); then
    echo 'Pipeline status is temporarily unavailable; retrying.' >&2
    sleep 10
    continue
  fi
  condition=$(jq -r '.status.conditions[]? | select(.type=="Succeeded") | .status' <<< "$status")
  case "$condition" in
    True)
      jq -r '.status.results[]? | "\(.name)=\(.value)"' <<< "$status"
      echo "$run completed."
      exit ;;
    False)
      jq -r '.status.conditions[] | select(.type=="Succeeded") | .message' <<< "$status" >&2
      echo "Inspect task logs for $run." >&2; exit 1 ;;
  esac
  sleep 10
done
echo "Timed out waiting for $run; inspect it before starting another build." >&2
exit 1
