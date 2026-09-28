#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rendered=.rendered/cluster.yaml

yq_docs() {
  yq -r "$@" | grep -v '^---$' | grep -v '^[[:space:]]*$'
}

test "$(yq_docs 'select(.kind == "AppProject") | .metadata.name' "$rendered")" = cluster-config
test "$(yq_docs 'select(.kind == "AppProject") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = -1
test "$(yq_docs 'select(.kind == "Application") | .metadata.name' "$rendered" | wc -l)" -eq 6
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "cloudnative-pg") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 0
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "agent-sandbox-operator") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 10
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "omnigent") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 30
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "automation-orchestrator") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered")" = 30
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "forgejo-demo") | .spec.source.path' "$rendered")" = cluster/forgejo-demo
test "$(yq_docs 'select(.kind == "Application" and .metadata.name == "forgejo-demo") | .spec.ignoreDifferences[].jsonPointers[]' "$rendered")" = /spec/replicas
test "$(yq_docs 'select(.kind == "Application" and .metadata.name != "cloudnative-pg" and .metadata.name != "omnigent" and .metadata.name != "automation-orchestrator") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered" | sort -u)" = 10

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
rg -q 'baseUrl: \$\{RHDH_URL\}' cluster/rhdh/app-config-rhdh-configmap.yaml
test "$(yq_docs 'select(.kind == "AutomationOrchestrator") | .spec.ingress.host' .rendered/automation-orchestrator.yaml)" = null
test "$(yq_docs 'select(.kind == "AutomationOrchestrator") | .spec.workflowHttpRequestAllowedHosts[0]' .rendered/automation-orchestrator.yaml)" = omnigent.omnigent.svc
test "$(yq_docs '.nodes[] | select(.id == "create_session") | .parameters.url' cluster/automation-orchestrator/workflows/omnigent-dispatch.yaml)" = http://omnigent.omnigent.svc:8080/v1/sessions
test "$(yq -r '.nodes[] | select(.id == "create_session") | .parameters.body.initial_items | length' cluster/automation-orchestrator/workflows/omnigent-dispatch.yaml)" = 0
test "$(yq -r '.triggers[0].parameters.input_schema.properties.issue_number.type' cluster/automation-orchestrator/workflows/omnigent-dispatch.yaml)" = integer
rg -q 'forgejo-issue start \$\{trigger.issue_number\}' cluster/automation-orchestrator/workflows/omnigent-dispatch.yaml
test "$(yq_docs '.nodes[] | select(.id == "send_task") | .parameters.url' cluster/automation-orchestrator/workflows/omnigent-dispatch.yaml)" = 'http://omnigent.omnigent.svc:8080/v1/sessions/${create_session.body.id}/events'
test "$(yq_docs '.edges[] | select(.from == "create_session" and .to == "send_task") | .to' cluster/automation-orchestrator/workflows/omnigent-dispatch.yaml)" = send_task
if rg -q 'apps\.cluster-' cluster -g '*.yaml' -g '!**/charts/**'; then
  echo 'A cluster-specific ingress domain remains in a GitOps manifest.' >&2
  exit 1
fi
for app in forgejo-demo omnigent; do
  rendered_app=".rendered/$app.yaml"
  test "$(yq_docs 'select(.kind == "PersistentVolumeClaim") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered_app")" = \
    "$(yq_docs 'select(.kind == "Deployment") | .metadata.annotations."argocd.argoproj.io/sync-wave"' "$rendered_app")"
done
test "$(yq_docs 'select(.kind == "ImageStream") | .metadata.annotations."argocd.argoproj.io/sync-wave"' .rendered/omnigent.yaml)" = \
  "$(yq_docs 'select(.kind == "BuildConfig") | .metadata.annotations."argocd.argoproj.io/sync-wave"' .rendered/omnigent.yaml)"
test "$(yq_docs 'select(.kind == "ConfigMap" and .metadata.name == "omnigent-sandbox-config") | .data."config.yaml"' .rendered/omnigent.yaml | yq -r '.sandbox.provider')" = agent_sandbox
rg -q 'FORGEJO_TOKEN' cluster/omnigent/omnigent-config-configmap.yaml

echo 'The app-of-apps chart renders the project, six active paths and expected waves.'
echo 'RHBK adopts the environment Keycloak without managing its database, data or secrets.'
