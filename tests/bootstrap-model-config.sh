#!/usr/bin/env bash
# Verify the generated OpenCode transport without credentials or a cluster.
set -Eeuo pipefail
test_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$test_repo_root/bootstrap/bootstrap.sh"
test_scratch=$(mktemp -d)
trap 'rm -rf -- "$test_scratch"' EXIT

demo_verify_cluster() { return 0; }
oc() {
  if [[ $* == *'create secret generic omnigent-model'* ]]; then
    local argument
    for argument in "$@"; do
      if [[ $argument == --from-file=OPENCODE_CONFIG_CONTENT=* ]]; then
        cp -- "${argument#--from-file=OPENCODE_CONFIG_CONTENT=}" "$test_scratch/config.json"
      fi
    done
    printf '{}\n'
  elif [[ $* == *'create secret generic omnigent-agent'* ]]; then
    printf '{}\n'
  elif [[ $* == *'apply -f -'* ]]; then
    cat >/dev/null
    printf 'secret/test unchanged\n'
  else
    printf 'Unexpected oc call: %s\n' "$*" >&2
    return 1
  fi
}

export MODEL_PROVIDER=opencode-go OPENCODE_GO_ENDPOINT=https://opencode.test/v1
export OPENCODE_GO_API_KEY=test-only-key OPENCODE_GO_MODEL=claude-haiku-5-5
for protocol in responses chat anthropic; do
  export OPENCODE_GO_PROTOCOL=$protocol
  case $protocol in
    responses) expected_sdk=@ai-sdk/openai ;;
    chat) expected_sdk=@ai-sdk/openai-compatible ;;
    anthropic) expected_sdk=@ai-sdk/anthropic ;;
  esac
  demo_model_config >/dev/null
  jq -e --arg sdk "$expected_sdk" '
    .provider.demo.npm == $sdk and
    .provider.demo.options.baseURL == "https://opencode.test/v1" and
    .provider.demo.options.apiKey == "{env:OPENAI_API_KEY}" and
    .model == "demo/claude-haiku-5-5"' "$test_scratch/config.json" >/dev/null
  jq -e 'all(.. | strings; contains("test-only-key") | not)' "$test_scratch/config.json" >/dev/null
  printf 'PASS %s selects the SDK and keeps credentials out of OpenCode JSON\n' "$protocol"
done

OPENCODE_GO_PROTOCOL=invalid
if demo_model_inputs >/dev/null 2>&1; then
  printf 'FAIL invalid transport was accepted\n' >&2
  exit 1
fi
OPENCODE_GO_PROTOCOL=anthropic
OPENCODE_GO_ENDPOINT=https://opencode.test/v1/messages
if demo_model_inputs >/dev/null 2>&1; then
  printf 'FAIL a full Messages URL was accepted as the API base\n' >&2
  exit 1
fi
printf 'PASS invalid transport and full endpoint are rejected\n'
