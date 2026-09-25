#!/usr/bin/env bash
set -euo pipefail

# Point the root Application and app-of-apps defaults at a publish branch so
# each demo cluster can sync its own Git history without fighting over main.
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
branch=${1:?Usage: scripts/set-gitops-branch.sh BRANCH}
if ! git check-ref-format --branch "$branch"; then
  echo "Invalid Git branch name: $branch" >&2
  exit 1
fi

python3 - "$root" "$branch" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
branch = sys.argv[2]
for relative, field in (
    ("bootstrap/config/root-application.yaml", "targetRevision"),
    ("cluster/values.yaml", "targetRevision"),
    ("cluster/openshell/omnigent-opencode-buildconfig.yaml", "ref"),
):
    path = root / relative
    content = path.read_text()
    updated, count = re.subn(
        rf"(?m)^(\s*{field}: )[^\n]+$",
        lambda match: match.group(1) + branch,
        content,
        count=1,
    )
    if count != 1:
        raise SystemExit(f"Could not find {field} in {path}")
    path.write_text(updated)
PY
