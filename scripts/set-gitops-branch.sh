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

yq -y -i ".spec.source.targetRevision = \"$branch\"" \
  "$root/bootstrap/config/root-application.yaml"
yq -y -i ".default.app.source.targetRevision = \"$branch\"" \
  "$root/cluster/values.yaml"
