#!/usr/bin/env bash
set -euo pipefail

# Call AO's published workflow API, then print the Omnigent session it created.
export KUBECONFIG=${KUBECONFIG:-"$HOME/.kube/config"}
task=${*:-Reply with DEMO_AGENT_READY and the first line of ansible --version. Do not edit files.}

oc whoami --show-server
oc whoami

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
payload=$(jq -cn --arg workflow_id "$workflow_id" --arg task "$task" \
  '{workflow_id:$workflow_id,trigger_node_id:"start",use_published:true,input_data:{task:$task}}')
execution_id=$(curl -fsS "https://$ao_host/api/v1/executions" \
  -H "Authorization: Bearer $ao_token" -H 'Content-Type: application/json' \
  --data-binary "$payload" | jq -er '.id')
unset payload
echo "AO execution: $execution_id"

deadline=$((SECONDS + 420))
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
    echo "AO execution is still $status after seven minutes." >&2
    exit 1
  fi
  sleep 5
done

session_id=$(ao_get "executions/$execution_id/activities" |
  jq -er '.resources[] | select(.activity_name == "create_session") | .output_data.body.id')
echo "AO workflow: completed"
echo "Omnigent session: $session_id"
echo 'Open the session in Omnigent to inspect the agent response.'
