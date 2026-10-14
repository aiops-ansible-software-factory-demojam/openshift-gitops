#!/usr/bin/env bash
# Exercise lifecycle and workflow rendering without an installed cluster.
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/bootstrap/bootstrap.sh"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
source_secret="$scratch/source.json"

# Only the Secret operations used by demo_mcp_material are simulated. Crypto,
# serialization, renewal decisions and workflow rendering are the real code.
oc() {
  [[ $1 != -n ]] || shift 2
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

export DEMO_BACKEND=cnv WEBAPP_MCP_ENABLED=true
for name in first second rotated renewed; do mkdir "$scratch/$name"; done
demo_mcp_material "$scratch/first"
cp "$source_secret" "$scratch/original.json"
demo_mcp_material "$scratch/second"
cmp "$source_secret" "$scratch/original.json"
openssl verify -CAfile "$scratch/first/mcp-ca.crt" -verify_hostname webapp-mcp.webapp-vms.svc \
  "$scratch/first/mcp-tls.crt" >/dev/null
demo_mcp_material "$scratch/rotated" true
! cmp -s "$scratch/first/mcp-token" "$scratch/rotated/mcp-token"
cmp "$scratch/first/mcp-ca.crt" "$scratch/rotated/mcp-ca.crt"
cmp "$scratch/first/mcp-tls.crt" "$scratch/rotated/mcp-tls.crt"
jq '.data["material.json"] |= (@base64d | fromjson | .expires_at=0 | tojson | @base64)' \
  "$source_secret" >"$scratch/expired.json"
mv "$scratch/expired.json" "$source_secret"
demo_mcp_material "$scratch/renewed"
! cmp -s "$scratch/rotated/mcp-token" "$scratch/renewed/mcp-token"

yq -c . "$root/cluster/automation-orchestrator/workflows/rootcause.yaml" >"$scratch/workflow.json"
demo_ao_rca_definition <"$scratch/workflow.json" >"$scratch/disabled.json"
jq -e 'all(.nodes[]; .id != "mcpdiag") and
  any(.edges[]; .from == "auditlogs" and .to == "airca") and
  ([.nodes[].parameters.prompt // ""] | join("") | contains("${mcpdiag}") | not)' "$scratch/disabled.json" >/dev/null
export mcp_integration_id=11111111-1111-4111-8111-111111111111
export mcp_credential_id=22222222-2222-4222-8222-222222222222
export mcp_tool_ids='["33333333-3333-4333-8333-333333333333"]'
demo_ao_rca_definition <"$scratch/workflow.json" >"$scratch/enabled.json"
jq -e '.nodes[] | select(.id == "mcpdiag") |
  .parameters.tool_selection_strategy == "SELECTED" and (.parameters.tool_selections|length)==1 and
  (.parameters.integration_connections|length)==1 and .settings.continue_on_failure' "$scratch/enabled.json" >/dev/null
export DEMO_BACKEND=aws WEBAPP_MCP_ENABLED=
! demo_mcp_enabled
export WEBAPP_MCP_ENABLED=true
demo_mcp_enabled
export WEBAPP_MCP_ENABLED=invalid
if (demo_mcp_enabled) 2>/dev/null; then echo 'Invalid feature setting must fail explicitly' >&2; exit 1; fi
printf 'MCP bootstrap: Secret reuse, TLS, rotation, expiry renewal, workflow modes and backend gating passed\n'
