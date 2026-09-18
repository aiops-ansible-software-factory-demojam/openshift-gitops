#!/usr/bin/env bash
set -euo pipefail

namespace=automation-orchestrator
workflow_name=sandbox-hello-world-direct-api
credential_name=agent-sandbox-api
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
workflow_file="$script_dir/workflows/sandbox-hello-world-direct-api.json"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

oc whoami --show-server
oc whoami

# Build one trust bundle that retains public roots and adds the Kubernetes API
# signer. The AutomationOrchestrator CRD has no worker CA/volume fields yet.
oc -n openshift-config-managed get configmap trusted-ca-bundle \
  -o jsonpath='{.data.ca-bundle\.crt}' >"$scratch/platform-ca.crt"
oc -n "$namespace" get configmap kube-root-ca.crt \
  -o jsonpath='{.data.ca\.crt}' >"$scratch/kubernetes-ca.crt"
cp "$scratch/platform-ca.crt" "$scratch/combined-ca.crt"
printf '\n' >>"$scratch/combined-ca.crt"
sed -n '1,$p' "$scratch/kubernetes-ca.crt" >>"$scratch/combined-ca.crt"

oc -n "$namespace" create configmap automation-orchestrator-http-ca-bundle \
  --from-file=ca.crt="$scratch/combined-ca.crt" \
  --dry-run=client -o yaml | oc apply -f -
oc -n "$namespace" set volume deployment/automation-orchestrator-worker \
  --add --overwrite --name=http-ca-bundle --type=configmap \
  --configmap-name=automation-orchestrator-http-ca-bundle \
  --mount-path=/var/run/orchestrator-http-ca --read-only
if oc -n "$namespace" get deployment automation-orchestrator-worker -o json |
  jq -e '.spec.template.spec.volumes[]? | select(.name == "kube-root-ca")' \
    >/dev/null; then
  oc -n "$namespace" set volume deployment/automation-orchestrator-worker \
    --remove --name=kube-root-ca
fi
oc -n "$namespace" set env deployment/automation-orchestrator-worker \
  SSL_CERT_FILE=/var/run/orchestrator-http-ca/ca.crt \
  REQUESTS_CA_BUNDLE=/var/run/orchestrator-http-ca/ca.crt
oc -n "$namespace" rollout status deployment/automation-orchestrator-worker \
  --timeout=180s

route_host=$(oc -n "$namespace" get route automation-orchestrator \
  -o jsonpath='{.spec.host}')
base_url="https://$route_host/api/v1"
admin_password=${AO_ADMIN_PASSWORD:-}
if [[ -z "$admin_password" ]]; then
  admin_password=$(oc -n "$namespace" get secret \
    automation-orchestrator-admin-password \
    -o go-template='{{index .data "password" | base64decode}}')
fi

login_payload=$(jq -n --arg password "$admin_password" \
  '{username:"admin",password:$password}')
ao_token=$(curl -fsS -H 'Content-Type: application/json' --data-binary @- \
  "$base_url/auth/login" <<<"$login_payload" | jq -r '.access_token')
auth_header="Authorization: Bearer $ao_token"

project_id=$(curl -fsS -H "$auth_header" "$base_url/projects" | jq -r \
  '.resources[] | select(.name == "default") | .id')
credential_type_id=$(curl -fsS -H "$auth_header" \
  "$base_url/credential_types" | jq -r \
  '.resources[] | select(.name == "HTTP Bearer Token") | .id')
kube_token=$(oc -n agent-sandbox-clients get secret \
  automation-orchestrator-sandbox-api-token \
  -o go-template='{{index .data "token" | base64decode}}')

credential_id=$(curl -fsS -H "$auth_header" \
  "$base_url/credentials?limit=100" | jq -r --arg name "$credential_name" \
  '.resources[]? | select(.name == $name) | .id' | head -1)
if [[ -z "$credential_id" ]]; then
  credential_payload=$(jq -n \
    --arg name "$credential_name" \
    --arg project_id "$project_id" \
    --arg credential_type_id "$credential_type_id" \
    --arg token "$kube_token" \
    '{
      name: $name,
      description: "Namespace-scoped Kubernetes API token for the direct Agent Sandbox prototype",
      project_id: $project_id,
      credential_type_id: $credential_type_id,
      inputs: {token: $token},
      labels: {prototype: "agent-sandbox"}
    }')
  credential_id=$(curl -fsS -H "$auth_header" \
    -H 'Content-Type: application/json' --data-binary @- \
    "$base_url/credentials" <<<"$credential_payload" | jq -r '.id')
fi

workflow_definition=$(jq --arg credential_id "$credential_id" '
  .nodes |= map(
    if .type == "http_request"
    then .parameters.credential_id = $credential_id
    else .
    end
  )
' "$workflow_file")
validation_payload=$(jq -n --argjson definition "$workflow_definition" \
  '{workflow_definition: $definition}')
curl -fsS -H "$auth_header" -H 'Content-Type: application/json' \
  --data-binary @- "$base_url/workflows/validate" \
  <<<"$validation_payload" | jq -e '.is_valid == true' >/dev/null

workflow_id=$(curl -fsS -H "$auth_header" "$base_url/workflows?limit=100" |
  jq -r --arg name "$workflow_name" \
    '.resources[]? | select(.name == $name and .is_builtin == false) | .id' |
  head -1)
if [[ -z "$workflow_id" ]]; then
  workflow_payload=$(jq -n \
    --arg name "$workflow_name" \
    --arg project_id "$project_id" \
    --argjson definition "$workflow_definition" \
    '{
      name: $name,
      description: "Direct Kubernetes API prototype for a one-shot Agent Sandbox hello-world command.",
      project_id: $project_id,
      labels: {prototype: "agent-sandbox", execution: "direct-api"},
      workflow_definition: $definition
    }')
  workflow_response=$(curl -fsS -H "$auth_header" \
    -H 'Content-Type: application/json' --data-binary @- \
    "$base_url/workflows" <<<"$workflow_payload")
  workflow_id=$(jq -r '.id' <<<"$workflow_response")
  workflow_version=$(jq -r '.current_version' <<<"$workflow_response")
  publish_needed=true
else
  workflow_response=$(curl -fsS -H "$auth_header" \
    "$base_url/workflows/$workflow_id")
  workflow_version=$(jq -r '.current_version' <<<"$workflow_response")
  published_version=$(jq -r '.published_version_number // 0' \
    <<<"$workflow_response")
  publish_needed=false
  current_definition=$(curl -fsS -H "$auth_header" \
    "$base_url/workflows/$workflow_id/versions/$workflow_version" |
    jq '.workflow_definition')
  if [[ $(jq -S -c . <<<"$current_definition") != \
        $(jq -S -c . <<<"$workflow_definition") ]]; then
    update_payload=$(jq -n \
      --argjson expected_version "$workflow_version" \
      --argjson definition "$workflow_definition" \
      '{expected_version: $expected_version, workflow_definition: $definition}')
    workflow_response=$(curl -fsS -X PATCH -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary @- \
      "$base_url/workflows/$workflow_id" <<<"$update_payload")
    workflow_version=$(jq -r '.current_version' <<<"$workflow_response")
    publish_needed=true
  elif [[ "$published_version" != "$workflow_version" ]]; then
    publish_needed=true
  fi
fi

if [[ "$publish_needed" == true ]]; then
  publish_payload=$(jq -n \
    '{publish_name:"Reconciled prototype",change_description:"Reconciled from openshift-gitops"}')
  curl -fsS -H "$auth_header" -H 'Content-Type: application/json' \
    --data-binary @- \
    "$base_url/workflows/$workflow_id/versions/$workflow_version/publish" \
    <<<"$publish_payload" >/dev/null
fi

printf 'Reconciled workflow %s version %s\n' "$workflow_name" "$workflow_version"
