#!/usr/bin/env bash
set -euo pipefail

# Publish workflows/omnigent-dispatch.yaml into a live Automation Orchestrator.
# Prefer the operator-managed Route. Port-forward is opt-in for environments
# where the Route is unreachable from the bootstrap host.

namespace=automation-orchestrator
workflow_name=omnigent-dispatch
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
workflow_file="$script_dir/workflows/omnigent-dispatch.yaml"
ao_local_port=${AO_LOCAL_PORT:-18080}

oc whoami --show-server
oc whoami

ao_response=$(mktemp)
pf_log=$(mktemp)
pf_pid=
trap '[[ -n ${pf_pid:-} ]] && kill "$pf_pid" 2>/dev/null || true
  rm -f "$ao_response" "$pf_log"' EXIT

ao_response_is_json() {
  jq -e . "$ao_response" >/dev/null 2>&1
}

ao_curl() {
  local method=$1 url=$2 http_code=000
  shift 2
  http_code=$(curl -sS -o "$ao_response" -w '%{http_code}' \
    -X "$method" "$@" "$url" 2>/dev/null) || true
  printf '%s' "${http_code:-000}"
}

ao_http_ok() {
  [[ "$1" =~ ^2[0-9][0-9]$ ]]
}

ao_fail_response() {
  local action=$1 http_code=$2
  echo "Automation Orchestrator $action failed (HTTP $http_code)." >&2
  if [[ -s "$ao_response" ]]; then
    if ao_response_is_json; then
      jq -r '.detail // .title // .message // .' "$ao_response" >&2 || true
    else
      cat "$ao_response" >&2
      printf '\n' >&2
    fi
  fi
  exit 1
}

ao_require_json() {
  local action=$1 http_code=$2
  if ! ao_http_ok "$http_code" || ! ao_response_is_json; then
    ao_fail_response "$action" "$http_code"
  fi
}

wait_for_ao_instance() {
  echo 'Waiting for the Automation Orchestrator instance...'
  oc -n "$namespace" wait --for=condition=Ready \
    automationorchestrator/automation-orchestrator --timeout=15m
  for deploy in automation-orchestrator-ui automation-orchestrator-backend; do
    if oc -n "$namespace" get "deployment/$deploy" >/dev/null 2>&1; then
      oc -n "$namespace" rollout status "deployment/$deploy" --timeout=10m
    fi
  done
}

resolve_route_base_url() {
  local host
  host=$(oc -n "$namespace" get route automation-orchestrator \
    -o jsonpath='{.status.ingress[0].host}' 2>/dev/null || true)
  if [[ -z "$host" ]]; then
    host=$(oc -n "$namespace" get route -o jsonpath='{.items[0].status.ingress[0].host}' \
      2>/dev/null || true)
  fi
  if [[ -z "$host" ]]; then
    echo 'Automation Orchestrator Route has no assigned host.' >&2
    return 1
  fi
  printf 'https://%s/api/v1' "$host"
}

start_port_forward() {
  local svc port deadline http_code
  if ! oc -n "$namespace" get svc automation-orchestrator-ui >/dev/null 2>&1; then
    echo 'Service automation-orchestrator-ui was not found.' >&2
    oc -n "$namespace" get svc -o name >&2 || true
    return 1
  fi
  svc=automation-orchestrator-ui
  port=$(oc -n "$namespace" get svc "$svc" \
    -o jsonpath='{.spec.ports[?(@.name=="http")].port}')
  if [[ -z "$port" ]]; then
    port=$(oc -n "$namespace" get svc "$svc" -o jsonpath='{.spec.ports[0].port}')
  fi
  if [[ -z "$port" ]]; then
    echo "Service $svc has no ports." >&2
    return 1
  fi
  : >"$pf_log"
  oc -n "$namespace" port-forward "svc/$svc" "$ao_local_port:$port" \
    >"$pf_log" 2>&1 &
  pf_pid=$!
  deadline=$((SECONDS + 30))
  until http_code=$(ao_curl GET \
    "http://127.0.0.1:$ao_local_port/api/v1/auth/providers") &&
    [[ "$http_code" != 000 ]]; do
    if ! kill -0 "$pf_pid" 2>/dev/null; then
      echo 'Port-forward exited before the local port was ready.' >&2
      [[ -s "$pf_log" ]] && cat "$pf_log" >&2
      pf_pid=
      return 1
    fi
    if (( SECONDS >= deadline )); then
      kill "$pf_pid" 2>/dev/null || true
      pf_pid=
      echo 'Timed out waiting for the Automation Orchestrator port-forward.' >&2
      [[ -s "$pf_log" ]] && cat "$pf_log" >&2
      return 1
    fi
    sleep 1
  done
  printf 'http://127.0.0.1:%s/api/v1' "$ao_local_port"
}

resolve_base_url() {
  if [[ -n ${AO_API_BASE_URL:-} ]]; then
    printf '%s' "$AO_API_BASE_URL"
    return 0
  fi
  if [[ ${AO_USE_PORT_FORWARD:-false} == true ]]; then
    start_port_forward
    return
  fi
  resolve_route_base_url
}

wait_for_ao_api() {
  local base_url=$1 deadline=$((SECONDS + 600)) http_code
  echo "Waiting for the Automation Orchestrator API at $base_url ..."
  until http_code=$(ao_curl GET "$base_url/auth/providers") &&
    ao_http_ok "$http_code" && ao_response_is_json &&
    jq -e '.providers | type == "array"' "$ao_response" >/dev/null 2>&1; do
    if [[ -n ${pf_pid:-} ]] && ! kill -0 "$pf_pid" 2>/dev/null; then
      echo 'The Automation Orchestrator port-forward exited early.' >&2
      [[ -s "$pf_log" ]] && cat "$pf_log" >&2
      exit 1
    fi
    if (( SECONDS >= deadline )); then
      echo "Last readiness response from $base_url/auth/providers:" >&2
      ao_fail_response 'readiness check' "${http_code:-000}"
    fi
    sleep 5
  done
}

read_admin_password() {
  local secret=$1
  oc -n "$namespace" get secret "$secret" \
    -o go-template='{{index .data "password" | base64decode}}' 2>/dev/null || true
}

last_login_code=000
ao_login() {
  local base_url=$1 password=$2 http_code login_payload
  login_payload=$(jq -n --arg password "$password" \
    '{username:"admin",password:$password}')
  http_code=$(ao_curl POST "$base_url/auth/login" \
    -H 'Content-Type: application/json' --data-binary "$login_payload")
  unset login_payload
  last_login_code=$http_code
  if ao_http_ok "$http_code" && ao_response_is_json &&
     jq -e '.access_token | type == "string" and length > 0' \
       "$ao_response" >/dev/null 2>&1; then
    jq -r '.access_token' "$ao_response"
    return 0
  fi
  return 1
}

wait_for_ao_instance
base_url=$(resolve_base_url)
wait_for_ao_api "$base_url"

ao_token=
for secret in automation-orchestrator-admin-password \
  automation-orchestrator-initial-admin-password; do
  admin_password=$(read_admin_password "$secret")
  if [[ -z "$admin_password" ]]; then
    continue
  fi
  if ao_token=$(ao_login "$base_url" "$admin_password"); then
    unset admin_password
    break
  fi
  unset admin_password
done
if [[ -z ${ao_token:-} ]]; then
  echo 'Could not authenticate to the Automation Orchestrator API.' >&2
  echo 'Tried automation-orchestrator-admin-password and' >&2
  echo 'automation-orchestrator-initial-admin-password.' >&2
  ao_fail_response 'login' "$last_login_code"
fi
auth_header="Authorization: Bearer $ao_token"

http_code=$(ao_curl GET "$base_url/projects" -H "$auth_header")
ao_require_json 'list projects' "$http_code"
project_id=$(jq -r '.resources[] | select(.name == "default") | .id' \
  "$ao_response")
if [[ -z $project_id || $project_id == null ]]; then
  echo 'The default Automation Orchestrator project was not found.' >&2
  exit 1
fi

credential_name=omnigent-machine-client
http_code=$(ao_curl GET "$base_url/credential_types?limit=100" -H "$auth_header")
ao_require_json 'list credential types' "$http_code"
credential_type_id=$(jq -r \
  '.resources[] | select(.name == "HTTP Basic Auth") | .id' "$ao_response")
if [[ -z $credential_type_id || $credential_type_id == null ]]; then
  echo 'The HTTP Basic Auth credential type was not found.' >&2
  exit 1
fi

http_code=$(ao_curl GET "$base_url/credentials?limit=100" -H "$auth_header")
ao_require_json 'list credentials' "$http_code"
credential_id=$(jq -r --arg name "$credential_name" \
  '.resources[]? | select(.name == $name) | .id' "$ao_response" | head -1)

client_id=$(oc -n "$namespace" get secret omnigent-machine-client-credential \
  -o go-template='{{index .data "username" | base64decode}}')
client_secret=$(oc -n "$namespace" get secret omnigent-machine-client-credential \
  -o go-template='{{index .data "password" | base64decode}}')
if [[ -z ${credential_id:-} ]]; then
  credential_payload=$(jq -n --arg name "$credential_name" \
    --arg project_id "$project_id" --arg type_id "$credential_type_id" \
    --arg username "$client_id" --arg password "$client_secret" \
    '{name:$name,project_id:$project_id,credential_type_id:$type_id,
      inputs:{username:$username,password:$password}}')
  http_code=$(ao_curl POST "$base_url/credentials" -H "$auth_header" \
    -H 'Content-Type: application/json' --data-binary "$credential_payload")
  unset credential_payload
  ao_require_json 'create credential' "$http_code"
  credential_id=$(jq -r '.id' "$ao_response")
fi

omnigent_host=$(oc -n omnigent get route omnigent \
  -o jsonpath='{.status.ingress[0].host}')
[[ -n "$omnigent_host" ]] || { echo 'Omnigent Route has no assigned host.' >&2; exit 1; }
omnigent_url="https://$omnigent_host"
http_code=$(ao_curl GET "$omnigent_url/v1/agents" --user "$client_id:$client_secret")
unset client_secret
ao_require_json 'list Omnigent agents' "$http_code"
agent_id=$(jq -r '.data[] | select(.name == "demo") | .id' "$ao_response")
if [[ -z ${agent_id:-} || $agent_id == null ]]; then
  echo 'The Omnigent demo agent was not found.' >&2
  exit 1
fi

workflow_definition=$(yq -c '.' "$workflow_file" | jq -c \
  --arg credential_id "$credential_id" --arg agent_id "$agent_id" \
  '.nodes |= map(if .id == "create_session" then
      .parameters.credential_id = $credential_id |
      .parameters.body.agent_id = $agent_id
    elif .id == "send_task" then .parameters.credential_id = $credential_id
    else . end)')
validation_payload=$(jq -n --argjson definition "$workflow_definition" \
  '{workflow_definition: $definition}')
http_code=$(ao_curl POST "$base_url/workflows/validate" -H "$auth_header" \
  -H 'Content-Type: application/json' --data-binary "$validation_payload")
ao_require_json 'validate workflow' "$http_code"
jq -e '.is_valid == true' "$ao_response" >/dev/null ||
  ao_fail_response 'validate workflow' "$http_code"

http_code=$(ao_curl GET "$base_url/workflows?limit=100" -H "$auth_header")
ao_require_json 'list workflows' "$http_code"
workflow_id=$(jq -r --arg name "$workflow_name" \
  '.resources[]? | select(.name == $name and .is_builtin == false) | .id' \
  "$ao_response" | head -1)
if [[ -z ${workflow_id:-} ]]; then
  payload=$(jq -n --arg name "$workflow_name" --arg project_id "$project_id" \
    --argjson definition "$workflow_definition" \
    '{name:$name,project_id:$project_id,workflow_definition:$definition}')
  http_code=$(ao_curl POST "$base_url/workflows" -H "$auth_header" \
    -H 'Content-Type: application/json' --data-binary "$payload")
  ao_require_json 'create workflow' "$http_code"
  workflow_id=$(jq -r '.id' "$ao_response")
  workflow_version=$(jq -r '.current_version' "$ao_response")
  publish_needed=true
else
  http_code=$(ao_curl GET "$base_url/workflows/$workflow_id" -H "$auth_header")
  ao_require_json 'read workflow' "$http_code"
  workflow_version=$(jq -r '.current_version' "$ao_response")
  published_version=$(jq -r '.published_version_number // 0' "$ao_response")
  publish_needed=false
  http_code=$(ao_curl GET \
    "$base_url/workflows/$workflow_id/versions/$workflow_version" \
    -H "$auth_header")
  ao_require_json 'read workflow version' "$http_code"
  current_definition=$(jq -c '.workflow_definition' "$ao_response")
  if [[ $(jq -S -c . <<<"$current_definition") != \
        $(jq -S -c . <<<"$workflow_definition") ]]; then
    payload=$(jq -n --argjson expected_version "$workflow_version" \
      --argjson definition "$workflow_definition" \
      '{expected_version:$expected_version,workflow_definition:$definition}')
    http_code=$(ao_curl PATCH "$base_url/workflows/$workflow_id" \
      -H "$auth_header" -H 'Content-Type: application/json' \
      --data-binary "$payload")
    ao_require_json 'update workflow' "$http_code"
    workflow_version=$(jq -r '.current_version' "$ao_response")
    publish_needed=true
  elif [[ "$published_version" != "$workflow_version" ]]; then
    publish_needed=true
  fi
fi

if [[ "$publish_needed" == true ]]; then
  payload=$(jq -n \
    '{publish_name:"GitOps demo",change_description:"Reconciled from openshift-gitops"}')
  http_code=$(ao_curl POST \
    "$base_url/workflows/$workflow_id/versions/$workflow_version/publish" \
    -H "$auth_header" -H 'Content-Type: application/json' \
    --data-binary "$payload")
  ao_require_json 'publish workflow' "$http_code"
fi
printf 'Reconciled workflow %s version %s\n' "$workflow_name" "$workflow_version"
