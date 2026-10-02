#!/usr/bin/env bash
# Standalone Forgejo lifecycle remains available through the shared implementation.
set -euo pipefail
# shellcheck source=../../../bootstrap/bootstrap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../bootstrap/bootstrap.sh"
set +x
umask 077
demo_forgejo_lifecycle "$@"
