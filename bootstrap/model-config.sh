#!/usr/bin/env bash
set -euo pipefail

# Keep model credentials outside Git. The two Secrets are referenced by the
# GitOps-managed Omnigent Deployment and survive repeat bootstrap runs.
if [[ -z ${MODEL_API_KEY:-} ]] &&
   oc -n omnigent get secret omnigent-model >/dev/null 2>&1 &&
   oc -n omnigent get secret omnigent-agent >/dev/null 2>&1; then
  # OpenShell accepts environment values only on one line. Normalize Secrets
  # created by an earlier bootstrap without changing the existing API key.
  current_encoded=$(oc -n omnigent get secret omnigent-model -o json |
    jq -er '.data.OPENCODE_CONFIG_CONTENT')
  config=$(printf '%s' "$current_encoded" | base64 -d | jq -c .)
  encoded_config=$(printf '%s' "$config" | base64 -w0)
  if [[ "$current_encoded" != "$encoded_config" ]]; then
    oc -n omnigent patch secret omnigent-model --type merge \
      -p "$(jq -cn --arg value "$encoded_config" \
        '{data:{OPENCODE_CONFIG_CONTENT:$value}}')" >/dev/null
    if oc -n omnigent get deployment omnigent >/dev/null 2>&1; then
      oc -n omnigent rollout restart deployment/omnigent
    fi
  fi
  unset current_encoded config encoded_config
  echo 'Using the existing Omnigent model configuration.'
  exit 0
fi

model_secret_exists=false
if oc -n omnigent get secret omnigent-model >/dev/null 2>&1; then
  model_secret_exists=true
fi

provider=${MODEL_PROVIDER:-opencode-go}
case "$provider" in
  opencode-go)
    base_url=https://opencode.ai/zen/go/v1
    model=${MODEL_NAME:-kimi-k3}
    package=@ai-sdk/openai-compatible
    ;;
  openai)
    base_url=https://api.openai.com/v1
    model=${MODEL_NAME:-gpt-4.1-mini}
    package=@ai-sdk/openai
    ;;
  *)
    echo 'MODEL_PROVIDER must be opencode-go or openai.' >&2
    exit 2
    ;;
esac
if [[ ! "$model" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo 'MODEL_NAME may contain only letters, digits, dot, underscore and hyphen.' >&2
  exit 2
fi

model_key=${MODEL_API_KEY:-}
if [[ -z "$model_key" ]]; then
  if [[ ! -r /dev/tty ]]; then
    echo 'Set MODEL_API_KEY for noninteractive bootstrap.' >&2
    exit 2
  fi
  read -r -s -p "$provider API key: " model_key </dev/tty
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
jq -cn --arg base "$base_url" --arg model "$model" --arg package "$package" '
  {
    "$schema": "https://opencode.ai/config.json",
    model: ("demo/" + $model),
    provider: {
      demo: {
        npm: $package,
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

cat >"$scratch/demo.yaml" <<EOF
name: opencode-go-test
prompt: |
  You are a coding assistant working in a disposable demo sandbox.
  Follow the task, inspect the repository, and report what you changed.
executor:
  harness: opencode
  model: demo/$model
EOF

oc -n omnigent create secret generic omnigent-model \
  --from-file=OPENAI_API_KEY="$scratch/api-key" \
  --from-file=OPENCODE_CONFIG_CONTENT="$scratch/opencode-config.json" \
  --dry-run=client -o yaml | oc apply -f -
oc -n omnigent create secret generic omnigent-agent \
  --from-file=demo.yaml="$scratch/demo.yaml" \
  --dry-run=client -o yaml | oc apply -f -
if [[ "$model_secret_exists" == true ]] &&
   oc -n omnigent get deployment omnigent >/dev/null 2>&1; then
  oc -n omnigent rollout restart deployment/omnigent
fi
echo "Omnigent is configured for $provider model $model."
