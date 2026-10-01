#!/usr/bin/env bash
# All entry points load the same operator inputs; generated credentials stay in Kubernetes.
set +x
demo_inherited_kubeconfig=${KUBECONFIG:-}
demo_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
demo_env_file=${ENV_FILE:-$demo_repo_root/.env}
if [[ -f $demo_env_file ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$demo_env_file"
  set +a
fi
export AAP_EE_IMAGE=${AAP_EE_IMAGE:-registry.redhat.io/ansible-automation-platform-27/ee-supported-rhel9@sha256:d97a6fc9c34132bfddf5c8f0db93a24fea67ed3db2094d15f78d7f4eba724f1f}
if [[ -n $demo_inherited_kubeconfig ]]; then
  KUBECONFIG=$demo_inherited_kubeconfig
fi
export KUBECONFIG=${KUBECONFIG:-}
unset demo_inherited_kubeconfig

demo_verify_cluster() {
  local demo_server
  [[ -n $KUBECONFIG ]] || {
    echo 'Export KUBECONFIG or set it explicitly in .env before cluster operations.' >&2
    return 2
  }
  demo_server=$(oc whoami --show-server) || return
  printf '%s\n' "$demo_server"
  oc whoami || return
  [[ -z ${DEMO_CLUSTER_SERVER:-} || $demo_server == "$DEMO_CLUSTER_SERVER" ]] || {
    echo 'The active cluster changed during this run; restart with the intended kubeconfig.' >&2
    return 2
  }
  # Nested entry points retain the server discovered at the start of this run.
  export DEMO_CLUSTER_SERVER="$demo_server"
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
