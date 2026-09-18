#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
domain=${1:?Usage: scripts/set-domain.sh apps.your-cluster.example.com}
if [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ || "$domain" != *.* ]]; then
  echo 'Supply an ingress domain, without a scheme or trailing slash.' >&2
  exit 1
fi
# Run once on a fresh checkout; changes are ordinary reviewable Git diffs.
find cluster -name '*.yaml' -type f -exec sed -i "s/apps\.demo\.example\.com/$domain/g" {} +
