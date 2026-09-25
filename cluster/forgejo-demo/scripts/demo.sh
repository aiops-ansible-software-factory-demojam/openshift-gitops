#!/usr/bin/env bash
# Lifecycle is deliberately fixed to this disposable namespace and PVC.
set -euo pipefail
set +x
root=$(cd "$(dirname "$0")/.." && pwd)
namespace=forgejo-demo
: "${FORGEJO_URL:?Set FORGEJO_URL to the public HTTPS URL of this demo instance}"
: "${EXPECTED_SERVER:?Set EXPECTED_SERVER to the target OpenShift API URL}"
FORGEJO_URL=${FORGEJO_URL%/}
host=${FORGEJO_URL#https://}
[[ $FORGEJO_URL == https://* && $host =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || {
  echo 'FORGEJO_URL must be an HTTPS URL with a DNS hostname and no path or port.' >&2; exit 2;
}
export FORGEJO_URL
state=${FORGEJO_STATE_DIR:-$root/.state}
umask 077
mkdir -p "$state"
cluster() {
  local server
  server=$(oc whoami --show-server)
  oc whoami
  [[ $server == "$EXPECTED_SERVER" ]] || {
    echo 'Unexpected cluster; check EXPECTED_SERVER before continuing.' >&2; exit 2;
  }
}
route() {
  local route_host
  route_host=$(oc -n "$namespace" get route forgejo-demo \
    -o jsonpath='{.status.ingress[0].host}')
  [[ $FORGEJO_URL == "https://$route_host" ]] || {
    echo 'FORGEJO_URL does not match the GitOps-managed Route host.' >&2; exit 2;
  }
}
bootstrap() {
  # Inspect usernames only; never read Kubernetes Secrets.
  local users
  users=$(oc -n "$namespace" exec deploy/forgejo-demo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user list)
  if ! printf '%s\n' "$users" | awk '{print $2}' | grep -qx demo-admin; then
    oc -n "$namespace" exec deploy/forgejo-demo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user create --username demo-admin --email admin@example.test --password demo-admin --admin --must-change-password=false >/dev/null
  else
    oc -n "$namespace" exec deploy/forgejo-demo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user change-password --username demo-admin --password demo-admin --must-change-password=false >/dev/null
  fi
  if [[ ! -s $state/admin-token ]]; then
    oc -n "$namespace" exec deploy/forgejo-demo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user generate-access-token --username demo-admin --token-name "demo-bootstrap-$(date +%s)" --scopes all --raw > "$state/admin-token.tmp"
    mv "$state/admin-token.tmp" "$state/admin-token"
  fi
}
seed() {
  bootstrap
  FORGEJO_TOKEN=$(cat "$state/admin-token")
  export FORGEJO_TOKEN
  "$root/scripts/seed.sh"
  if [[ ! -s $state/agent-token ]]; then
    oc -n "$namespace" exec deploy/forgejo-demo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user generate-access-token --username demo-agent --token-name demo-agent --scopes write:repository,write:issue,read:user --raw > "$state/agent-token.tmp"
    mv "$state/agent-token.tmp" "$state/agent-token"
  fi
  if [[ ! -s $state/rhdh-token ]]; then
    oc -n "$namespace" exec deploy/forgejo-demo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user generate-access-token --username demo-agent --token-name demo-rhdh --scopes write:repository,write:user,read:issue --raw > "$state/rhdh-token.tmp"
    mv "$state/rhdh-token.tmp" "$state/rhdh-token"
  fi
}
case ${1:-help} in
  deploy)
    cluster
    oc -n openshift-gitops get applications.argoproj.io forgejo-demo >/dev/null || {
      echo 'Sync the root GitOps application to create forgejo-demo first.' >&2; exit 2;
    }
    oc -n openshift-gitops wait --for=jsonpath='{.status.sync.status}'=Synced \
      applications.argoproj.io/forgejo-demo --timeout=600s
    oc -n "$namespace" rollout status deploy/forgejo-demo --timeout=300s
    route
    bootstrap
    echo "Ready at $FORGEJO_URL; credentials in $state (mode 600)."
    ;;
  seed) cluster; route; seed ;;
  reset)
    [[ ${2:-} == --confirm-forgejo-demo ]] || { echo 'Usage: demo.sh reset --confirm-forgejo-demo (erases demo data)' >&2; exit 2; }
    COLLECTION_SOURCE=${COLLECTION_SOURCE:-$root/fixtures/collection}
    export COLLECTION_SOURCE
    [[ -f $COLLECTION_SOURCE/galaxy.yml ]] || exit 2
    cluster
    [[ $(oc get namespace "$namespace" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}') == forgejo-demo ]] || exit 2
    route
    [[ $(oc -n openshift-gitops get applications.argoproj.io forgejo-demo -o jsonpath='{.spec.syncPolicy.automated.selfHeal}') == true ]] || {
      echo 'forgejo-demo must have GitOps self-heal enabled for reset.' >&2; exit 2;
    }
    old_uid=$(oc -n "$namespace" get pvc forgejo-demo -o jsonpath='{.metadata.uid}')
    oc -n "$namespace" scale deploy/forgejo-demo --replicas=0
    oc -n "$namespace" wait --for=delete pod -l app=forgejo-demo --timeout=180s
    oc -n "$namespace" delete pvc forgejo-demo --wait=true --timeout=180s
    rm -f "$state/admin-token" "$state/admin-token.tmp" "$state/agent-token" "$state/agent-token.tmp"
    new_uid=
    for ((attempt = 0; attempt < 60; attempt++)); do
      new_uid=$(oc -n "$namespace" get pvc forgejo-demo -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
      [[ -n $new_uid && $new_uid != "$old_uid" ]] && break
      sleep 5
    done
    [[ -n $new_uid && $new_uid != "$old_uid" ]] || {
      echo 'GitOps did not recreate the demo PVC within five minutes.' >&2; exit 1;
    }
    oc -n "$namespace" scale deploy/forgejo-demo --replicas=1
    oc -n "$namespace" rollout status deploy/forgejo-demo --timeout=300s
    seed
    ;;
  *) echo 'Usage: demo.sh deploy | seed | reset --confirm-forgejo-demo' ;;
esac
