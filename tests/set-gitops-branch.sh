#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -r "$scratch"' EXIT

mkdir -p "$scratch/bootstrap/config" "$scratch/cluster" "$scratch/scripts"
cp bootstrap/config/root-application.yaml "$scratch/bootstrap/config/"
cp cluster/values.yaml "$scratch/cluster/"
cp scripts/set-gitops-branch.sh "$scratch/scripts/"

bash "$scratch/scripts/set-gitops-branch.sh" demo-alice
test "$(yq -r '.spec.source.targetRevision' \
  "$scratch/bootstrap/config/root-application.yaml")" = demo-alice
test "$(yq -r '.default.app.source.targetRevision' \
  "$scratch/cluster/values.yaml")" = demo-alice

bash "$scratch/scripts/set-gitops-branch.sh" demo-bob
test "$(yq -r '.spec.source.targetRevision' \
  "$scratch/bootstrap/config/root-application.yaml")" = demo-bob

if bash scripts/set-gitops-branch.sh 'bad branch' 2>/dev/null; then
  echo 'set-gitops-branch.sh accepted an invalid branch name.' >&2
  exit 1
fi

echo 'set-gitops-branch.sh updates root and app-of-apps targetRevision.'
