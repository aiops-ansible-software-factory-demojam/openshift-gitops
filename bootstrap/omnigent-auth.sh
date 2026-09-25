#!/usr/bin/env bash
set -euo pipefail

if oc -n omnigent get secret omnigent-auth >/dev/null 2>&1 &&
   oc -n omnigent get secret omnigent-machine-client >/dev/null 2>&1 &&
   oc -n automation-orchestrator get secret omnigent-machine-client-credential >/dev/null 2>&1; then
  echo 'Using the existing Omnigent accounts and machine-client configuration.'
  exit 0
fi

umask 077
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
printf '%s' "$(openssl rand -hex 32)" >"$scratch/OMNIGENT_ACCOUNTS_COOKIE_SECRET"
printf '%s' "$(openssl rand -hex 24)" >"$scratch/OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD"
printf '%s' "$(openssl rand -hex 32)" >"$scratch/password"
printf '%s' automation-orchestrator >"$scratch/username"

python3 - "$scratch/OMNIGENT_ACCOUNTS_COOKIE_SECRET" "$scratch/password" \
  >"$scratch/OMNIGENT_MACHINE_CLIENT_SECRET_HASH" <<'PY'
import hashlib
import hmac
import pathlib
import sys

cookie = bytes.fromhex(pathlib.Path(sys.argv[1]).read_text())
client_secret = pathlib.Path(sys.argv[2]).read_bytes()
sys.stdout.write(hmac.new(cookie, client_secret, hashlib.sha256).hexdigest())
PY

oc -n omnigent create secret generic omnigent-auth \
  --from-file=OMNIGENT_ACCOUNTS_COOKIE_SECRET="$scratch/OMNIGENT_ACCOUNTS_COOKIE_SECRET" \
  --from-file=OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD="$scratch/OMNIGENT_ACCOUNTS_INIT_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | oc apply -f -
oc -n omnigent create secret generic omnigent-machine-client \
  --from-file=OMNIGENT_MACHINE_CLIENT_ID="$scratch/username" \
  --from-file=OMNIGENT_MACHINE_CLIENT_SECRET_HASH="$scratch/OMNIGENT_MACHINE_CLIENT_SECRET_HASH" \
  --dry-run=client -o yaml | oc apply -f -
oc -n automation-orchestrator create secret generic omnigent-machine-client-credential \
  --from-file=username="$scratch/username" \
  --from-file=password="$scratch/password" \
  --dry-run=client -o yaml | oc apply -f -
echo 'Omnigent accounts and machine-client credentials were created.'
