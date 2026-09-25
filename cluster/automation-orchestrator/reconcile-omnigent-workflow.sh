#!/usr/bin/env bash
set -euo pipefail

namespace=automation-orchestrator
workflow_name=omnigent-dispatch
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
workflow_file="$script_dir/workflows/omnigent-dispatch.yaml"

oc whoami --show-server
oc whoami
route_host=$(oc -n "$namespace" get route automation-orchestrator -o jsonpath='{.spec.host}')
base_url="https://$route_host/api/v1"
admin_password=$(oc -n "$namespace" get secret automation-orchestrator-admin-password \
  -o go-template='{{index .data "password" | base64decode}}')
login_payload=$(jq -n --arg password "$admin_password" \
  '{username:"admin",password:$password}')
unset admin_password
ao_token=$(curl -fsS -H 'Content-Type: application/json' --data-binary @- \
  "$base_url/auth/login" <<<"$login_payload" | jq -er '.access_token')
unset login_payload
auth_header="Authorization: Bearer $ao_token"
project_id=$(curl -fsS -H "$auth_header" "$base_url/projects" | jq -r \
  '.resources[] | select(.name == "default") | .id')
workflow_definition=$(yq -c '.' "$workflow_file")
validation_payload=$(jq -n --argjson definition "$workflow_definition" \
  '{workflow_definition: $definition}')
curl -fsS -H "$auth_header" -H 'Content-Type: application/json' \
  --data-binary @- "$base_url/workflows/validate" \
  <<<"$validation_payload" | jq -e '.is_valid == true' >/dev/null

workflow_id=$(curl -fsS -H "$auth_header" "$base_url/workflows?limit=100" |
  jq -r --arg name "$workflow_name" \
    '.resources[]? | select(.name == $name and .is_builtin == false) | .id' | head -1)
if [[ -z "$workflow_id" ]]; then
  payload=$(jq -n --arg name "$workflow_name" --arg project_id "$project_id" \
    --argjson definition "$workflow_definition" \
    '{name:$name,project_id:$project_id,workflow_definition:$definition}')
  response=$(curl -fsS -H "$auth_header" -H 'Content-Type: application/json' \
    --data-binary @- "$base_url/workflows" <<<"$payload")
  workflow_id=$(jq -r '.id' <<<"$response")
  workflow_version=$(jq -r '.current_version' <<<"$response")
  publish_needed=true
else
  response=$(curl -fsS -H "$auth_header" "$base_url/workflows/$workflow_id")
  workflow_version=$(jq -r '.current_version' <<<"$response")
  published_version=$(jq -r '.published_version_number // 0' <<<"$response")
  publish_needed=false
  current_definition=$(curl -fsS -H "$auth_header" \
    "$base_url/workflows/$workflow_id/versions/$workflow_version" |
    jq '.workflow_definition')
  if [[ $(jq -S -c . <<<"$current_definition") != \
        $(jq -S -c . <<<"$workflow_definition") ]]; then
    payload=$(jq -n --argjson expected_version "$workflow_version" \
      --argjson definition "$workflow_definition" \
      '{expected_version:$expected_version,workflow_definition:$definition}')
    response=$(curl -fsS -X PATCH -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary @- \
      "$base_url/workflows/$workflow_id" <<<"$payload")
    workflow_version=$(jq -r '.current_version' <<<"$response")
    publish_needed=true
  elif [[ "$published_version" != "$workflow_version" ]]; then
    publish_needed=true
  fi
fi

if [[ "$publish_needed" == true ]]; then
  payload=$(jq -n '{publish_name:"GitOps demo",change_description:"Reconciled from openshift-gitops"}')
  curl -fsS -H "$auth_header" -H 'Content-Type: application/json' \
    --data-binary @- "$base_url/workflows/$workflow_id/versions/$workflow_version/publish" \
    <<<"$payload" >/dev/null
fi
printf 'Reconciled workflow %s version %s\n' "$workflow_name" "$workflow_version"
