#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/bootstrap/bootstrap.sh"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
export DEMO_USERS_FILE="$scratch/users.json"
cat > "$DEMO_USERS_FILE" <<'JSON'
{"users":[
  {"username":"demo-user","email":"demo-user@example.test","groups":["demo-users","demo-admins"]},
  {"username":"reader","email":"reader@example.test","groups":["demo-users"]},
  {"username":"disabled","email":"disabled@example.test","groups":["demo-admins"],"enabled":false},
  {"username":"not-registered","email":"new@example.test","groups":["demo-admins"]}
]}
JSON
registered='[{"login":"demo-user","email":"DEMO-USER@example.test"},
 {"login":"reader","email":"reader@example.test"},
 {"login":"disabled","email":"disabled@example.test"},
 {"login":"demo-agent","email":"agent@example.test"}]'
protection=$(demo_invoice_main_protection "$registered")
jq -e '.merge_whitelist_usernames == ["demo-reviewer","demo-user"] and
  .enable_merge_whitelist and .apply_to_admins and .enable_status_check and
  .required_approvals == 1 and .enable_push == false and
  .status_check_contexts == ["invoice/ec2-validation"] and
  .dismiss_stale_approvals and .block_on_rejected_reviews and .block_on_outdated_branch' \
  <<<"$protection" >/dev/null
if demo_invoice_main_protection '[{"login":"demo-user","email":"wrong@example.test"}]' 2>/dev/null; then
  echo 'An identity email mismatch was accepted.' >&2
  exit 1
fi
echo 'Forgejo reviewer policy checks passed.'

# Exercise the actual writer: each application must require its own status.
fixture_registered=$registered
demo_invoice_forgejo_connect() { :; }
forgejo_api() {
  case "$1 $2" in
    'GET /admin/users?limit=50&page=1') printf '%s\n' "$fixture_registered" ;;
    GET*/branch_protections) printf '[]\n' ;;
    POST*/ansible-collection-demo.webapp/branch_protections) printf '%s\n' "$3" >"$scratch/web-policy.json" ;;
    POST*/ansible-collection-demo.pythonapp/branch_protections) printf '%s\n' "$3" >"$scratch/python-policy.json" ;;
    PUT*) : ;;
    *) printf 'Unexpected protection call: %s %s\n' "$1" "$2" >&2; return 1 ;;
  esac
}
demo_protect_applications
jq -e '.status_check_contexts == ["webapp/regression-validation"] and .apply_to_admins and .required_approvals == 1' "$scratch/web-policy.json" >/dev/null
jq -e '.status_check_contexts == ["invoice/ec2-validation"]' "$scratch/python-policy.json" >/dev/null
