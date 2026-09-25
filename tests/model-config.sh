#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
export MODEL_TEST_DIR="$scratch"

cat >"$scratch/oc" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *'get secret omnigent-model -o json'*)
    [[ ${MODEL_TEST_EXISTING_GO:-false} == true ]] || exit 1
    cat "$MODEL_TEST_DIR/existing-secret.json" ;;
  *'get secret omnigent-model'*|*'get secret omnigent-agent'*)
    [[ ${MODEL_TEST_EXISTING_GO:-false} == true ]] ;;
  *'patch secret omnigent-model'*|*'patch secret omnigent-agent'*)
    previous=
    for arg in "$@"; do
      if [[ $previous == -p ]]; then
        if [[ $* == *'patch secret omnigent-model'* ]]; then
          printf '%s' "$arg" >"$MODEL_TEST_DIR/model-patch.json"
        else
          printf '%s' "$arg" >"$MODEL_TEST_DIR/agent-patch.json"
        fi
        break
      fi
      previous=$arg
    done ;;
  *'get deployment omnigent'*) exit 1 ;;
  *'create secret generic omnigent-model'*)
    for arg in "$@"; do
      case "$arg" in
        --from-file=OPENCODE_CONFIG_CONTENT=*)
          cp "${arg#--from-file=OPENCODE_CONFIG_CONTENT=}" "$MODEL_TEST_DIR/config.json" ;;
      esac
    done
    printf 'apiVersion: v1\nkind: Secret\n' ;;
  *'create secret generic omnigent-agent'*)
    for arg in "$@"; do
      case "$arg" in
        --from-file=demo.yaml=*)
          cp "${arg#--from-file=demo.yaml=}" "$MODEL_TEST_DIR/agent.yaml" ;;
      esac
    done
    printf 'apiVersion: v1\nkind: Secret\n' ;;
  *'apply -f -'*) cat >/dev/null ;;
  *) echo "Unexpected oc invocation: $*" >&2; exit 2 ;;
esac
MOCK
chmod +x "$scratch/oc"

run_case() {
  local base_url=$1 model=$2
  rm -f "$scratch/config.json" "$scratch/agent.yaml"
  MODEL_BASE_URL="$base_url" MODEL_NAME="$model" MODEL_API_KEY=test-key \
    PATH="$scratch:$PATH" bash bootstrap/model-config.sh >/dev/null
  jq -e --arg base "$base_url" --arg model "$model" '
    .model == ("demo/" + $model) and
    .provider.demo.npm == "@ai-sdk/openai-compatible" and
    .provider.demo.options.baseURL == $base and
    .provider.demo.options.apiKey == "{env:OPENAI_API_KEY}" and
    .provider.demo.models[$model].name == $model
  ' "$scratch/config.json" >/dev/null
  test "$(yq -r '.executor.model' "$scratch/agent.yaml")" == "demo/$model"
}

run_case https://opencode.ai/zen/go/v1 glm-5.3-flash
run_case https://maas-rhdp.apps.maas.redhatworkshops.io/v1 gpt-oss-120b
MODEL_API_KEY=test-key PATH="$scratch:$PATH" \
  bash bootstrap/model-config.sh >/dev/null
jq -e '.model == "demo/glm-5.3-flash" and
  .provider.demo.options.baseURL == "https://opencode.ai/zen/go/v1"' \
  "$scratch/config.json" >/dev/null

legacy_config=$(jq -cn '{
  model:"demo/kimi-k3",
  provider:{demo:{
    options:{baseURL:"https://opencode.ai/zen/go/v1"},
    models:{"kimi-k3":{name:"kimi-k3"}}
  }}
}')
jq -cn --arg value "$(printf '%s' "$legacy_config" | base64 -w0)" \
  '{data:{OPENCODE_CONFIG_CONTENT:$value}}' >"$scratch/existing-secret.json"
MODEL_TEST_EXISTING_GO=true PATH="$scratch:$PATH" \
  bash bootstrap/model-config.sh >/dev/null
jq -e '
  .data.OPENCODE_CONFIG_CONTENT | @base64d | fromjson |
  .model == "demo/glm-5.3-flash" and
  (.provider.demo.models | keys == ["glm-5.3-flash"])
' "$scratch/model-patch.json" >/dev/null
jq -er '.data["demo.yaml"] | @base64d' "$scratch/agent-patch.json" |
  yq -r '.executor.model' | rg -Fxq 'demo/glm-5.3-flash'

cat >"$scratch/op" <<'MOCK_OP'
#!/usr/bin/env bash
printf '%s\n' '{"fields":[{"label":"password","value":"test-key"}]}'
MOCK_OP
chmod +x "$scratch/op"
MODEL_API_KEY= MODEL_BASE_URL= MODEL_NAME= PATH="$scratch:$PATH" \
  bash bootstrap/model-config.sh >/dev/null
jq -e '.model == "demo/glm-5.3-flash"' "$scratch/config.json" >/dev/null

if MODEL_BASE_URL=https://opencode.ai/zen/go/v1 \
   MODEL_NAME=kimi-k3 MODEL_API_KEY=test-key \
   PATH="$scratch:$PATH" bash bootstrap/model-config.sh >/dev/null 2>&1; then
  echo 'OpenCode Go accepted a model other than glm-5.3-flash.' >&2
  exit 1
fi
for host in opencode.ai maas-rhdp.apps.maas.redhatworkshops.io; do
  yq -r '.network_policies[].endpoints[].host' \
    cluster/openshell/image/policy.yaml | rg -Fxq "$host"
done

if MODEL_BASE_URL=https://maas-rhdp.apps.maas.redhatworkshops.io/v1/chat/completions \
   MODEL_NAME=gpt-oss-120b MODEL_API_KEY=test-key \
   PATH="$scratch:$PATH" bash bootstrap/model-config.sh >/dev/null 2>&1; then
  echo 'A chat completions URL was accepted as a base URL.' >&2
  exit 1
fi

echo 'OpenCode Go and LiteLLM MaaS share base URL, model, and API key inputs.'
