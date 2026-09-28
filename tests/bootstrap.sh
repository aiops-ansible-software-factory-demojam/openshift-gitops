#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
export BOOTSTRAP_TEST_LOG="$scratch/oc.log"
export BOOTSTRAP_TEST_DOMAIN=apps.demo.example.test
export BOOTSTRAP_TEST_IMAGE_READY="$scratch/image-ready"

cat >"$scratch/oc" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$BOOTSTRAP_TEST_LOG"
case "$*" in
  *'.status.domain}'*) printf '%s' "$BOOTSTRAP_TEST_DOMAIN" ;;
  *'.status.installedCSV}'*) printf 'openshift-gitops-operator.v1.21.0' ;;
  *'.spec.install.spec.deployments[*].name}'*) printf 'openshift-gitops-operator-controller-manager' ;;
  *'.status.sync.status}'*) printf 'Synced' ;;
  *'.status.sync.revision}'*) git rev-parse HEAD ;;
  *'.status.health.status}'*) printf 'Healthy' ;;
  *'get route '*'.spec.host}'*) printf 'old.apps.previous.example.test' ;;
  *'get route '*'.status.ingress[0].host}'*)
    printf 'old.apps.previous.example.test' ;;
  *'get route '*'-o json'*)
    command_line=$*
    route_name=${command_line#*get route }
    route_name=${route_name%% *}
    if rg -q "delete route $route_name --wait=true" "$BOOTSTRAP_TEST_LOG"; then
      printf '{"spec":{"host":""},"status":{"ingress":[{"host":"%s"}]}}' \
        "demo.$BOOTSTRAP_TEST_DOMAIN"
    else
      printf '{"spec":{"host":"old.apps.previous.example.test"},"status":{"ingress":[{"host":"old.apps.previous.example.test"}]}}'
    fi ;;
  *'get secret omnigent-model -o json'*)
    printf '{"data":{"OPENCODE_CONFIG_CONTENT":"e30="}}' ;;
  *'get secret omnigent-machine-client-credential -o go-template='*'username'* )
    printf 'automation-orchestrator' ;;
  *'get secret omnigent-machine-client-credential -o go-template='*'password'* )
    printf 'demo-password' ;;
  *'get builds -l buildconfig=omnigent-opencode -o json'*)
    printf '{"items":[{"status":{"phase":"Complete"},"spec":{"revision":{"git":{"commit":"%s"}}}}]}' \
      "$(git rev-parse HEAD)" ;;
  *'get imagestreamtag omnigent-opencode:adt26.9.0-omni0.15.0-opencode1.18.32'*)
    test -f "$BOOTSTRAP_TEST_IMAGE_READY" ;;
  *'start-build buildconfig/omnigent-opencode --wait --follow'*)
    touch "$BOOTSTRAP_TEST_IMAGE_READY" ;;
  *'exec deployment/omnigent -c omnigent -- cat /etc/omnigent/config.yaml'*)
    printf 'sandbox:\n  kubernetes:\n    image: previous-sandbox-image\n' ;;
  *'get applications -o custom-columns='*) printf 'cluster Synced Healthy\n' ;;
  *) : ;;
esac
MOCK
chmod +x "$scratch/oc"

cat >"$scratch/git" <<'MOCK_GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *' branch --show-current' ]]; then
  printf '%s\n' "$BOOTSTRAP_BRANCH"
elif [[ "$*" == *' ls-remote origin refs/heads/'* ]]; then
  printf '%s\t%s\n' "$(/usr/bin/git rev-parse HEAD)" "${*##* }"
elif [[ "$*" == *' add -- '* || "$*" == *' commit -m '* ||
        "$*" == *' push -u origin '* ]]; then
  exit 0
else
  exec /usr/bin/git "$@"
fi
MOCK_GIT
chmod +x "$scratch/git"

BOOTSTRAP_BRANCH=$(yq -r '.spec.source.targetRevision' \
  bootstrap/config/root-application.yaml) BOOTSTRAP_SEED_DEMO=false \
  BOOTSTRAP_VERIFY_GOLDENPATHS=false \
  BOOTSTRAP_RECONCILE_WORKFLOW=false PATH="$scratch:$PATH" \
  bash bootstrap/bootstrap.sh >/dev/null

line() { rg -n "$1" "$BOOTSTRAP_TEST_LOG" | head -1 | cut -d: -f1; }
namespace_line=$(line 'apply -f .*openshift-gitops-operator-namespace.yaml')
subscription_line=$(line 'apply -f .*openshift-gitops-operator-subscription.yaml')
argocd_line=$(line 'apply --server-side --force-conflicts -f .*openshift-gitops-argocd.yaml')
permissions_line=$(line 'apply -f .*openshift-gitops-cluster-permissions.yaml')
model_line=$(line 'get secret omnigent-model')
forgejo_url_line=$(line 'create configmap forgejo-demo-url')
root_line=$(line 'apply -f .*root-application.yaml')
image_line=$(line 'get imagestreamtag omnigent-opencode:adt26.9.0-omni0.15.0-opencode1.18.32')

test "$namespace_line" -lt "$subscription_line"
test "$subscription_line" -lt "$argocd_line"
test "$argocd_line" -lt "$permissions_line"
test "$permissions_line" -lt "$model_line"
test "$permissions_line" -lt "$forgejo_url_line"
test "$forgejo_url_line" -lt "$root_line"
test "$model_line" -lt "$root_line"
test "$root_line" -lt "$image_line"
test "$(rg -c 'start-build buildconfig/omnigent-opencode --wait --follow' "$BOOTSTRAP_TEST_LOG")" -eq 1
test "$(rg -c 'rollout status deployment/openshift-gitops-operator-controller-manager' "$BOOTSTRAP_TEST_LOG")" -eq 1
test "$(rg -c 'get crd sandboxes.agents.x-k8s.io' "$BOOTSTRAP_TEST_LOG")" -eq 1
test "$(rg -c 'rollout status deployment/omnigent' "$BOOTSTRAP_TEST_LOG")" -eq 2
test "$(rg -c 'rollout restart deployment/omnigent' "$BOOTSTRAP_TEST_LOG")" -eq 2
rg -q 'root-url=https://forgejo-demo.apps.demo.example.test/' "$BOOTSTRAP_TEST_LOG"
test "$(rg -c 'delete route .*--wait=true' "$BOOTSTRAP_TEST_LOG")" -eq 4

echo 'Bootstrap derives Forgejo URL, migrates legacy Routes, and waits for the sandbox image.'
