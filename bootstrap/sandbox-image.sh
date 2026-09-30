#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
demo_verify_cluster
namespace=omnigent-sandboxes
active_runs=$(oc -n "$namespace" get pipelineruns -l tekton.dev/pipeline=omnigent-opencode -o json |
  jq '[.items[] | select((.status.conditions[0].status // "Unknown") == "Unknown")] | length')
[[ $active_runs == 0 ]] || { echo 'A sandbox image build is already active; inspect it before restarting.' >&2; exit 1; }
# Release caches from terminal runs, preserving the failed logs until this next run.
while read -r completed; do
  oc -n "$namespace" delete pod,pvc,statefulset -l "tekton.dev/pipelineRun=$completed" --ignore-not-found >/dev/null
done < <(oc -n "$namespace" get pipelineruns -l tekton.dev/pipeline=omnigent-opencode -o json |
  jq -r '.items[] | select(.status.conditions[0].status == "True" or .status.conditions[0].status == "False") | .metadata.name')
oc wait nodes --all --for='jsonpath={.status.conditions[?(@.type=="DiskPressure")].status}=False' --timeout=15m
# One deliberate run; no trigger or automatic CI is installed.
run=$(yq '.' "$demo_repo_root/bootstrap/sandbox-image-pipelinerun.yaml" |
  jq --arg revision "${SANDBOX_BUILD_REVISION:-$(git -C "$demo_repo_root" rev-parse HEAD)}" \
    '.spec.params[0].value = $revision' |
  oc -n "$namespace" create -f - -o name)
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
      oc -n "$namespace" delete pod,pvc,statefulset -l "tekton.dev/pipelineRun=${run##*/}" --ignore-not-found >/dev/null
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
