#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rendered=.rendered/cluster.yaml

yq_docs() {
  yq -r "$@" | grep -v '^---$' | grep -v '^[[:space:]]*$'
}

test "$(yq_docs 'select(.kind == "AppProject") | .metadata.name' "$rendered")" = cluster-config
test "$(yq_docs 'select(.kind == "Application") | .metadata.name' "$rendered" | wc -l)" -eq 10
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "cloudnative-pg") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 0
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "agent-sandboxes") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 20
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "automation-orchestrator") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 30
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "forgejo-demo") | .spec.source.path' "$rendered")" = cluster/forgejo-demo
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "forgejo-demo") | .spec.ignoreDifferences[].jsonPointers[]' "$rendered")" = /spec/replicas
test "$(yq_docs 'select(.kind == "Application" and .metadata.name != "cloudnative-pg" and .metadata.name != "agent-sandboxes" and .metadata.name != "automation-orchestrator") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered" | sort -u)" = 10

while read -r name path; do
  test "$path" = "cluster/$name"
  test -f "$path/kustomization.yaml"
done < <(yq_docs 'select(.kind == "Application") | [.metadata.name, .spec.source.path] | @tsv' "$rendered")

rhbk=.rendered/rhbk.yaml
test "$(yq_docs 'select(.kind == "Namespace" or .kind == "OperatorGroup" or .kind == "Subscription" or .kind == "Keycloak" or .kind == "Route") | .kind' "$rhbk" | wc -l)" -eq 5
test "$(yq_docs 'select(.kind == "Secret" or .kind == "Deployment" or .kind == "PersistentVolumeClaim" or .kind == "Cluster") | .kind' "$rhbk" | wc -l)" -eq 0
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "rhbk") | .spec.ignoreDifferences[] | .kind' "$rendered")" = Keycloak
test "$(yq_docs 'select(.kind == "Keycloak") | .spec.hostname.hostname' "$rhbk")" = sso.apps.cluster-qb5wm.dyn.redhatworkshops.io

echo 'The app-of-apps chart renders the project, ten paths and expected waves.'
echo 'RHBK adopts the environment Keycloak without managing its database, data or secrets.'
