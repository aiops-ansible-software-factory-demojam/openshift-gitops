# Omnigent isolates each native OpenCode session and imports provider
# definitions from the sandbox user's global OpenCode config.
if [ -n "${OPENCODE_CONFIG_CONTENT:-}" ]; then
  opencode_config_dir="${HOME:-/sandbox}/.config/opencode"
  mkdir -p "$opencode_config_dir"
  chmod 700 "$opencode_config_dir"
  printf '%s\n' "$OPENCODE_CONFIG_CONTENT" >"$opencode_config_dir/opencode.json"
  chmod 600 "$opencode_config_dir/opencode.json"
  unset opencode_config_dir
fi
