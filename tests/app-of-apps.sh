#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rendered=.rendered/cluster.yaml

yq_docs() {
  yq -r "$@" | grep -v '^---$' | grep -v '^[[:space:]]*$'
}

test "$(yq_docs 'select(.kind == "AppProject") | .metadata.name' "$rendered")" = cluster-config
test "$(yq_docs 'select(.kind == "AppProject") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = -1
test "$(yq_docs 'select(.kind == "Application") | .metadata.name' "$rendered" | wc -l)" -eq 8
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "cloudnative-pg") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 0
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "openshell") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 20
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "omnigent") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 30
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "automation-orchestrator") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 30
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "forgejo-demo") | .spec.source.path' "$rendered")" = cluster/forgejo-demo
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "forgejo-demo") | .spec.ignoreDifferences[].jsonPointers[]' "$rendered")" = /spec/replicas
test "$(yq_docs 'select(.kind == "Application" and .metadata.name != "cloudnative-pg" and .metadata.name != "openshell" and .metadata.name != "omnigent" and .metadata.name != "automation-orchestrator") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered" | sort -u)" = 10

while read -r name path; do
  test "$path" = "cluster/$name"
  test -f "$path/kustomization.yaml"
done < <(yq_docs 'select(.kind == "Application") | [.metadata.name, .spec.source.path] | @tsv' "$rendered")

rhbk=.rendered/rhbk.yaml
test "$(yq_docs 'select(.kind == "Namespace" or .kind == "OperatorGroup" or .kind == "Subscription" or .kind == "Keycloak" or .kind == "Route") | .kind' "$rhbk" | wc -l)" -eq 5
test "$(yq_docs 'select(.kind == "Secret" or .kind == "Deployment" or .kind == "PersistentVolumeClaim" or .kind == "Cluster") | .kind' "$rhbk" | wc -l)" -eq 0
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "rhbk") | .spec.ignoreDifferences[] | .kind' "$rendered")" = Keycloak
test "$(yq_docs 'select(.kind == "Keycloak") | .spec.hostname.hostname' "$rhbk")" = null
test "$(yq_docs 'select(.kind == "Keycloak") | .spec.hostname.strict' "$rhbk")" = false
test "$(yq_docs 'select(.kind == "Route") | .spec.subdomain' "$rhbk")" = sso
for app in forgejo-demo omnigent; do
  test "$(yq_docs 'select(.kind == "Route") | .spec.host' ".rendered/$app.yaml")" = null
  test "$(yq_docs 'select(.kind == "Route") | .spec.subdomain' ".rendered/$app.yaml")" = "$app"
done
test "$(yq_docs 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "FORGEJO__server__ROOT_URL") | .valueFrom.configMapKeyRef.name' .rendered/forgejo-demo.yaml)" = forgejo-demo-url
test "$(yq_docs 'select(.kind == "Backstage") | .spec.application.route.subdomain' .rendered/rhdh.yaml)" = rhdh
if rg -q 'baseUrl:|origin:' cluster/rhdh/app-config-rhdh-configmap.yaml; then
  echo 'The RHDH app config overrides the ingress-derived base URLs.' >&2
  exit 1
fi
test "$(yq_docs 'select(.kind == "AutomationOrchestrator") | .spec.ingress.host' .rendered/automation-orchestrator.yaml)" = null
test "$(yq_docs 'select(.kind == "AutomationOrchestrator") | .spec.workflowHttpRequestAllowedHosts[0]' .rendered/automation-orchestrator.yaml)" = omnigent.omnigent.svc
test "$(yq_docs '.nodes[] | select(.id == "create_session") | .parameters.url' cluster/automation-orchestrator/workflows/omnigent-dispatch.yaml)" = http://omnigent.omnigent.svc:8080/v1/sessions
if rg -q 'apps\.cluster-' cluster -g '*.yaml' -g '!**/charts/**'; then
  echo 'A cluster-specific ingress domain remains in a GitOps manifest.' >&2
  exit 1
fi
for app in forgejo-demo omnigent; do
  rendered_app=".rendered/$app.yaml"
  test "$(yq_docs 'select(.kind == "PersistentVolumeClaim") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered_app")" = \
    "$(yq_docs 'select(.kind == "Deployment") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered_app")"
done
test "$(yq_docs 'select(.kind == "ImageStream") | .metadata.annotations."argocd.argoproj.io/sync-wave"' .rendered/openshell.yaml)" = \
  "$(yq_docs 'select(.kind == "BuildConfig") | .metadata.annotations."argocd.argoproj.io/sync-wave"' .rendered/openshell.yaml)"

echo 'The app-of-apps chart renders the project, eight paths and expected waves.'
echo 'RHBK adopts the environment Keycloak without managing its database, data or secrets.'
