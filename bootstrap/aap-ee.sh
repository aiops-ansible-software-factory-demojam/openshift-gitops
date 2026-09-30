#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
: "${RH_AUTOMATIONHUB_TOKEN:?Populate RH_AUTOMATIONHUB_TOKEN in .env}"
demo_verify_cluster
namespace=ansible-automation-platform
umask 077
scratch=$(mktemp -d)
cleanup_build_pods() {
  local -a pods
  mapfile -t pods < <(oc -n "$namespace" get pods -o json | jq -r '
    .items[] | select(.metadata.name | test("^demo-aap-ee-[0-9]+-build$")) |
    select(.status.phase == "Succeeded" or .status.phase == "Failed") | .metadata.name')
  if (( ${#pods[@]} > 0 )); then
    oc -n "$namespace" delete pod "${pods[@]}" --ignore-not-found >/dev/null
  fi
}
cleanup() {
  find "$scratch" -type f -delete
  find "$scratch" -depth -type d -empty -delete
  oc -n "$namespace" delete secret aap-ee-automation-hub --ignore-not-found >/dev/null
  # Build status and output images remain; terminal build pods hold large caches.
  cleanup_build_pods
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
ansible-builder create -f "$demo_repo_root/execution-environment.yml" \
  --context "$scratch/context" --output-filename Containerfile
tar -czf "$scratch/context.tar.gz" -C "$scratch/context" .
build=$(oc -n "$namespace" start-build demo-aap-ee \
  --from-archive="$scratch/context.tar.gz" -o name)
echo "Started $build"
# A long log stream can close while the build continues. Build phase, rather
# than the transport connection, determines whether bootstrap succeeds.
oc -n "$namespace" logs "$build" --follow ||
  echo 'Build log stream ended; waiting on the Build resource.' >&2
deadline=$((SECONDS + 2700))
while :; do
  phase=$(oc -n "$namespace" get "$build" -o jsonpath='{.status.phase}')
  case "$phase" in
    Complete) break ;;
    Failed|Error|Cancelled)
      echo "$build ended with phase $phase." >&2; exit 1 ;;
  esac
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for $build ($phase)." >&2; exit 1
  fi
  sleep 10
done
echo "$build completed."
cleanup_build_pods
# SNO may need kubelet's pressure transition period after unpacking large images.
# Do not schedule AAP jobs until the node can admit them normally.
oc wait nodes --all \
  --for='jsonpath={.status.conditions[?(@.type=="DiskPressure")].status}=False' \
  --timeout=15m
