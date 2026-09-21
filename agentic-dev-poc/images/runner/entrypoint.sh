#!/bin/sh
set -eu
config="${HOME}/.config/openshell"
gateway="${config}/gateways/openshell"
mkdir -p "${gateway}/mtls"
if [ -f /etc/openshell-mtls/ca.crt ]; then
  cp /etc/openshell-mtls/ca.crt "${gateway}/mtls/ca.crt"
fi
if [ -f /etc/openshell-mtls/tls.crt ]; then
  cp /etc/openshell-mtls/tls.crt "${gateway}/mtls/tls.crt"
fi
if [ -f /etc/openshell-mtls/tls.key ]; then
  cp /etc/openshell-mtls/tls.key "${gateway}/mtls/tls.key"
fi
chmod 0700 "${config}" "${gateway}" "${gateway}/mtls" || true
printf '%s\n' openshell > "${config}/active_gateway"
if [ ! -f "${gateway}/metadata.json" ]; then
  openshell gateway add "https://openshell.openshell.svc.cluster.local:8080" \
    --name openshell \
    --local \
    --oidc-issuer "${OIDC_ISSUER}" \
    --oidc-client-id "${OIDC_CLIENT_ID}" \
    --oidc-audience "${OIDC_AUDIENCE}"
fi
exec python3 -m agentic_runner
