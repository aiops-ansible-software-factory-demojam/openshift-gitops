#!/usr/bin/env bash
# Compatibility entry point; authentication and dispatch live in bootstrap.
set -euo pipefail
exec bash "$(dirname -- "${BASH_SOURCE[0]}")/../bootstrap/bootstrap.sh" dispatch-issue "$@"
