#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rendered=.rendered/cluster.yaml

test "$(yq -r 'select(.kind == "AppProject") | .metadata.name' "$rendered")" = cluster-config
test "$(yq -r 'select(.kind == "Application") | .metadata.name' "$rendered" | wc -l)" -eq 9
test "$(yq -r 'select(.kind == "Application" and .metadata.name == "cloudnative-pg") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 0
test "$(yq -r 'select(.kind == "Application" and .metadata.name == "agent-sandboxes") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 20
test "$(yq -r 'select(.kind == "Application" and .metadata.name != "cloudnative-pg" and .metadata.name != "agent-sandboxes") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered" | sort -u)" = 10

while read -r name path; do
  test "$path" = "cluster/$name"
  test -f "$path/kustomization.yaml"
done < <(yq -r 'select(.kind == "Application") | [.metadata.name, .spec.source.path] | @tsv' "$rendered")

rhbk=.rendered/rhbk.yaml
test "$(yq -r 'select(.kind == "OperatorGroup" or .kind == "Subscription" or .kind == "Keycloak" or .kind == "Route") | .kind' "$rhbk" | wc -l)" -eq 4
test "$(yq -r 'select(.kind == "Secret" or .kind == "Deployment" or .kind == "PersistentVolumeClaim" or .kind == "Cluster") | .kind' "$rhbk" | wc -l)" -eq 0

echo 'The app-of-apps chart renders the project, nine paths and expected waves.'
echo 'RHBK adopts the environment Keycloak without managing its database, data or secrets.'
