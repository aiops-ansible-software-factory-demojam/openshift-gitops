#!/usr/bin/env bash
set -euo pipefail
oc whoami --show-server
oc whoami

# This namespace is exclusively for ephemeral sessions. Delete even claims
# whose client omitted lifecycle.shutdownTime. Pool inventory is not selected.
cutoff=$(( $(date +%s) - 3600 ))
claims=$(oc -n agent-sandboxes get sandboxclaims.extensions.agents.x-k8s.io \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.creationTimestamp}{"\n"}{end}')
while read -r name created; do
  [[ -n "$name" ]] || continue
  if (( $(date -d "$created" +%s) <= cutoff )); then
    oc -n agent-sandboxes delete sandboxclaim.extensions.agents.x-k8s.io "$name" \
      --ignore-not-found --cascade=foreground --wait=false
  fi
done <<< "$claims"
