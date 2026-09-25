#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
export BOOTSTRAP_TEST_LOG="$scratch/oc.log"
export BOOTSTRAP_TEST_DOMAIN
BOOTSTRAP_TEST_DOMAIN=$(yq -r '.spec.hostname.hostname' cluster/rhbk/keycloak.yaml)
BOOTSTRAP_TEST_DOMAIN=${BOOTSTRAP_TEST_DOMAIN#*.}

cat >"$scratch/oc" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$BOOTSTRAP_TEST_LOG"
case "$*" in
  *'.status.domain}'*) printf '%s' "$BOOTSTRAP_TEST_DOMAIN" ;;
  *'.status.installedCSV}'*) printf 'openshift-gitops-operator.v1.21.0' ;;
  *'.spec.install.spec.deployments[*].name}'*) printf 'openshift-gitops-operator-controller-manager' ;;
  *'.status.sync.status}'*) printf 'Synced' ;;
  *'.status.health.status}'*) printf 'Healthy' ;;
  *'get secret omnigent-model -o json'*)
    printf '{"data":{"OPENCODE_CONFIG_CONTENT":"e30="}}' ;;
  *'get secret omnigent-machine-client-credential -o go-template='*'username'* )
    printf 'automation-orchestrator' ;;
  *'get secret omnigent-machine-client-credential -o go-template='*'password'* )
    printf 'demo-password' ;;
  *'get builds -l buildconfig=omnigent-opencode -o json'*)
    printf '{"items":[{"status":{"phase":"Complete"},"spec":{"revision":{"git":{"commit":"%s"}}}}]}' \
      "$(git rev-parse HEAD)" ;;
  *'get applications -o custom-columns='*) printf 'cluster Synced Healthy\n' ;;
  *) : ;;
esac
MOCK
chmod +x "$scratch/oc"

BOOTSTRAP_RECONCILE_WORKFLOW=false PATH="$scratch:$PATH" \
  bash bootstrap/bootstrap.sh >/dev/null

line() { rg -n "$1" "$BOOTSTRAP_TEST_LOG" | head -1 | cut -d: -f1; }
namespace_line=$(line 'apply -f .*openshift-gitops-operator-namespace.yaml')
subscription_line=$(line 'apply -f .*openshift-gitops-operator-subscription.yaml')
argocd_line=$(line 'apply --server-side --force-conflicts -f .*openshift-gitops-argocd.yaml')
permissions_line=$(line 'apply -f .*openshift-gitops-cluster-permissions.yaml')
model_line=$(line 'get secret omnigent-model')
root_line=$(line 'apply -f .*root-application.yaml')
image_line=$(line 'get imagestreamtag omnigent-opencode:1.18.32')

test "$namespace_line" -lt "$subscription_line"
test "$subscription_line" -lt "$argocd_line"
test "$argocd_line" -lt "$permissions_line"
test "$permissions_line" -lt "$model_line"
test "$model_line" -lt "$root_line"
test "$root_line" -lt "$image_line"
test "$(rg -c 'rollout status deployment/openshift-gitops-operator-controller-manager' "$BOOTSTRAP_TEST_LOG")" -eq 1
test "$(rg -c 'rollout status statefulset/openshell' "$BOOTSTRAP_TEST_LOG")" -eq 1
test "$(rg -c 'rollout status deployment/omnigent' "$BOOTSTRAP_TEST_LOG")" -eq 1

echo 'Bootstrap installs GitOps, creates model configuration, and waits for the sandbox image.'
