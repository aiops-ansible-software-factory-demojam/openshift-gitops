#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -r "$scratch"' EXIT
export BOOTSTRAP_TEST_LOG="$scratch/oc.log"

cat > "$scratch/oc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$BOOTSTRAP_TEST_LOG"
case "$*" in
  *'.status.installedCSV}'*) printf 'openshift-gitops-operator.v1.21.0' ;;
  *'.spec.install.spec.deployments[*].name}'*) printf 'openshift-gitops-operator-controller-manager' ;;
  *'.status.sync.status}'*) printf 'Synced' ;;
  *'.status.health.status}'*) printf 'Healthy' ;;
  *'get applications -o custom-columns='*) printf 'cluster Synced Healthy\n' ;;
  *) : ;;
esac
EOF
chmod +x "$scratch/oc"

PATH="$scratch:$PATH" bash bootstrap/bootstrap.sh >/dev/null

namespace_line=$(grep -n 'apply -f .*openshift-gitops-operator-namespace.yaml' "$BOOTSTRAP_TEST_LOG" | cut -d: -f1)
subscription_line=$(grep -n 'apply -f .*openshift-gitops-operator-subscription.yaml' "$BOOTSTRAP_TEST_LOG" | cut -d: -f1)
argocd_get_line=$(grep -n 'get argocd openshift-gitops' "$BOOTSTRAP_TEST_LOG" | cut -d: -f1)
argocd_apply_line=$(grep -n 'apply --server-side --force-conflicts -f .*openshift-gitops-argocd.yaml' "$BOOTSTRAP_TEST_LOG" | cut -d: -f1)
root_apply_line=$(grep -n 'apply -f .*root-application.yaml' "$BOOTSTRAP_TEST_LOG" | cut -d: -f1)
health_line=$(grep -n "get application cluster -o jsonpath={.status.health.status}" "$BOOTSTRAP_TEST_LOG" | cut -d: -f1)

test "$namespace_line" -lt "$subscription_line"
test "$subscription_line" -lt "$argocd_get_line"
test "$argocd_get_line" -lt "$argocd_apply_line"
test "$argocd_apply_line" -lt "$root_apply_line"
test "$root_apply_line" -lt "$health_line"
test "$(grep -c 'rollout status deployment/openshift-gitops-operator-controller-manager' "$BOOTSTRAP_TEST_LOG")" -eq 1
test "$(grep -c 'wait --for=condition=Ready pod --all' "$BOOTSTRAP_TEST_LOG")" -eq 1

echo 'Bootstrap installs OLM objects, overlays the default ArgoCD, then watches the root app.'
