#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../bootstrap/env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../bootstrap/env.sh"
action=${1:-}
case "$action" in
  create|nginx|delete|sync|verify) [[ $# -eq 1 ]] ;;
  *) echo 'Usage: webapp-demo.sh create | nginx | delete | sync | verify' >&2; exit 2 ;;
esac
demo_verify_cluster
demo_wait_for_api
case "$action" in
  create)
    bash "$demo_repo_root/bootstrap/readiness.sh" aap
    python3 "$demo_repo_root/bootstrap/aap-runtime.py" launch webapp_vm
    ;;
  nginx) python3 "$demo_repo_root/bootstrap/aap-runtime.py" launch webapp_nginx ;;
  delete) python3 "$demo_repo_root/bootstrap/aap-runtime.py" launch webapp_vm '{"vm_state":"absent"}' ;;
  sync) python3 "$demo_repo_root/bootstrap/aap-runtime.py" launch aap_configure_all ;;
  verify)
    oc -n webapp-vms wait --for=condition=Ready vm/webapp --timeout=15m
    host=$(oc -n webapp-vms get route webapp -o jsonpath='{.status.ingress[0].host}')
    curl --fail --silent --show-error "https://$host/" >/dev/null
    # Probe from the exporter's actual network location; no local port forwards.
    pod=$(oc -n blackbox-exporter get pods -l app=blackbox-exporter -o jsonpath='{.items[0].metadata.name}')
    metrics=$(oc -n blackbox-exporter exec "$pod" -- wget -qO- \
      'http://127.0.0.1:9115/probe?module=http_2xx&target=http%3A%2F%2Fwebapp.webapp-vms.svc.cluster.local%2F')
    [[ $metrics == *'probe_success 1'* ]] || { echo 'Webapp blackbox probe failed.' >&2; exit 1; }
    echo "RHEL webapp and blackbox probe are healthy: https://$host/"
    ;;
esac
