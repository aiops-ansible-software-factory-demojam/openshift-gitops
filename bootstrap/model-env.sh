#!/usr/bin/env bash
# Validate the selected provider before bootstrap or a destructive demo reset.
# shellcheck disable=SC2034
case ${MODEL_PROVIDER:-opencode-go} in
  opencode-go)
    model_endpoint=${OPENCODE_GO_ENDPOINT:-https://opencode.ai/zen/go/v1}
    model_name=${OPENCODE_GO_MODEL:-gpt-6-luna}
    model_key=${OPENCODE_GO_API_KEY:?Populate OPENCODE_GO_API_KEY in .env}
    model_npm=@ai-sdk/openai
    ;;
  litellm)
    model_endpoint=${LITELLM_ENDPOINT:?Populate LITELLM_ENDPOINT in .env}
    model_name=${LITELLM_MODEL:?Populate LITELLM_MODEL in .env}
    model_key=${LITELLM_API_KEY:?Populate LITELLM_API_KEY in .env}
    model_npm=@ai-sdk/openai-compatible
    ;;
  *) echo 'MODEL_PROVIDER must be opencode-go or litellm.' >&2; exit 2 ;;
esac
model_endpoint=${model_endpoint%/}
if [[ $model_endpoint != https://* || $model_endpoint == *[[:space:]?#]* ||
      $model_endpoint == */chat/completions || $model_endpoint == */responses ]]; then
  echo 'The provider endpoint must be an HTTPS API base URL.' >&2; exit 2
fi
model_host=${model_endpoint#https://}
model_host=${model_host%%/*}
if [[ ! $model_host =~ ^[a-zA-Z0-9.-]+(:[0-9]+)?$ ||
      ! $model_name =~ ^[a-zA-Z0-9._:/-]+$ ]]; then
  echo 'Invalid provider endpoint host or model name.' >&2; exit 2
fi
