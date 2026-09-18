#!/usr/bin/env bash
set -euo pipefail
namespace=agent-sandboxes
oc whoami --show-server
oc whoami

ready=$(oc -n "$namespace" get sandboxwarmpool.extensions.agents.x-k8s.io python-kata \
  -o jsonpath='{.status.readyReplicas}')
if [[ ${ready:-0} -lt 1 ]]; then
  echo 'Enroll a Kata worker and set the GitOps warm pool replicas to 1 first.' >&2
  exit 1
fi

expires=$(date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)
claim=$(oc -n "$namespace" create -f - -o jsonpath='{.metadata.name}' <<EOF
apiVersion: extensions.agents.x-k8s.io/v1beta1
kind: SandboxClaim
metadata:
  generateName: smoke-
  namespace: agent-sandboxes
spec:
  warmPoolRef:
    name: python-kata
  lifecycle:
    shutdownTime: "$expires"
    shutdownPolicy: Delete
    ttlSecondsAfterFinished: 60
EOF
)
cleanup() {
  oc -n "$namespace" delete sandboxclaim.extensions.agents.x-k8s.io "$claim" \
    --ignore-not-found --cascade=foreground --timeout=120s
}
trap cleanup EXIT
oc -n "$namespace" wait --for=condition=Ready \
  "sandboxclaim.extensions.agents.x-k8s.io/$claim" --timeout=600s
sandbox=$(oc -n "$namespace" get sandboxclaim.extensions.agents.x-k8s.io "$claim" \
  -o jsonpath='{.status.sandbox.name}')
test -n "$sandbox"
oc -n "$namespace" wait --for=condition=Ready "pod/$sandbox" --timeout=600s
runtime=$(oc -n "$namespace" get pod "$sandbox" -o jsonpath='{.spec.runtimeClassName}')
test "$runtime" = kata
# Expand id inside the remote sandbox, not in this client shell.
# shellcheck disable=SC2016
oc -n "$namespace" exec "$sandbox" -c workspace -- /bin/bash -ec '
  test "$(id -u)" -ne 0
  test ! -e /var/run/secrets/kubernetes.io/serviceaccount/token
  python3 --version
  git --version
  printf sandbox-ok > /workspace/smoke.txt
'
result=$(oc -n "$namespace" exec "$sandbox" -c workspace -- cat /workspace/smoke.txt)
test "$result" = sandbox-ok
cleanup
trap - EXIT
oc -n "$namespace" wait --for=delete "sandbox.agents.x-k8s.io/$sandbox" --timeout=120s
oc -n "$namespace" wait --for=delete "pod/$sandbox" --timeout=120s
echo 'Kata session creation, non-root execution, file retrieval and cleanup passed.'
