#!/usr/bin/env bash
# All entry points load the same operator inputs; generated credentials stay in Kubernetes.
set +x
demo_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
demo_env_file=${ENV_FILE:-$demo_repo_root/.env}
if [[ -f $demo_env_file ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$demo_env_file"
  set +a
fi
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}

demo_verify_cluster() {
  local demo_server
  demo_server=$(oc whoami --show-server)
  printf '%s\n' "$demo_server"
  oc whoami
  [[ -z ${EXPECTED_SERVER:-} || $demo_server == "$EXPECTED_SERVER" ]] || {
    echo 'Unexpected cluster; check EXPECTED_SERVER in .env.' >&2; exit 2;
  }
}

# SNO API server rollouts can briefly interrupt Kubernetes jobs.
demo_wait_for_api() {
  local deadline=$((SECONDS + 900))
  until oc get clusteroperator kube-apiserver --request-timeout=30s -o json |
    jq -e '(.status.conditions | map({key: .type, value: .status}) | from_entries) as $c |
      $c.Available == "True" and $c.Progressing == "False" and $c.Degraded == "False"' >/dev/null; do
    if (( SECONDS >= deadline )); then
      echo 'Timed out waiting for a stable OpenShift API server.' >&2; exit 1
    fi
    echo 'Waiting for the OpenShift API server to finish reconciling...'
    sleep 10
  done
}
