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
  *'get secret omnigent-model'*) exit 1 ;;
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

run_case https://opencode.ai/zen/go/v1 kimi-k3
run_case https://maas-rhdp.apps.maas.redhatworkshops.io/v1 gpt-oss-120b
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
