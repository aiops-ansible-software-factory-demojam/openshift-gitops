#!/usr/bin/env bash
set -euo pipefail

bootstrap_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
operator_namespace=openshift-gitops-operator
gitops_namespace=openshift-gitops

oc whoami --show-server
oc whoami

# Follow the Red Hat CLI installation flow: namespace, OperatorGroup, then
# Subscription. The operator creates the default cluster-scoped Argo CD instance.
oc apply -f "$bootstrap_dir/openshift-gitops-operator-namespace.yaml"
oc apply -f "$bootstrap_dir/openshift-gitops-operator-operatorgroup.yaml"
oc apply -f "$bootstrap_dir/openshift-gitops-operator-subscription.yaml"

echo 'Waiting for the OpenShift GitOps operator installation...'
until installed_csv=$(oc -n "$operator_namespace" get subscription openshift-gitops-operator \
  -o jsonpath='{.status.installedCSV}' 2>/dev/null) && [[ -n "$installed_csv" ]]; do
  sleep 5
done
oc -n "$operator_namespace" wait --for=jsonpath='{.status.phase}'=Succeeded \
  "clusterserviceversion/$installed_csv" --timeout=15m
operator_deployments=$(oc -n "$operator_namespace" get \
  "clusterserviceversion/$installed_csv" \
  -o jsonpath='{.spec.install.spec.deployments[*].name}')
for deployment in $operator_deployments; do
  oc -n "$operator_namespace" rollout status "deployment/$deployment" --timeout=10m
done

echo 'Waiting for the operator-created default Argo CD instance...'
until oc -n "$gitops_namespace" get argocd openshift-gitops >/dev/null 2>&1; do
  sleep 5
done

# Reconcile the default instance to the checked-in definition while retaining
# the special cluster-scoped permissions Red Hat grants to this instance.
oc apply --server-side --force-conflicts \
  -f "$bootstrap_dir/config/openshift-gitops-argocd.yaml"
oc apply -f "$bootstrap_dir/config/openshift-gitops-cluster-permissions.yaml"
oc -n "$gitops_namespace" wait --for=jsonpath='{.status.phase}'=Available \
  argocd/openshift-gitops --timeout=15m
oc -n "$gitops_namespace" wait --for=condition=Ready pod --all --timeout=15m

echo 'Waiting for the Argo CD cluster permissions...'
until [[ $(oc auth can-i \
  --as=system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller \
  patch kataconfigs.kataconfiguration.openshift.io) == yes ]]; do
  sleep 5
done

echo 'OpenShift GitOps is healthy; starting the app-of-apps rollout...'
oc apply -f "$bootstrap_dir/config/root-application.yaml"

deadline=$((SECONDS + 3600))
until [[ $(oc -n "$gitops_namespace" get application cluster \
  -o jsonpath='{.status.sync.status}') == Synced ]] && \
  [[ $(oc -n "$gitops_namespace" get application cluster \
  -o jsonpath='{.status.health.status}') == Healthy ]]; do
  oc -n "$gitops_namespace" get applications \
    -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
  if (( SECONDS >= deadline )); then
    echo 'Timed out waiting for the app-of-apps rollout.' >&2
    exit 1
  fi
  sleep 10
done

oc -n "$gitops_namespace" get applications \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
echo 'The app-of-apps rollout is Synced and Healthy.'
