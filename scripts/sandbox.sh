#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo 'Usage: scripts/sandbox.sh create|list|exec|delete [OpenShell options]' >&2
  exit 2
fi
command -v openshell >/dev/null || {
  echo 'Install the OpenShell CLI before launching a sandbox.' >&2
  exit 2
}

export KUBECONFIG=${KUBECONFIG:-"$HOME/.kube/config"}
oc whoami --show-server
oc whoami
port=${OPENSHELL_LOCAL_PORT:-18080}
oc -n openshell port-forward svc/openshell "$port:8080" \
  --address 127.0.0.1 >/dev/null 2>&1 &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true' EXIT

for attempt in $(seq 1 30); do
  if curl --silent --output /dev/null "http://127.0.0.1:$port/health"; then
    break
  fi
  if ! kill -0 "$forward_pid" 2>/dev/null; then
    echo 'OpenShell port-forward stopped unexpectedly.' >&2
    exit 1
  fi
  sleep 1
done

openshell --gateway-endpoint "http://127.0.0.1:$port" sandbox "$@"
