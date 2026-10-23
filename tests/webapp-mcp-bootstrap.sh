#!/usr/bin/env bash
# Exercise lifecycle and workflow rendering without an installed cluster.
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/bootstrap/bootstrap.sh"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
source_secret="$scratch/source.json"
fixture_root=$scratch

# Only the Secret operations used by demo_mcp_material are simulated. Crypto,
# serialization, renewal decisions and workflow rendering are the real code.
oc() {
  local namespace=
  if [[ $1 == -n ]]; then namespace=$2; shift 2; fi
  if [[ $namespace == openshift-ingress-operator ]]; then
    cat "$fixture_root/first/mcp-ca.crt"; return
  fi
  if [[ $1 == get && $2 == route ]]; then printf keycloak.test; return; fi
  case "$1 $2" in
    'get secret')
      [[ -f $source_secret ]] || return 0
      if [[ ${*: -1} == name ]]; then printf 'secret/webapp-mcp-material\n'
      else cat "$source_secret"; fi
      ;;
    'create secret')
      local result='{"data":{}}' argument name file
      for argument in "$@"; do
        if [[ $argument == --from-file=* ]]; then
          argument=${argument#--from-file=}
          name=${argument%%=*}; file=${argument#*=}
          result=$(jq -c --arg name "$name" --rawfile value "$file" '.data[$name]=($value|@base64)' <<<"$result")
        fi
      done
      printf '%s' "$result"
      ;;
    'apply --server-side') cat >"$source_secret" ;;
    *) printf 'Unexpected cluster operation in test\n' >&2; return 1 ;;
  esac
}

# Simulate only the identity service, retaining the real client configuration,
# token decoding and renewal path. The HTTPS tests verify actual JWT signatures.
demo_identity_connect() { :; }
demo_identity_upsert_client() {
  jq -e '.clientId == "demojam-ao-rca" and .serviceAccountsEnabled and
    (.standardFlowEnabled | not) and (.directAccessGrantsEnabled | not) and
    (.fullScopeAllowed | not) and .attributes["access.token.lifespan"] == "7776000" and
    .protocolMappers[0].config["included.custom.audience"] == "webapp-mcp"' <<<"$1" >/dev/null
}
curl() {
  [[ ${*: -1} == https://keycloak.test/realms/demo/protocol/openid-connect/token ]] || return 1
  local claims header payload
  claims=$(jq -nc --arg jti "$(openssl rand -hex 16)" --argjson exp "$(($(date +%s) + 7776000))" \
    '{iss:"https://keycloak.test/realms/demo",aud:"webapp-mcp",azp:"demojam-ao-rca",jti:$jti,exp:$exp}')
  header=$(printf '%s' '{"alg":"RS256"}' | base64 -w0 | tr '+/' '-_' | tr -d '=')
  payload=$(printf '%s' "$claims" | base64 -w0 | tr '+/' '-_' | tr -d '=')
  jq -nc --arg token "$header.$payload.test-signature" '{access_token:$token}'
}

export DEMO_BACKEND=cnv WEBAPP_MCP_ENABLED=true
for name in first second rotated renewed; do mkdir "$scratch/$name"; done
demo_mcp_material "$scratch/first"
cp "$source_secret" "$scratch/original.json"
demo_mcp_material "$scratch/second"
cmp "$source_secret" "$scratch/original.json"
openssl verify -CAfile "$scratch/first/mcp-ca.crt" -verify_hostname webapp-mcp.webapp-vms.svc \
  "$scratch/first/mcp-tls.crt" >/dev/null
demo_mcp_material "$scratch/rotated" true
if cmp -s "$scratch/first/mcp-token" "$scratch/rotated/mcp-token"; then exit 1; fi
cmp "$scratch/first/mcp-ca.crt" "$scratch/rotated/mcp-ca.crt"
cmp "$scratch/first/mcp-tls.crt" "$scratch/rotated/mcp-tls.crt"
[[ $(jq -r .jwt_id "$scratch/first/mcp-material.json") != $(jq -r .jwt_id "$scratch/rotated/mcp-material.json") ]]
jq -e 'has("token_sha256") | not' "$scratch/rotated/mcp-material.json" >/dev/null
cmp "$scratch/first/mcp-client-secret" "$scratch/rotated/mcp-client-secret"
jq '.data["material.json"] |= (@base64d | fromjson | .expires_at=0 | tojson | @base64)' \
  "$source_secret" >"$scratch/expired.json"
mv "$scratch/expired.json" "$source_secret"
demo_mcp_material "$scratch/renewed"
if cmp -s "$scratch/rotated/mcp-token" "$scratch/renewed/mcp-token"; then exit 1; fi

# Upgrade from the previous opaque-token material without replacing the TLS CA.
mkdir "$scratch/migrated"
jq '.data["material.json"] |= (@base64d | fromjson | del(.jwt_issuer,.jwt_id) |
  .token_sha256="legacy-digest" | tojson | @base64) | .data.token=("legacy-token"|@base64)' \
  "$source_secret" >"$scratch/legacy.json"
mv "$scratch/legacy.json" "$source_secret"
demo_mcp_material "$scratch/migrated"
cmp "$scratch/first/mcp-ca.crt" "$scratch/migrated/mcp-ca.crt"
demo_mcp_token_claims "$scratch/migrated/mcp-token" | jq -e '.azp == "demojam-ao-rca"' >/dev/null

yq -c . "$root/cluster/automation-orchestrator/workflows/rootcause.yaml" >"$scratch/workflow.json"
demo_ao_rca_definition <"$scratch/workflow.json" >"$scratch/disabled.json"
jq -e 'all(.nodes[]; .type != "script" and .id != "airca_fallback" and .id != "rca_success") and
  any(.edges[]; .from == "auditlogs" and .to == "airca") and
  any(.edges[]; .from == "airca" and .to == "createissue") and
  any(.nodes[]; .id == "airca" and .parameters.tool_selection_strategy == "NONE" and
    (.parameters.prompt | contains("MCP disabled")))' "$scratch/disabled.json" >/dev/null
jq -e '.nodes[] | select(.id == "airca") | .parameters.prompt |
  contains("read_log_file") and contains("log_path=/var/log/audit/audit.log") and
  (contains("get_selinux_denials") | not)' "$scratch/workflow.json" >/dev/null
export mcp_integration_id=11111111-1111-4111-8111-111111111111
export mcp_credential_id=22222222-2222-4222-8222-222222222222
export mcp_tool_ids='["33333333-3333-4333-8333-333333333333"]'
demo_ao_rca_definition <"$scratch/workflow.json" >"$scratch/enabled.json"
jq -e '.nodes[] | select(.id == "airca") |
  .parameters.tool_selection_strategy == "SELECTED" and (.parameters.tool_selections|length)==1 and
  (.parameters.integration_connections|length)==1 and .settings.continue_on_failure' "$scratch/enabled.json" >/dev/null
jq -e 'any(.edges[]; .from == "alertmanagereda" and .to == "airca") and
  any(.edges[]; .from == "auditlogs" and .to == "airca_fallback") and
  all(.nodes[]; .type != "script") and
  any(.nodes[]; .id == "airca_fallback" and .parameters.tool_selection_strategy == "NONE") and
  any(.edges[]; .from == "rca_success" and .from_port == "true" and .to == "createissue") and
  any(.edges[]; .from == "rca_success" and .from_port == "false" and .to == "auditlogs")' "$scratch/enabled.json" >/dev/null
export DEMO_BACKEND=aws WEBAPP_MCP_ENABLED=
if demo_mcp_enabled; then exit 1; fi
export WEBAPP_MCP_ENABLED=true
demo_mcp_enabled
export WEBAPP_MCP_ENABLED=invalid
if (demo_mcp_enabled) 2>/dev/null; then echo 'Invalid feature setting must fail explicitly' >&2; exit 1; fi

# Optional diagnostic failures finish successfully with an explicit error status.
# A terminal result must not be polled again or launch another execution.
base_url=https://ao.test/api/v1
auth_header='Authorization: Bearer test-only'
ao_response="$scratch/run-response.json"
ao_require_json() { [[ $2 == 200 ]]; jq -e . "$ao_response" >/dev/null; }
ao_curl() {
  case "$1 $2" in
    'GET https://ao.test/api/v1/workflows?limit=100')
      printf '%s' '{"resources":[{"name":"probe","is_builtin":false,"id":"workflow"}]}' >"$ao_response" ;;
    'POST https://ao.test/api/v1/executions')
      printf '%s' '{"id":"execution"}' >"$ao_response" ;;
    'GET https://ao.test/api/v1/executions/execution')
      printf '%s' '{"status":"completed_with_errors"}' >"$ao_response" ;;
    'GET https://ao.test/api/v1/executions/execution/activities?limit=100')
      printf '%s' '{"resources":[{"activity_name":"create_session","status":"completed","output_data":{"body":{"id":"fixture-session"}}}]}' >"$ao_response" ;;
    *) echo 'Unexpected workflow API operation' >&2; return 1 ;;
  esac
  printf '200'
}
sleep() { echo 'A terminal execution must not be polled again' >&2; return 1; }
demo_ao_run probe '{}' >"$scratch/run-output"
unset -f sleep
tail -n +2 "$scratch/run-output" | jq -e '.status=="completed_with_errors" and .results[0].output.body.id=="fixture-session"' >/dev/null

# A selective source refresh must not fetch/reset the recovered collection.
# Stop at the first fetch, before any Forgejo mutation, and record its name.
demo_source_checkout() { printf '%s\n' "$1" >>"$scratch/seed-fetches"; return 1; }
if demo_forgejo_seed_repos demojam-ansible; then
  echo 'The mocked source fetch must abort seeding' >&2; exit 1
fi
[[ $(cat "$scratch/seed-fetches") == demojam-ansible ]]
if (demo_forgejo_seed_repos unknown-repository) 2>/dev/null; then
  echo 'An unknown repository must fail before seeding' >&2; exit 1
fi
printf 'MCP bootstrap: Secret reuse, TLS, rotation, expiry renewal, workflow modes and backend gating passed\n'
