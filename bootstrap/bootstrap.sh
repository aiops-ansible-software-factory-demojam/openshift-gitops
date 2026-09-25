#!/usr/bin/env bash
set -euo pipefail

bootstrap_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
operator_namespace=openshift-gitops-operator
gitops_namespace=openshift-gitops
export KUBECONFIG=${KUBECONFIG:-"$HOME/.kube/config"}

oc whoami --show-server
oc whoami

# The Route manifests request stable subdomains from this cluster's ingress
# controller. Forgejo also needs its public URL for links and callbacks.
ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default \
  -o jsonpath='{.status.domain}')
[[ -n "$ingress_domain" ]] || {
  echo 'The default ingress controller has no domain.' >&2
  exit 1
}

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
oc apply -f "$bootstrap_dir/../cluster/forgejo-demo/forgejo-demo-namespace.yaml"
oc -n forgejo-demo create configmap forgejo-demo-url \
  --from-literal="root-url=https://forgejo-demo.$ingress_domain/" \
  --dry-run=client -o yaml | oc -n forgejo-demo apply -f -
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
target_revision=$(git -C "$bootstrap_dir/.." rev-parse HEAD)
published_revision=$(git -C "$bootstrap_dir/.." ls-remote origin refs/heads/main |
  cut -f1)
if [[ "$published_revision" != "$target_revision" ]]; then
  echo 'Publish the checked-out revision to origin/main before bootstrap.' >&2
  exit 1
fi
oc -n "$gitops_namespace" annotate application cluster \
  argocd.argoproj.io/refresh=hard --overwrite

echo 'Waiting for Argo CD to refresh the root application...'
until [[ $(oc -n "$gitops_namespace" get application cluster \
  -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/refresh}') != hard ]]; do
  sleep 2
done

deadline=$((SECONDS + 3600))
# OpenShift preserves an explicit Route host when a manifest starts requesting
# a subdomain. Refresh each affected child app before recreating legacy Routes.
for app in rhbk forgejo-demo omnigent rhdh automation-orchestrator; do
  until oc -n "$gitops_namespace" get application "$app" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for the $app Application." >&2
      exit 1
    fi
    sleep 5
  done
  oc -n "$gitops_namespace" annotate application "$app" \
    argocd.argoproj.io/refresh=hard --overwrite
  until [[ $(oc -n "$gitops_namespace" get application "$app" \
    -o jsonpath='{.status.sync.revision}') == "$target_revision" ]]; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for $app to read $target_revision." >&2
      exit 1
    fi
    sleep 5
  done
done
for route_ref in keycloak/keycloak forgejo-demo/forgejo-demo \
  omnigent/omnigent rhdh/backstage-rhdh-developer-hub \
  automation-orchestrator/automation-orchestrator; do
  route_namespace=${route_ref%%/*}
  route_name=${route_ref#*/}
  if oc -n "$route_namespace" get route "$route_name" >/dev/null 2>&1; then
    route_host=$(oc -n "$route_namespace" get route "$route_name" \
      -o jsonpath='{.spec.host}')
    assigned_host=$(oc -n "$route_namespace" get route "$route_name" \
      -o jsonpath='{.status.ingress[0].host}')
    if [[ -n "$route_host" && "$route_host" != *".$ingress_domain" ]] || \
      [[ -n "$assigned_host" && "$assigned_host" != *".$ingress_domain" ]] || \
      { [[ "$route_ref" != rhdh/* && "$route_ref" != automation-orchestrator/* ]] && \
        [[ -n "$route_host" ]]; }; then
      echo "Recreating $route_ref to release its old Route host."
      oc -n "$route_namespace" delete route "$route_name" --wait=true
      if [[ "$route_ref" == rhdh/* ]]; then
        # The RHDH operator reconciles on Backstage changes, not Route deletion.
        oc -n rhdh annotate backstage rhdh-developer-hub \
          demo.openshift-gitops.io/route-reconcile="$target_revision" --overwrite
      fi
    fi
  fi
  until route_json=$(oc -n "$route_namespace" get route "$route_name" \
    -o json 2>/dev/null) && \
    assigned_host=$(jq -r '.status.ingress[0].host // ""' <<<"$route_json") && \
    route_host=$(jq -r '.spec.host // ""' <<<"$route_json") && \
    [[ "$assigned_host" == *".$ingress_domain" ]] && \
    { [[ "$route_ref" == rhdh/* || "$route_ref" == automation-orchestrator/* ]] || \
      [[ -z "$route_host" ]]; }; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for $route_ref on $ingress_domain." >&2
      exit 1
    fi
    sleep 5
  done
done
until [[ $(oc -n "$gitops_namespace" get application cluster \
  -o jsonpath='{.status.sync.status}') == Synced ]] && \
  [[ $(oc -n "$gitops_namespace" get application cluster \
  -o jsonpath='{.status.health.status}') == Healthy ]] && \
  [[ $(oc -n "$gitops_namespace" get application cluster \
  -o jsonpath='{.status.sync.revision}') == "$target_revision" ]]; do
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

for app in openshell omnigent automation-orchestrator; do
  oc -n "$gitops_namespace" annotate application "$app" \
    argocd.argoproj.io/refresh=hard --overwrite
  deadline=$((SECONDS + 1800))
  until [[ $(oc -n "$gitops_namespace" get application "$app" \
    -o jsonpath='{.status.sync.revision}') == "$target_revision" ]] && \
    [[ $(oc -n "$gitops_namespace" get application "$app" \
    -o jsonpath='{.status.sync.status}') == Synced ]] && \
    [[ $(oc -n "$gitops_namespace" get application "$app" \
    -o jsonpath='{.status.health.status}') == Healthy ]]; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for $app to sync $target_revision." >&2
      exit 1
    fi
    sleep 10
  done
done

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
sandbox_image_current() {
  local built_revision
  built_revision=$(oc -n openshell get builds -l buildconfig=omnigent-opencode \
    -o json | jq -r '[.items[] | select(.status.phase == "Complete")] |
      sort_by(.metadata.creationTimestamp) | last | .spec.revision.git.commit // empty')
  [[ "$built_revision" =~ ^[0-9a-f]{40}$ ]] &&
    git -C "$bootstrap_dir/.." diff --quiet "$built_revision" HEAD -- \
      cluster/openshell/image
}
if ! sandbox_image_current; then
  echo 'Building the OpenCode sandbox image from the current Git revision...'
  oc -n openshell start-build buildconfig/omnigent-opencode --wait --follow
fi
sandbox_image_current
oc -n openshell rollout status statefulset/openshell --timeout=10m
oc -n omnigent rollout status deployment/omnigent --timeout=10m
oc -n omnigent delete secret omnigent-auth omnigent-machine-client \
  --ignore-not-found
if [[ ${BOOTSTRAP_RECONCILE_WORKFLOW:-true} == true ]]; then
  bash "$bootstrap_dir/../cluster/automation-orchestrator/reconcile-omnigent-workflow.sh"
fi
echo 'The app-of-apps rollout, sandbox image, and dispatch workflow are ready.'
