#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'find "$scratch" -depth -delete' EXIT
export FEATURE_TEST_DIR="$scratch"
export FORGEJO_STATE_DIR="$scratch/state"
export KUBECONFIG="$scratch/kubeconfig"

cat >"$scratch/oc" <<'MOCK_OC'
#!/bin/bash
set -euo pipefail
case "$*" in
  'whoami --show-server') printf 'https://api.demo.example.test:6443' ;;
  whoami) printf 'demo-admin\n' ;;
  *'get ingresscontroller default'*) printf 'apps.demo.example.test' ;;
  *'get route forgejo-demo'*) printf 'forgejo-demo.apps.demo.example.test' ;;
  *'patch secret omnigent-model'*)
    for arg in "$@"; do
      case "$arg" in
        --patch-file=*) cp "${arg#--patch-file=}" "$FEATURE_TEST_DIR/patch.json" ;;
      esac
    done ;;
  *'get secret omnigent-model'*|*'rollout status deployment/forgejo-demo'*) : ;;
  *) echo "Unexpected oc command: $*" >&2; exit 1 ;;
esac
MOCK_OC
cat >"$scratch/bash" <<'MOCK_BASH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$FEATURE_TEST_DIR/bash.log"
case "$*" in
  *'/scripts/demo.sh seed'|*'/scripts/demo.sh reset --confirm-forgejo-demo')
    mkdir -p "$FORGEJO_STATE_DIR"
    printf 'admin-token' >"$FORGEJO_STATE_DIR/admin-token"
    printf '%s' "$FEATURE_TEST_TOKEN" >"$FORGEJO_STATE_DIR/agent-token" ;;
  *'/scripts/ensure-nginx-uid-issue.sh')
    printf 'https://forgejo-demo.apps.demo.example.test/demo-owner/ansible-collection-demo/issues/1\n' ;;
  *) echo "Unexpected bash command: $*" >&2; exit 1 ;;
esac
MOCK_BASH
chmod +x "$scratch/oc" "$scratch/bash"

FEATURE_TEST_TOKEN=first-token PATH="$scratch:$PATH" \
  /bin/bash scripts/feature-demo.sh hydrate >"$scratch/output"
jq -e '.stringData.FORGEJO_TOKEN == "first-token" and
  .stringData.FORGEJO_USERNAME == "demo-agent" and
  .stringData.FORGEJO_URL == "http://forgejo-demo.forgejo-demo.svc.cluster.local:3000"' \
  "$scratch/patch.json" >/dev/null
if rg -q 'first-token' "$scratch/output" "$scratch/bash.log"; then
  echo 'Hydration logged the agent token.' >&2
  exit 1
fi

FEATURE_TEST_TOKEN=rotated-token PATH="$scratch:$PATH" \
  /bin/bash scripts/feature-demo.sh reset --confirm-forgejo-demo >"$scratch/output"
jq -e '.stringData.FORGEJO_TOKEN == "rotated-token"' \
  "$scratch/patch.json" >/dev/null
rg -q '/scripts/demo.sh reset --confirm-forgejo-demo' "$scratch/bash.log"
if rg -q 'rotated-token' "$scratch/output" "$scratch/bash.log"; then
  echo 'Reset logged the rotated agent token.' >&2
  exit 1
fi

echo 'Hydration and reset refresh the sandbox token without logging it.'
