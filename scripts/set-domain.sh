#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cluster_dir=${CLUSTER_DIR:-"$root/cluster"}
domain=${1:?Usage: scripts/set-domain.sh apps.your-cluster.example.com}
if [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ || "$domain" != *.* ]]; then
  echo 'Supply an ingress domain, without a scheme or trailing slash.' >&2
  exit 1
fi
keycloak_host=$(yq -r '.spec.hostname.hostname' "$cluster_dir/rhbk/keycloak.yaml")
current=${keycloak_host#*.}
if [[ "$current" != apps.* ]]; then
  echo "No apps.* ingress domain found in the Keycloak hostname." >&2
  exit 1
fi
mapfile -d '' files < <(find "$cluster_dir" -path '*/charts/*' -prune -o \
  -name '*.yaml' -type f -print0)
escaped=$(printf '%s' "$current" | sed 's/[.[\*^$]/\\&/g')
sed -i.bak "s/$escaped/$domain/g" "${files[@]}"
find "$cluster_dir" -name '*.yaml.bak' -delete
