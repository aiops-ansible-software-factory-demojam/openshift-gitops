#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp)
trap 'rm -f "$scratch"' EXIT
for kind in Application Subscription Cluster Database SandboxTemplate SandboxWarmPool AnsibleAutomationPlatform AutomationOrchestrator Keycloak; do
  yq -r ".spec.resourceHealthChecks[] | select(.kind == \"$kind\") | .check" \
    bootstrap/config/openshift-gitops-argocd.yaml > "$scratch"
  "${LUA:-lua}" tests/health.lua "$scratch" "$kind"
done
