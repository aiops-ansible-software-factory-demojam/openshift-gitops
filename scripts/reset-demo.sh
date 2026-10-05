#!/usr/bin/env bash
# Compatibility entry point; all reset behavior lives in bootstrap.sh.
exec bash "$(dirname -- "${BASH_SOURCE[0]}")/../bootstrap/bootstrap.sh" demo-reset "$@"
