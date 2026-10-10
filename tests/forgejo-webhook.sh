#!/usr/bin/env bash
# Verify hook registration and reruns without a cluster or real credentials.
set -Eeuo pipefail
test_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$test_repo_root/bootstrap/bootstrap.sh"
test_scratch=$(mktemp -d)
trap 'rm -rf -- "$test_scratch"' EXIT
export FORGEJO_STATE_DIR=$test_scratch
printf '%s' test-admin-token >"$test_scratch/admin-token"
printf '%s\n' '[]' >"$test_scratch/hooks.json"
printf '%s' first-test-token >"$test_scratch/token"

oc() {
  case "$*" in
    '-n openshift-ingress-operator get ingresscontroller default -o jsonpath={.status.domain}')
      printf '%s' apps.test ;;
    '-n forgejo get route forgejo -o jsonpath={.status.ingress[0].host}')
      printf '%s' forgejo.apps.test ;;
    '-n forgejo get secret forgejo-eda-webhook -o json')
      jq -n --rawfile token "$test_scratch/token" '{data:{
        token:($token|@base64),url:("https://aap.apps.test/eda-event-streams/api/eda/v1/external_event_stream/test/post/"|@base64)}}' ;;
    *) printf 'Unexpected oc call: %s\n' "$*" >&2; return 1 ;;
  esac
}

forgejo_api() {
  local method=$1 path=$2 body=${3:-}
  [[ $FORGEJO_TOKEN == test-admin-token && $FORGEJO_URL == https://forgejo.apps.test ]]
  case "$method $path" in
    'GET /repos/demo-owner/ansible-collection-demo.webapp/hooks?limit=100')
      cat "$test_scratch/hooks.json" ;;
    'POST /repos/demo-owner/ansible-collection-demo.webapp/hooks')
      jq -n --argjson body "$body" '[$body + {id:42}]' >"$test_scratch/hooks.json" ;;
    'PATCH /repos/demo-owner/ansible-collection-demo.webapp/hooks/42')
      jq --argjson body "$body" '.[0] += $body' "$test_scratch/hooks.json" >"$test_scratch/hooks.next"
      mv "$test_scratch/hooks.next" "$test_scratch/hooks.json" ;;
    *) printf 'Unexpected Forgejo call: %s %s\n' "$method" "$path" >&2; return 1 ;;
  esac
}

demo_forgejo_webhook_configure
jq -e 'length == 1 and .[0].type == "forgejo" and .[0].active == true and
  .[0].events == ["issues"] and .[0].authorization_header == "Bearer first-test-token" and
  .[0].config.content_type == "json" and .[0].config.http_method == "POST"' "$test_scratch/hooks.json" >/dev/null
first_run=$(jq -Sc . "$test_scratch/hooks.json")
demo_forgejo_webhook_configure
[[ $(jq -Sc . "$test_scratch/hooks.json") == "$first_run" ]]
printf '%s' second-test-token >"$test_scratch/token"
demo_forgejo_webhook_configure
jq -e 'length == 1 and .[0].id == 42 and
  .[0].authorization_header == "Bearer second-test-token"' "$test_scratch/hooks.json" >/dev/null
printf 'PASS registration, repeat, and credential refresh preserve a single issue hook\n'

jq '. + [.[0] + {id:43}]' "$test_scratch/hooks.json" >"$test_scratch/hooks.next"
mv "$test_scratch/hooks.next" "$test_scratch/hooks.json"
if demo_forgejo_webhook_configure >"$test_scratch/output" 2>&1; then
  printf 'FAIL duplicate hooks should stop setup\n' >&2
  exit 1
fi
printf 'PASS duplicate hooks stop setup\n'
