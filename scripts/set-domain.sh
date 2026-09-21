#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cluster_dir=${CLUSTER_DIR:-"$root/cluster"}
domain=${1:?Usage: scripts/set-domain.sh apps.your-cluster.example.com}
if [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ || "$domain" != *.* ]]; then
  echo 'Supply an ingress domain, without a scheme or trailing slash.' >&2
  exit 1
fi
current=$(find "$cluster_dir" -path '*/charts/*' -prune -o -name '*.yaml' -type f \
  -exec grep -hoE 'apps\.[a-z0-9.-]+' {} + | sort -u)
if [[ -z "$current" ]]; then
  echo "No apps.* ingress domain found under $cluster_dir." >&2
  exit 1
fi
if [[ $(printf '%s\n' "$current" | grep -c .) -ne 1 ]]; then
  echo "Expected one ingress domain under $cluster_dir, found:" >&2
  printf '%s\n' "$current" >&2
  exit 1
fi
escaped=$(printf '%s' "$current" | sed 's/[.[\*^$]/\\&/g')
find "$cluster_dir" -path '*/charts/*' -prune -o -name '*.yaml' -type f \
  -exec sed -i.bak "s/$escaped/$domain/g" {} +
find "$cluster_dir" -path '*/charts/*' -prune -o -name '*.yaml.bak' -type f -exec rm -f {} +
