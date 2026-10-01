#!/usr/bin/env bash
# Installed-later APIs are checked here, immediately before their use.
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
demo_verify_cluster
case ${1:-} in
  sandbox)
    oc -n openshift-cnv wait --for=condition=Available hyperconverged/kubevirt-hyperconverged --timeout=15m
    oc -n openshift-cnv wait --for=condition=Available kubevirt/kubevirt-kubevirt-hyperconverged --timeout=15m
    oc wait --for=condition=Ready tektonconfig/config --timeout=15m
    oc wait --for=condition=Established crd/sandboxes.agents.x-k8s.io --timeout=15m
    oc -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=15m
    oc -n agent-sandbox-system rollout status deployment/sandbox-router-deployment --timeout=15m
    oc -n openshift-virtualization-os-images wait --for=condition=Ready datasource/centos-stream10 --timeout=15m
    ;;
  aap)
    oc -n ansible-automation-platform wait --for=condition=Successful ansibleautomationplatform/aap --timeout=15m
    for deployment in aap-gateway aap-controller-web aap-controller-task; do
      oc -n ansible-automation-platform rollout status "deployment/$deployment" --timeout=15m
    done
    oc -n openshift-virtualization-os-images wait --for=condition=Ready datasource/rhel9 --timeout=15m
    ;;
  *) echo 'Usage: readiness.sh sandbox | aap' >&2; exit 2 ;;
esac
