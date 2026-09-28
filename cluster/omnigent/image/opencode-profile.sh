# Omnigent's native OpenCode harness isolates each session's XDG config and
# imports provider definitions from this user-level config. Its serve process
# intentionally ignores OPENCODE_CONFIG_CONTENT, so materialize it at login.
case ":$PATH:" in
  *:/opt/ansible-dev-tools/bin:*) ;;
  *) export PATH="$PATH:/opt/ansible-dev-tools/bin" ;;
esac

if [ -n "${OPENCODE_CONFIG_CONTENT:-}" ]; then
  opencode_config_dir="${HOME:-/home/omnigent}/.config/opencode"
  mkdir -p "$opencode_config_dir"
  chmod 700 "$opencode_config_dir"
  printf '%s\n' "$OPENCODE_CONFIG_CONTENT" >"$opencode_config_dir/opencode.json"
  chmod 600 "$opencode_config_dir/opencode.json"
  unset opencode_config_dir
fi
