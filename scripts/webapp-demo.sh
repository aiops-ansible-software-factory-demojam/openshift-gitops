#!/usr/bin/env bash
# Compatibility entry point; all implementation lives in bootstrap/bootstrap.sh.
set -euo pipefail
exec bash "$(dirname -- "${BASH_SOURCE[0]}")/../bootstrap/bootstrap.sh" webapp "$@"
