#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -r "$scratch"' EXIT
cp -R cluster "$scratch/cluster"

old_host=$(yq -r '.spec.hostname.hostname' cluster/rhbk/keycloak.yaml)
old_domain=${old_host#*.}
host_prefix=${old_host%%.*}
CLUSTER_DIR="$scratch/cluster" bash scripts/set-domain.sh apps.new-demo.example.com
test "$(yq -r '.spec.hostname.hostname' "$scratch/cluster/rhbk/keycloak.yaml")" = \
  "$host_prefix.apps.new-demo.example.com"
if rg -q -F "$old_domain" "$scratch/cluster" -g '*.yaml' -g '!**/charts/**'; then
  echo 'set-domain.sh left the old ingress domain in a manifest.' >&2
  exit 1
fi
rg -q -F 'maas-rhdp.apps.maas.redhatworkshops.io' \
  "$scratch/cluster/openshell/image/policy.yaml"

if CLUSTER_DIR="$scratch/cluster" bash scripts/set-domain.sh not-a-domain 2>/dev/null; then
  echo 'set-domain.sh accepted a hostname without a dot.' >&2
  exit 1
fi

echo 'set-domain.sh replaces the authored apps.* domain and rejects invalid input.'
