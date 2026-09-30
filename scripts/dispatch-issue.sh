#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../bootstrap/env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/env.sh"

# Call AO's published workflow API and print the launched Omnigent session.
issue_number=${1:?Usage: dispatch-issue.sh ISSUE_NUMBER}
[[ $issue_number =~ ^[1-9][0-9]*$ ]] || {
  echo 'Pass a positive numeric Forgejo issue number.' >&2
  exit 2
}

demo_verify_cluster

ao_host=$(oc -n automation-orchestrator get route automation-orchestrator \
  -o jsonpath='{.status.ingress[0].host}')
ao_password=$(oc -n automation-orchestrator get secret \
  automation-orchestrator-admin-password \
  -o go-template='{{index .data "password" | base64decode}}')
login_payload=$(jq -cn --arg password "$ao_password" \
  '{username:"admin",password:$password}')
unset ao_password
ao_token=$(curl -fsS "https://$ao_host/api/v1/auth/login" \
  -H 'Content-Type: application/json' --data-binary "$login_payload" |
  jq -er '.access_token')
unset login_payload

ao_get() {
  curl -fsS "https://$ao_host/api/v1/$1" \
    -H "Authorization: Bearer $ao_token"
}

workflow_id=$(ao_get 'workflows?limit=100' |
  jq -er '.resources[] | select(.name == "omnigent-dispatch") | .id')
payload=$(jq -cn --arg workflow_id "$workflow_id" \
  --argjson issue_number "$issue_number" \
  '{workflow_id:$workflow_id,trigger_node_id:"start",use_published:true,input_data:{issue_number:$issue_number}}')
execution_id=$(curl -fsS "https://$ao_host/api/v1/executions" \
  -H "Authorization: Bearer $ao_token" -H 'Content-Type: application/json' \
  --data-binary "$payload" | jq -er '.id')
unset payload
echo "AO execution: $execution_id"

deadline=$((SECONDS + 900))
while :; do
  status=$(ao_get "executions/$execution_id" | jq -er '.status')
  case "$status" in
    completed) break ;;
    failed|canceled|cancelled)
      echo "AO execution ended with status $status" >&2
      exit 1
      ;;
  esac
  if (( SECONDS >= deadline )); then
    echo "AO execution is still $status after fifteen minutes." >&2
    exit 1
  fi
  sleep 5
done

session_id=$(ao_get "executions/$execution_id/activities" |
  jq -er '.resources[] | select(.activity_name == "create_session") | .output_data.body.id')
echo 'AO workflow: completed'
echo "Omnigent session: $session_id"
echo 'The agent continues asynchronously. Inspect the session for its PR URL.'
