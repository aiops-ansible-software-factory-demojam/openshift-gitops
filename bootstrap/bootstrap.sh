#!/usr/bin/env bash
set -euo pipefail

bootstrap_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
operator_namespace=openshift-gitops-operator
gitops_namespace=openshift-gitops
export KUBECONFIG=${KUBECONFIG:-"$HOME/.kube/config"}

oc whoami --show-server
oc whoami

# Argo CD reads main from GitHub. Publish the cluster's actual ingress domain
# before installing the root Application, so first sync uses routable hosts.
ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default \
  -o jsonpath='{.status.domain}')
keycloak_host=$(yq -r '.spec.hostname.hostname' \
  "$bootstrap_dir/../cluster/rhbk/keycloak.yaml")
if [[ "${keycloak_host#*.}" != "$ingress_domain" ]]; then
  if [[ -n $(git -C "$bootstrap_dir/.." status --porcelain) ]]; then
    echo 'Publish local changes before bootstrap can update the ingress domain.' >&2
    exit 1
  fi
  bash "$bootstrap_dir/../scripts/set-domain.sh" "$ingress_domain"
  git -C "$bootstrap_dir/.." add cluster
  git -C "$bootstrap_dir/.." commit -m "Set demo ingress domain to $ingress_domain"
  git -C "$bootstrap_dir/.." push origin HEAD:main
fi

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
until oc get clusterrolebinding openshift-gitops-demo-manager >/dev/null 2>&1; do
  sleep 5
done
# The environment-provided keycloak namespace exists before GitOps. Label it so
# the operator grants the application controller rights to adopt Keycloak.
oc label namespace keycloak argocd.argoproj.io/managed-by=openshift-gitops --overwrite
# These namespaces also hold bootstrap-owned Secrets. Create them before the
# root app so the first child sync can mount the model and encryption keys.
oc apply -f "$bootstrap_dir/../cluster/openshell/openshell-namespace.yaml"
oc apply -f "$bootstrap_dir/../cluster/omnigent/omnigent-namespace.yaml"
oc apply -f "$bootstrap_dir/../cluster/automation-orchestrator/automation-orchestrator-namespace.yaml"
if ! oc -n openshell get secret openshell-credential-encryption-key >/dev/null 2>&1; then
  umask 077
  scratch=$(mktemp -d)
  trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
  openssl rand -base64 32 >"$scratch/key-encryption-key"
  oc -n openshell create secret generic openshell-credential-encryption-key \
    --from-file=key-encryption-key="$scratch/key-encryption-key" \
    --dry-run=client -o yaml | oc apply -f -
fi
bash "$bootstrap_dir/model-config.sh"
bash "$bootstrap_dir/omnigent-auth.sh"

echo 'OpenShift GitOps is healthy; starting the app-of-apps rollout...'
oc apply -f "$bootstrap_dir/config/root-application.yaml"

echo 'Waiting for Argo CD to refresh the root application...'
until [[ $(oc -n "$gitops_namespace" get application cluster \
  -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/refresh}') != hard ]]; do
  sleep 2
done

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

echo 'Waiting for the OpenCode sandbox image build...'
deadline=$((SECONDS + 1800))
until oc -n openshell get imagestreamtag omnigent-opencode:1.18.32 >/dev/null 2>&1; do
  oc -n openshell get builds -l buildconfig=omnigent-opencode \
    -o custom-columns=NAME:.metadata.name,PHASE:.status.phase --no-headers || true
  if (( SECONDS >= deadline )); then
    echo 'Timed out waiting for the OpenCode sandbox image.' >&2
    exit 1
  fi
  sleep 15
done
source_revision=$(git -C "$bootstrap_dir/.." rev-parse HEAD)
if ! oc -n openshell get builds -l buildconfig=omnigent-opencode -o json |
    jq -e --arg revision "$source_revision" \
      'any(.items[]; .status.phase == "Complete" and
        .spec.revision.git.commit == $revision)' >/dev/null; then
  echo 'Building the OpenCode sandbox image from the current Git revision...'
  oc -n openshell start-build buildconfig/omnigent-opencode --wait --follow
fi
oc -n openshell get builds -l buildconfig=omnigent-opencode -o json |
  jq -e --arg revision "$source_revision" \
    'any(.items[]; .status.phase == "Complete" and
      .spec.revision.git.commit == $revision)' >/dev/null
oc -n openshell rollout status statefulset/openshell --timeout=10m
oc -n omnigent rollout status deployment/omnigent --timeout=10m
if [[ ${BOOTSTRAP_RECONCILE_WORKFLOW:-true} == true ]]; then
  bash "$bootstrap_dir/../cluster/automation-orchestrator/reconcile-omnigent-workflow.sh"
fi
echo 'The app-of-apps rollout, sandbox image, and dispatch workflow are ready.'
