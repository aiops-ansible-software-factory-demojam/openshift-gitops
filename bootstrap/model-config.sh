#!/usr/bin/env bash
set -euo pipefail

# Keep the model key outside Git. The runner Secret lives with Sandboxes;
# the agent spec Secret is mounted by the Omnigent server.
if [[ -n ${MODEL_PROVIDER:-} ]]; then
  echo 'Use MODEL_BASE_URL and MODEL_NAME instead of MODEL_PROVIDER.' >&2
  exit 2
fi
go_base_url=https://opencode.ai/zen/go/v1
go_model=glm-5.3-flash
write_agent_spec() {
  local model=$1
  cat <<EOF
name: opencode-demo
prompt: |
  You are a coding assistant for Ansible collection feature work.
  Follow the task and repository AGENTS.md instructions. Work in the session
  workspace, explain changes, and run relevant tests. Do not merge changes.
  Never print credentials or put them in repository files.
executor:
  harness: opencode
  model: demo/$model
EOF
}

if [[ -z ${MODEL_API_KEY:-} && -z ${MODEL_BASE_URL:-} &&
      -z ${MODEL_NAME:-} ]] &&
   oc -n omnigent-sandboxes get secret omnigent-model >/dev/null 2>&1 &&
   oc -n omnigent get secret omnigent-agent >/dev/null 2>&1; then
  current_encoded=$(oc -n omnigent-sandboxes get secret omnigent-model -o json |
    jq -er '.data.OPENCODE_CONFIG_CONTENT')
  config=$(printf '%s' "$current_encoded" | base64 -d | jq -c .)
  current_base_url=$(jq -r '.provider.demo.options.baseURL // empty' <<<"$config")
  current_model=$(jq -r '.model // empty' <<<"$config")
  if [[ "$current_base_url" == "$go_base_url" &&
        "$current_model" != "demo/$go_model" ]]; then
    config=$(jq -c --arg model "$go_model" '
      .model = ("demo/" + $model) |
      .provider.demo.models = {($model): {name: $model}}
    ' <<<"$config")
    current_model="demo/$go_model"
  fi
  agent_spec=$(write_agent_spec "${current_model#demo/}")
  agent_encoded=$(printf '%s' "$agent_spec" | base64 -w0)
  current_agent_encoded=$(oc -n omnigent get secret omnigent-agent \
    -o jsonpath='{.data.demo\.yaml}')
  if [[ $agent_encoded != "$current_agent_encoded" ]]; then
    oc -n omnigent patch secret omnigent-agent --type merge \
      -p "$(jq -cn --arg value "$agent_encoded" \
        '{data:{"demo.yaml":$value}}')" >/dev/null
    if oc -n omnigent get deployment omnigent >/dev/null 2>&1; then
      oc -n omnigent rollout restart deployment/omnigent
    fi
  fi
  unset agent_spec agent_encoded current_agent_encoded
  encoded_config=$(printf '%s' "$config" | base64 -w0)
  if [[ "$current_encoded" != "$encoded_config" ]]; then
    oc -n omnigent-sandboxes patch secret omnigent-model --type merge \
      -p "$(jq -cn --arg value "$encoded_config" \
        '{data:{OPENCODE_CONFIG_CONTENT:$value}}')" >/dev/null
  fi
  unset current_encoded config encoded_config current_base_url current_model
  echo 'Using the existing Omnigent model configuration.'
  exit 0
fi

base_url=${MODEL_BASE_URL:-$go_base_url}
model=${MODEL_NAME:-$go_model}
if [[ "$base_url" != https://* || "$base_url" == *[[:space:]?#]* ||
      "$base_url" == */chat/completions ]]; then
  echo 'MODEL_BASE_URL must be an HTTPS API base URL ending before /chat/completions.' >&2
  exit 2
fi
model_host=${base_url#https://}
model_host=${model_host%%/*}
if [[ ! "$model_host" =~ ^[a-zA-Z0-9.-]+(:[0-9]+)?$ ]]; then
  echo 'MODEL_BASE_URL must contain a valid DNS host.' >&2
  exit 2
fi
base_url=${base_url%/}
if [[ "$base_url" == "$go_base_url" && "$model" != "$go_model" ]]; then
  echo "OpenCode Go always uses model $go_model." >&2
  exit 2
fi
if [[ ! "$model" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo 'MODEL_NAME may contain only letters, digits, dot, underscore and hyphen.' >&2
  exit 2
fi

model_key=${MODEL_API_KEY:-}
if [[ -z "$model_key" && "$base_url" == "$go_base_url" ]] &&
   command -v op >/dev/null 2>&1; then
  model_key=$(op item get opencode-go-subscription-key --vault lab_agents \
    --format json 2>/dev/null |
    jq -er '.fields[] | select(.label == "password") | .value' 2>/dev/null) ||
    model_key=
fi
if [[ -z "$model_key" ]]; then
  if [[ ! -r /dev/tty ]]; then
    echo 'Set MODEL_API_KEY for noninteractive bootstrap.' >&2
    exit 2
  fi
  read -r -s -p "API key for $base_url: " model_key </dev/tty
  printf '\n' >/dev/tty
fi
if [[ -z "$model_key" ]]; then
  echo 'The model API key cannot be empty.' >&2
  exit 2
fi

umask 077
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
printf '%s' "$model_key" >"$scratch/api-key"
unset model_key
# Keep the existing Secret key for in-place upgrades; the selected endpoint is
# the baseURL below, not the name of this environment variable.
jq -cn --arg base "$base_url" --arg model "$model" '
  {
    "$schema": "https://opencode.ai/config.json",
    model: ("demo/" + $model),
    provider: {
      demo: {
        npm: "@ai-sdk/openai-compatible",
        name: "Demo inference",
        options: {
          baseURL: $base,
          apiKey: "{env:OPENAI_API_KEY}"
        },
        models: {
          ($model): {
            name: $model
          }
        }
      }
    }
  }
' | tr -d '\n' >"$scratch/opencode-config.json"

write_agent_spec "$model" >"$scratch/demo.yaml"

oc -n omnigent-sandboxes create secret generic omnigent-model \
  --from-file=OPENAI_API_KEY="$scratch/api-key" \
  --from-file=OPENCODE_CONFIG_CONTENT="$scratch/opencode-config.json" \
  --dry-run=client -o yaml | oc apply -f -
oc -n omnigent create secret generic omnigent-agent \
  --from-file=demo.yaml="$scratch/demo.yaml" \
  --dry-run=client -o yaml | oc apply -f -
echo "Omnigent is configured for $base_url model $model."
