#!/usr/bin/env bash
# Read-only local and pre-install cluster checks; no completion or AAP requests.
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
command -v python3 >/dev/null || {
  echo 'FAIL tool python3: install Python 3 before running preflight.' >&2
  exit 2
}
exec python3 "$demo_repo_root/bootstrap/preflight.py"
