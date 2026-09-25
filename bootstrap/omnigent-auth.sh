#!/usr/bin/env bash
set -euo pipefail

umask 077
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT

if oc -n automation-orchestrator get secret \
  omnigent-machine-client-credential >/dev/null 2>&1; then
  oc -n automation-orchestrator get secret omnigent-machine-client-credential \
    -o go-template='{{index .data "username" | base64decode}}' >"$scratch/username"
  oc -n automation-orchestrator get secret omnigent-machine-client-credential \
    -o go-template='{{index .data "password" | base64decode}}' >"$scratch/password"
else
  printf '%s' automation-orchestrator >"$scratch/username"
  printf '%s' "$(openssl rand -hex 32)" >"$scratch/password"
  oc -n automation-orchestrator create secret generic \
    omnigent-machine-client-credential \
    --from-file=username="$scratch/username" \
    --from-file=password="$scratch/password" \
    --dry-run=client -o yaml | oc apply -f -
fi

if [[ $(<"$scratch/username") != automation-orchestrator ]]; then
  echo 'The Omnigent proxy credential has an unexpected username.' >&2
  exit 1
fi
printf 'automation-orchestrator:%s\n' \
  "$(openssl passwd -apr1 -stdin <"$scratch/password")" \
  >"$scratch/htpasswd"
oc -n omnigent create secret generic omnigent-proxy-auth \
  --from-file=htpasswd="$scratch/htpasswd" \
  --dry-run=client -o yaml | oc apply -f -
echo 'Omnigent Route proxy authentication is configured.'
