#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../../../bootstrap/bootstrap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../bootstrap/bootstrap.sh"
set +x
: "${FORGEJO_URL:?Set FORGEJO_URL}" "${FORGEJO_TOKEN:?Set FORGEJO_TOKEN}"
FORGEJO_URL=${FORGEJO_URL%/}
api() { forgejo_api "$@"; }
