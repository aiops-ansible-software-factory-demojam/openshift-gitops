#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'find "$scratch" -depth -delete' EXIT
export RESET_TEST_DIR="$scratch"
export KUBECONFIG="$scratch/kubeconfig"
export MODEL_API_KEY=test-key

cat >"$scratch/oc" <<'MOCK_OC'
#!/bin/bash
set -euo pipefail
case "$*" in
  'whoami --show-server') printf '%s\n' https://api.demo.example.test:6443 ;;
  whoami) printf '%s\n' demo-admin ;;
  *'get ingresscontroller default'*) printf '%s' apps.demo.example.test ;;
  *'get route omnigent'*) printf 'omnigent.%s' "${RESET_TEST_ROUTE:-apps.demo.example.test}" ;;
  *'get secret omnigent-machine-client-credential'*'username'*) printf '%s' demo-client ;;
  *'get secret omnigent-machine-client-credential'*'password'*) printf '%s' demo-secret ;;
  *'delete sandboxes'*|*'delete secret omnigent-model'*|*'delete secret omnigent-agent'*|*'rollout status deployment/omnigent'*)
    printf '%s\n' "$*" >>"$RESET_TEST_DIR/oc.log" ;;
  *) echo "Unexpected oc command: $*" >&2; exit 1 ;;
esac
MOCK_OC
cat >"$scratch/curl" <<'MOCK_CURL'
#!/bin/bash
set -euo pipefail
url=${!#}
case "$url" in
  */v1/agents)
    printf '%s\n' '{"data":[{"id":"demo-agent-id","name":"automation-developer"}]}' ;;
  *'/v1/sessions?limit=100')
    printf '%s\n' '{"data":[{"id":"demo-session","agent_id":"demo-agent-id"},{"id":"unrelated-session","agent_id":"other-agent"}],"has_more":false}' ;;
  */v1/sessions/demo-session)
    printf '%s\n' "$url" >>"$RESET_TEST_DIR/deleted.log" ;;
  *) echo "Unexpected curl URL: $url" >&2; exit 1 ;;
esac
MOCK_CURL
cat >"$scratch/bash" <<'MOCK_BASH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$RESET_TEST_DIR/bash.log"
MOCK_BASH
chmod +x "$scratch/oc" "$scratch/curl" "$scratch/bash"

PATH="$scratch:$PATH" /bin/bash scripts/reset-demo.sh --confirm-demo-reset \
  >"$scratch/output"
rg -Fxq 'https://omnigent.apps.demo.example.test/v1/sessions/demo-session' \
  "$scratch/deleted.log"
test "$(wc -l <"$scratch/deleted.log")" -eq 1
rg -q 'delete secret omnigent-model' "$scratch/oc.log"
rg -q 'delete secret omnigent-agent' "$scratch/oc.log"
rg -q '/bootstrap/model-config.sh' "$scratch/bash.log"
rg -q '/scripts/feature-demo.sh reset --confirm-forgejo-demo' "$scratch/bash.log"
rg -q '/reconcile-omnigent-workflow.sh' "$scratch/bash.log"

: >"$scratch/deleted.log"
if RESET_TEST_ROUTE=wrong.example.test PATH="$scratch:$PATH" \
  /bin/bash scripts/reset-demo.sh --confirm-demo-reset >"$scratch/output" 2>&1; then
  echo 'Reset accepted an Omnigent Route from another cluster.' >&2
  exit 1
fi
test ! -s "$scratch/deleted.log"
echo 'Demo reset deletes only automation-developer sessions and checks the cluster.'
