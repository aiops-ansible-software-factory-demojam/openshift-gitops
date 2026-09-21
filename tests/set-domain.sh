#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -r "$scratch"' EXIT
cp -R cluster "$scratch/cluster"

domains() {
  find "$1" -name '*.yaml' -type f -exec grep -hoE 'apps\.[a-z0-9.-]+' {} + | sort -u
}

CLUSTER_DIR="$scratch/cluster" bash scripts/set-domain.sh apps.new-demo.example.com
test "$(domains "$scratch/cluster")" = apps.new-demo.example.com

if CLUSTER_DIR="$scratch/cluster" bash scripts/set-domain.sh not-a-domain 2>/dev/null; then
  echo 'set-domain.sh accepted a hostname without a dot.' >&2
  exit 1
fi

echo 'set-domain.sh replaces the authored apps.* domain and rejects invalid input.'
