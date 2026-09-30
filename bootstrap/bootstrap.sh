#!/usr/bin/env bash
set -euo pipefail

bootstrap_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$bootstrap_dir/.." && pwd)
operator_namespace=openshift-gitops-operator
gitops_namespace=openshift-gitops
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# shellcheck source=model-env.sh
source "$bootstrap_dir/model-env.sh"
unset model_key
: "${RH_AUTOMATIONHUB_TOKEN:?Populate RH_AUTOMATIONHUB_TOKEN in .env}"
[[ -r ${AAP_LICENSE_FILE:-$repo_root/aap_manifest.zip} ]] || {
  echo 'Place aap_manifest.zip in the repo root before bootstrap.' >&2; exit 2;
}

demo_verify_cluster

# A demo branch can be tracked without committing branch-specific defaults.
# The branch must already contain the checked-out commit on origin.
gitops_branch=${BOOTSTRAP_BRANCH:-main}
git check-ref-format --branch "$gitops_branch" >/dev/null
target_revision=$(git -C "$repo_root" rev-parse HEAD)
published_revision=$(git -C "$repo_root" ls-remote origin "refs/heads/$gitops_branch" | cut -f1)
[[ $published_revision == "$target_revision" ]] || {
  echo "Publish the checked-out revision to origin/$gitops_branch before bootstrap." >&2; exit 1;
}
echo "Tracking GitOps branch $gitops_branch."

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
# root app so the first child sync can mount the model and agent spec.
oc apply -f "$repo_root/cluster/omnigent/omnigent-namespace.yaml"
oc apply -f "$repo_root/cluster/omnigent/omnigent-sandboxes-namespace.yaml"
oc apply -f "$repo_root/cluster/automation-orchestrator/automation-orchestrator-namespace.yaml"
oc apply -f "$repo_root/cluster/forgejo/forgejo-namespace.yaml"
oc apply -f "$repo_root/cluster/rhdh/rhdh-namespace.yaml"
if ! oc -n rhdh get secret rhdh-pg-credentials >/dev/null 2>&1; then
  umask 077
  db_password_file=$(mktemp)
  trap '[[ -z ${db_password_file:-} ]] || rm -f "$db_password_file"' EXIT
  openssl rand -hex 32 | tr -d '\n' > "$db_password_file"
  oc -n rhdh create secret generic rhdh-pg-credentials \
    --from-literal=username=backstage \
    --from-file=password="$db_password_file"
  rm -f "$db_password_file"
  db_password_file=
fi
oc -n forgejo create configmap forgejo-url \
  --from-literal="root-url=https://forgejo.$ingress_domain/" \
  --dry-run=client -o yaml | oc -n forgejo apply -f -
bash "$bootstrap_dir/model-config.sh"
bash "$bootstrap_dir/omnigent-auth.sh"

echo 'OpenShift GitOps is healthy; starting the app-of-apps rollout...'
# Native Argo Kustomize patches override child refs only on this cluster.
# Checked-in defaults remain main and are safe to merge.
yq '.' "$bootstrap_dir/config/root-application.yaml" | jq --arg branch "$gitops_branch" '
  .spec.source.targetRevision = $branch |
  .spec.source.kustomize.patches = [{
    target: {group: "argoproj.io", version: "v1alpha1", kind: "Application"},
    patch: ("- op: replace\n  path: /spec/source/targetRevision\n  value: " + ($branch | tojson) + "\n")
  }]' | oc -n "$gitops_namespace" apply -f -
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
for app in rhbk forgejo rhdh omnigent automation-orchestrator; do
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
  if [[ $app == forgejo ]]; then
    until oc -n forgejo get deployment forgejo >/dev/null 2>&1; do
      if (( SECONDS >= deadline )); then
        echo 'Timed out waiting for the Forgejo Deployment.' >&2
        exit 1
      fi
      sleep 5
    done
    bash "$repo_root/scripts/feature-demo.sh" hydrate
  fi
done
for route_ref in keycloak/keycloak forgejo/forgejo \
  omnigent/omnigent \
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
      { [[ "$route_ref" != automation-orchestrator/* ]] && \
        [[ -n "$route_host" ]]; }; then
      echo "Recreating $route_ref to release its old Route host."
      oc -n "$route_namespace" delete route "$route_name" --wait=true
    fi
  fi
  until route_json=$(oc -n "$route_namespace" get route "$route_name" \
    -o json 2>/dev/null) && \
    assigned_host=$(jq -r '.status.ingress[0].host // ""' <<<"$route_json") && \
    route_host=$(jq -r '.spec.host // ""' <<<"$route_json") && \
    [[ "$assigned_host" == *".$ingress_domain" ]] && \
    { [[ "$route_ref" == automation-orchestrator/* ]] || \
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

for app in openshift-pipelines agent-sandbox-operator openshift-virtualization omnigent automation-orchestrator ansible-automation-platform webapp-vms user-workload-monitoring; do
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

# Build only after the operator rollout, keeping image storage on a PVC.
sandbox_image_current() {
  local built_revision
  built_revision=$(oc -n omnigent-sandboxes get pipelineruns -l tekton.dev/pipeline=omnigent-opencode \
    -o json | jq -r '[.items[] | select(.status.conditions[0].status == "True")] |
      sort_by(.metadata.creationTimestamp) | last | .status.results[]? |
      select(.name == "SOURCE_COMMIT") | .value')
  [[ "$built_revision" =~ ^[0-9a-f]{40}$ ]] &&
    git -C "$repo_root" diff --quiet "$built_revision" HEAD -- cluster/omnigent/image
}
if [[ ${BOOTSTRAP_FORCE_SANDBOX_BUILD:-false} == true ]] ||
   ! oc -n omnigent-sandboxes get imagestreamtag omnigent-opencode:adt26.9.0-omni0.15.0-opencode1.18.32-v7 >/dev/null 2>&1 ||
   ! sandbox_image_current; then
  echo 'Building the OpenCode sandbox image from the current Git revision...'
  SANDBOX_BUILD_REVISION="$target_revision" bash "$bootstrap_dir/sandbox-image.sh"
fi
sandbox_image_current
oc get crd sandboxes.agents.x-k8s.io
oc -n omnigent rollout status deployment/omnigent --timeout=10m
desired_sandbox_image=$(yq -r '.data."config.yaml"' \
  "$repo_root/cluster/omnigent/omnigent-sandbox-config-configmap.yaml" |
  yq -r '.sandbox.kubernetes.image')
mounted_sandbox_image=$(oc -n omnigent exec deployment/omnigent -c omnigent -- \
  cat /etc/omnigent/config.yaml | yq -r '.sandbox.kubernetes.image')
desired_agent_path=$(yq -r '.data.OMNIGENT_BUILTIN_AGENT_DIRS' \
  "$repo_root/cluster/omnigent/omnigent-config-configmap.yaml")
mounted_agent_path=$(oc -n omnigent exec deployment/omnigent -c omnigent -- \
  printenv OMNIGENT_BUILTIN_AGENT_DIRS)
if [[ "$mounted_sandbox_image" != "$desired_sandbox_image" ||
      "$mounted_agent_path" != "$desired_agent_path" ]]; then
  echo 'Reloading Omnigent to use the current sandbox image and agent...'
  oc -n omnigent rollout restart deployment/omnigent
  oc -n omnigent rollout status deployment/omnigent --timeout=10m
fi
bash "$bootstrap_dir/verify-goldenpaths.sh"
# The Argo CD health check only requires the AutomationOrchestrator Ready
# condition. Wait for the UI and backend Deployments before publishing the
# dispatch workflow so the Route has endpoints.
for deploy in automation-orchestrator-ui automation-orchestrator-backend; do
  if oc -n automation-orchestrator get "deployment/$deploy" >/dev/null 2>&1; then
    oc -n automation-orchestrator rollout status "deployment/$deploy" --timeout=10m
  fi
done
oc -n omnigent delete secret omnigent-auth omnigent-machine-client \
  --ignore-not-found
if [[ ${BOOTSTRAP_RECONCILE_WORKFLOW:-true} == true ]]; then
  bash "$repo_root/cluster/automation-orchestrator/reconcile-omnigent-workflow.sh"
fi
bash "$bootstrap_dir/aap-ee.sh"
bash "$bootstrap_dir/aap-configure.sh"
echo "GitOps, Agent Sandbox, AO, and AAP webapp automation are ready on $gitops_branch."
echo 'Log into AAP and launch webapp_vm, then webapp_nginx.'
