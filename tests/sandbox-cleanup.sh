#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -r "$scratch"' EXIT
export CLEANUP_TEST_LOG="$scratch/deleted"
cat > "$scratch/oc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  whoami*) echo mock-identity ;;
  '-n agent-sandboxes get sandboxclaims.extensions.agents.x-k8s.io '* )
    [[ ${CLEANUP_TEST_FAIL:-false} = false ]] || exit 23
    printf 'expired %s\n' "$(date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%SZ)"
    printf 'active %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ;;
  '-n agent-sandboxes delete sandboxclaim.extensions.agents.x-k8s.io '* )
    printf '%s\n' "$*" >> "$CLEANUP_TEST_LOG"
    ;;
  *) echo "Unexpected command: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$scratch/oc"
PATH="$scratch:$PATH" bash cluster/agent-sandboxes/cleanup.sh
test "$(wc -l < "$CLEANUP_TEST_LOG")" -eq 1
grep -q ' expired --ignore-not-found --cascade=foreground --wait=false' "$CLEANUP_TEST_LOG"
if CLEANUP_TEST_FAIL=true PATH="$scratch:$PATH" bash cluster/agent-sandboxes/cleanup.sh; then
  echo 'Cleanup swallowed an API error.' >&2
  exit 1
fi
test "$(wc -l < "$CLEANUP_TEST_LOG")" -eq 1
echo 'Cleanup expires old claims, preserves active claims and propagates API failures.'
