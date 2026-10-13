#!/usr/bin/env bash
# Verify independent inference transports and credentials without a cluster.
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
      elif [[ $argument == --from-file=OPENAI_API_KEY=* ]]; then
        cp -- "${argument#--from-file=OPENAI_API_KEY=}" "$test_scratch/native-key"
      fi
    done
    printf '{}\n'
  elif [[ $* == *'create secret generic omnigent-agent'* ]]; then
    local argument
    for argument in "$@"; do
      if [[ $argument == --from-file=automation-developer.yaml=* ]]; then
        cp -- "${argument#--from-file=automation-developer.yaml=}" "$test_scratch/agent.yaml"
      fi
    done
    printf '{}\n'
  elif [[ $* == *'create secret generic ao-opencode-go'* ||
          $* == *'create secret generic ao-litellm-qwen'* ]]; then
    local argument
    for argument in "$@"; do
      if [[ $argument == --from-file=PROVIDER_API_KEY=* ]]; then
        cp -- "${argument#--from-file=PROVIDER_API_KEY=}" "$test_scratch/ao-key"
      fi
    done
    printf '{}\n'
  elif [[ $* == *'create configmap ao-opencode-go'* ||
          $* == *'create configmap ao-litellm-qwen'* ]]; then
    local argument
    for argument in "$@"; do
      if [[ $argument == --from-file=config.yaml=* ]]; then
        cp -- "${argument#--from-file=config.yaml=}" "$test_scratch/proxy.yaml"
      fi
    done
    printf '{}\n'
  elif [[ $* == *'get deployment ao-opencode-go'* ||
          $* == *'get secret ao-opencode-go'* ||
          $* == *'rollout status deployment/ao-opencode-go'* ||
          $* == *'get deployment ao-litellm-qwen'* ||
          $* == *'get secret ao-litellm-qwen'* ||
          $* == *'rollout status deployment/ao-litellm-qwen'* ]]; then
    return 0
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
unset AO_MODEL_PROVIDER AO_MODEL AO_MODEL_ENDPOINT AO_MODEL_API_KEY AO_MODEL_PROTOCOL AO_QWEN_REASONING_EFFORT
unset OMNIGENT_MODEL_PROVIDER OMNIGENT_MODEL OMNIGENT_MODEL_ENDPOINT OMNIGENT_MODEL_API_KEY OMNIGENT_MODEL_PROTOCOL OMNIGENT_QWEN_REASONING_EFFORT
export QWEN_REASONING_EFFORT=none AO_LLM_REQUEST_TIMEOUT_SECONDS=90
namespace=automation-orchestrator
omnigent_scratch=$test_scratch
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
  demo_model_inputs ao
  demo_ao_llm_proxy >/dev/null
  case $protocol in
    responses) expected_backend=openai/responses/claude-haiku-5-5; expected_base=$OPENCODE_GO_ENDPOINT ;;
    chat) expected_backend=openai/claude-haiku-5-5; expected_base=$OPENCODE_GO_ENDPOINT ;;
    anthropic) expected_backend=anthropic/claude-haiku-5-5; expected_base=$OPENCODE_GO_ENDPOINT/messages ;;
  esac
  yq . "$test_scratch/proxy.yaml" | jq -e --arg backend "$expected_backend" --arg base "$expected_base" '
    .model_list[0].litellm_params.model == $backend and
    .model_list[0].litellm_params.api_base == $base and
    .model_list[0].litellm_params.api_key == "os.environ/PROVIDER_API_KEY"' >/dev/null
  printf 'PASS %s selects the SDK and keeps credentials out of OpenCode JSON\n' "$protocol"
done

export LITELLM_ENDPOINT=https://litellm.test/v1 LITELLM_API_KEY=litellm-test-key LITELLM_MODEL=qwen38-27b
export AO_MODEL_PROVIDER=litellm AO_MODEL=qwen38-27b AO_QWEN_REASONING_EFFORT=low
export OMNIGENT_MODEL_PROVIDER=opencode-go OMNIGENT_MODEL=claude-haiku-5-5 OMNIGENT_MODEL_PROTOCOL=anthropic
demo_model_config >/dev/null
demo_model_inputs ao
[[ $model_provider == litellm && $model_protocol == chat && $model_name == qwen38-27b ]]
demo_ao_llm_proxy >/dev/null
[[ $(<"$test_scratch/native-key") == test-only-key && $(<"$test_scratch/ao-key") == litellm-test-key ]]
yq . "$test_scratch/agent.yaml" | jq -e '.executor.model == "demo/claude-haiku-5-5"' >/dev/null
jq -e '.model == "demo/claude-haiku-5-5" and .provider.demo.npm == "@ai-sdk/anthropic" and
  (.provider.demo.models["claude-haiku-5-5"] | has("options") | not)' "$test_scratch/config.json" >/dev/null
yq . "$test_scratch/proxy.yaml" | jq -e '.model_list[0].litellm_params |
  .model == "openai/qwen38-27b" and .api_base == "https://litellm.test/v1" and
  .reasoning_effort == "low" and .extra_body.chat_template_kwargs.reasoning_effort == "low"' >/dev/null
printf 'PASS Qwen AO and Anthropic Haiku Omnigent keep models, transports and keys separate\n'

# Reverse the providers and select a different Qwen effort for the coding side.
AO_MODEL_PROVIDER=opencode-go AO_MODEL=gpt-6-luna AO_MODEL_PROTOCOL=responses
OMNIGENT_MODEL_PROVIDER=litellm OMNIGENT_MODEL=qwen38-27b OMNIGENT_MODEL_PROTOCOL=chat
export OMNIGENT_QWEN_REASONING_EFFORT=medium
demo_model_config >/dev/null
demo_model_inputs ao
demo_ao_llm_proxy >/dev/null
[[ $(<"$test_scratch/native-key") == litellm-test-key && $(<"$test_scratch/ao-key") == test-only-key ]]
jq -e '.model == "demo/qwen38-27b" and .provider.demo.npm == "@ai-sdk/openai-compatible" and
  .provider.demo.models["qwen38-27b"].options.reasoningEffort == "medium"' "$test_scratch/config.json" >/dev/null
yq . "$test_scratch/proxy.yaml" | jq -e '.model_list[0].litellm_params |
  .model == "openai/responses/gpt-6-luna" and (has("reasoning_effort") | not)' >/dev/null
printf 'PASS reversed providers isolate AO transport from Omnigent Qwen effort\n'

# Same provider, separate accounts and models, independent of the shared preset.
MODEL_PROVIDER=litellm
AO_MODEL_PROVIDER=opencode-go AO_MODEL=gpt-6-luna AO_MODEL_PROTOCOL=responses
export AO_MODEL_ENDPOINT=https://ao-only.test/v1 AO_MODEL_API_KEY=ao-only-test-key
OMNIGENT_MODEL_PROVIDER=opencode-go OMNIGENT_MODEL=claude-haiku-5-5 OMNIGENT_MODEL_PROTOCOL=anthropic
export OMNIGENT_MODEL_ENDPOINT=https://coding-only.test/v1 OMNIGENT_MODEL_API_KEY=coding-only-test-key
demo_model_config >/dev/null
demo_model_inputs ao
demo_ao_llm_proxy >/dev/null
[[ $(<"$test_scratch/native-key") == coding-only-test-key && $(<"$test_scratch/ao-key") == ao-only-test-key ]]
jq -e '.model == "demo/claude-haiku-5-5" and .provider.demo.options.baseURL == "https://coding-only.test/v1"' "$test_scratch/config.json" >/dev/null
yq . "$test_scratch/proxy.yaml" | jq -e '.model_list[0].litellm_params |
  .model == "openai/responses/gpt-6-luna" and .api_base == "https://ao-only.test/v1"' >/dev/null
printf 'PASS same-provider model, endpoint and credential overrides are independent\n'

unset AO_MODEL_PROVIDER AO_MODEL AO_MODEL_ENDPOINT AO_MODEL_API_KEY AO_MODEL_PROTOCOL AO_QWEN_REASONING_EFFORT
unset OMNIGENT_MODEL_PROVIDER OMNIGENT_MODEL OMNIGENT_MODEL_ENDPOINT OMNIGENT_MODEL_API_KEY OMNIGENT_MODEL_PROTOCOL OMNIGENT_QWEN_REASONING_EFFORT
MODEL_PROVIDER=litellm
for consumer in ao omnigent; do
  demo_model_inputs "$consumer"
  [[ $model_provider == litellm && $model_name == qwen38-27b && $model_key == litellm-test-key &&
     $model_protocol == chat && $model_reasoning_effort == none ]]
done
printf 'PASS legacy shared LiteLLM defaults still configure both consumers\n'

# A credential for the other consumer must not satisfy a missing selected key.
AO_MODEL_PROVIDER=litellm OMNIGENT_MODEL_PROVIDER=opencode-go LITELLM_API_KEY=''
if demo_model_inputs ao >/dev/null 2>&1; then
  printf 'FAIL AO accepted the other provider credential\n' >&2; exit 1
fi
demo_model_inputs omnigent
[[ $model_key == test-only-key ]]
LITELLM_API_KEY=litellm-test-key AO_QWEN_REASONING_EFFORT=invalid
if demo_model_inputs ao >/dev/null 2>&1; then
  printf 'FAIL invalid AO Qwen effort was accepted\n' >&2; exit 1
fi
export AO_QWEN_REASONING_EFFORT=none AO_MODEL_PROTOCOL=anthropic
if demo_model_inputs ao >/dev/null 2>&1; then
  printf 'FAIL LiteLLM accepted the Anthropic transport\n' >&2; exit 1
fi
unset AO_MODEL_PROVIDER AO_QWEN_REASONING_EFFORT AO_MODEL_PROTOCOL OMNIGENT_MODEL_PROVIDER
MODEL_PROVIDER=opencode-go
printf 'PASS missing credentials, invalid scoped effort and unsupported protocol are rejected\n'

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
