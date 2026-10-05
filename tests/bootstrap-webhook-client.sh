#!/usr/bin/env bash
# Exercise the webhook client lifecycle without cluster access or real secrets.
set -Eeuo pipefail
test_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$test_repo_root/bootstrap/bootstrap.sh"

if [[ ${1:-} == --client ]]; then
  test_state=$2/state.json
  omnigent_scratch=$2
  ao_response=$2/response.json
  namespace=automation-orchestrator
  base_url=https://ao.test/api/v1
  auth_header='Authorization: Bearer test-token'
  project_id=test-project
  ao_require_json() {
    [[ $2 == 2* ]] || demo_die "Mock API failed: $1 ($2)"
    jq -e . "$ao_response" >/dev/null
  }
  ao_curl() {
    local method=$1 url=$2
    case "$method $url" in
      "GET $base_url/service_accounts?limit=100")
        jq '{resources:[.account // empty]}' "$test_state" >"$ao_response" ;;
      "POST $base_url/service_accounts")
        jq '.account={id:"test-account",name:"demojam-eda-webhook",project_id:"test-project",status:"active"} | .account_creates += 1' "$test_state" >"$test_state.next"
        mv "$test_state.next" "$test_state"
        jq .account "$test_state" >"$ao_response" ;;
      "GET $base_url/service_accounts/test-account/credentials?limit=100")
        jq '{resources:.clients}' "$test_state" >"$ao_response" ;;
      "POST $base_url/service_accounts/test-account/credentials")
        jq '.client_creates += 1 | .clients += [{id:"new-client",identifier:"new-identifier",status:"active",expires_at:"2099-01-01T00:00:00Z"}]' "$test_state" >"$test_state.next"
        mv "$test_state.next" "$test_state"
        printf '%s\n' '{"id":"new-client","identifier":"new-identifier","client_secret":"new-test-secret"}' >"$ao_response" ;;
      *) printf 'Unexpected API call: %s %s\n' "$method" "$url" >&2; return 1 ;;
    esac
    printf '200\n'
  }
  oc() {
    case "$*" in
      '-n automation-orchestrator get secret demojam-eda-webhook-client --ignore-not-found -o json')
        [[ $(jq -r '.secret_read_error // false' "$test_state") != true ]] || return 7
        jq '.secret // empty' "$test_state" ;;
      'apply --server-side --field-manager=demo-bootstrap --force-conflicts -f -')
        local secret
        secret=$(jq '.data=(.stringData | map_values(@base64)) | del(.stringData)')
        jq --argjson secret "$secret" '.secret=$secret' "$test_state" >"$test_state.next"
        mv "$test_state.next" "$test_state" ;;
      *) printf 'Unexpected oc call: %s\n' "$*" >&2; return 1 ;;
    esac
  }
  demo_ao_webhook_client
  exit
fi

test_scratch=$(mktemp -d)
trap 'find "$test_scratch" -type f -delete; rmdir "$test_scratch"' EXIT
baseline=$(jq -n '{
  account:{id:"test-account",name:"demojam-eda-webhook",project_id:"test-project",status:"active"},
  clients:[{id:"saved-client",identifier:"saved-identifier",status:"active",expires_at:"2099-01-01T00:00:00+00:00"}],
  secret:{data:{"service-account-id":("test-account"|@base64),"client-id":("saved-identifier"|@base64),"client-secret":("saved-test-secret"|@base64)}},
  account_creates:0,client_creates:0
}')

for scenario in fresh valid no-expiry expired disabled-client stale-account missing-client incomplete-secret; do
  case $scenario in
    fresh) filter='.account=null | .clients=[] | .secret=null'; expected_accounts=1; expected_clients=1 ;;
    valid) filter='.'; expected_accounts=0; expected_clients=0 ;;
    no-expiry) filter='.clients[0].expires_at=null'; expected_accounts=0; expected_clients=0 ;;
    expired) filter='.clients[0].expires_at="2000-01-01T00:00:00Z"'; expected_accounts=0; expected_clients=1 ;;
    disabled-client) filter='.clients[0].status="disabled"'; expected_accounts=0; expected_clients=1 ;;
    stale-account) filter='.secret.data["service-account-id"]=("previous-account"|@base64)'; expected_accounts=0; expected_clients=1 ;;
    missing-client) filter='.clients=[]'; expected_accounts=0; expected_clients=1 ;;
    incomplete-secret) filter='del(.secret.data["client-secret"])'; expected_accounts=0; expected_clients=1 ;;
  esac
  jq "$filter" <<<"$baseline" >"$test_scratch/state.json"
  [[ $(bash "$0" --client "$test_scratch") == test-account ]]
  jq -e --argjson accounts "$expected_accounts" --argjson clients "$expected_clients" '
    .account_creates == $accounts and .client_creates == $clients and
    (.secret.data["service-account-id"]|@base64d) == .account.id and
    (.secret.data["client-id"]|@base64d) == .clients[-1].identifier and
    (.secret.data["client-secret"]|@base64d|length > 0)' "$test_scratch/state.json" >/dev/null
  first_run=$(jq -Sc . "$test_scratch/state.json")
  [[ $(bash "$0" --client "$test_scratch") == test-account ]]
  [[ $(jq -Sc . "$test_scratch/state.json") == "$first_run" ]]
  printf 'PASS %s and repeat preserves credentials\n' "$scenario"
done

for scenario in disabled-account secret-read-error; do
  case $scenario in
    disabled-account) filter='.account.status="disabled"' ;;
    secret-read-error) filter='.secret_read_error=true' ;;
  esac
  jq "$filter" <<<"$baseline" >"$test_scratch/state.json"
  if bash "$0" --client "$test_scratch" >"$test_scratch/output" 2>&1; then
    printf 'FAIL %s should stop setup\n' "$scenario" >&2
    exit 1
  fi
  jq -e '.account_creates == 0 and .client_creates == 0' "$test_scratch/state.json" >/dev/null
  printf 'PASS %s stops without issuing credentials\n' "$scenario"
done
