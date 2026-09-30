#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# shellcheck source=model-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/model-env.sh"
demo_verify_cluster
agent_name=automation-developer
agent_file=${agent_name}.yaml
write_agent_spec() {
  local model=$1
  cat <<EOF
name: $agent_name
prompt: |
  AO runs the Backstage feature golden path before launching you. For an
  assigned issue, run demo-goldenpath checkout <number> to check out the
  existing feature/issue-<number> branch and read the issue. Read AGENTS.md.
  Make only the requested change, verify it, and review the final diff before
  committing. Write an accurate PR summary to a file outside the repository,
  then run demo-goldenpath pr <number> --body-file <path>. Report the PR URL.
  Never create the issue branch yourself or run the feature template again.
  Do not merge or push to main. Never print credentials or commit them.
executor:
  harness: opencode
  model: demo/$model
EOF
}

umask 077
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
printf '%s' "$model_key" >"$scratch/api-key"
unset model_key
# Keep the existing Secret key for in-place upgrades; the selected endpoint is
# the baseURL below, not the name of this environment variable.
jq -cn --arg base "$model_endpoint" --arg model "$model_name" \
  --arg npm "$model_npm" '
  {
    "$schema": "https://opencode.ai/config.json",
    model: ("demo/" + $model),
    provider: {
      demo: {
        npm: $npm,
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

write_agent_spec "$model_name" >"$scratch/$agent_file"

oc -n omnigent-sandboxes create secret generic omnigent-model \
  --from-file=OPENAI_API_KEY="$scratch/api-key" \
  --from-file=OPENCODE_CONFIG_CONTENT="$scratch/opencode-config.json" \
  --dry-run=client -o yaml | oc -n omnigent-sandboxes apply -f -
oc -n omnigent create secret generic omnigent-agent \
  --from-file="$agent_file=$scratch/$agent_file" \
  --dry-run=client -o yaml | oc -n omnigent apply -f -
if oc -n omnigent get deployment omnigent >/dev/null 2>&1; then
  oc -n omnigent rollout restart deployment/omnigent
fi
echo "Omnigent is configured for ${MODEL_PROVIDER:-opencode-go}: $model_endpoint model $model_name."
