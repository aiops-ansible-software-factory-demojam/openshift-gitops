#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/bootstrap/bootstrap.sh"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
printf 'DEMO_SCENARIO=selinux\n' >"$scratch/env"
(
  export ENV_FILE="$scratch/env" DEMO_SCENARIO=both
  demo_load_env
  [[ $DEMO_SCENARIO == both ]]
)
demo_source_checkout() { printf '%s\n' "$scratch/$1"; }
git() { printf '%040d\n' 1; }
export DEMO_SCENARIO=both
for file in demojam-ansible/playbooks/webapp/nginx-install.yml \
  demojam-ansible/playbooks/invoice/route.yml \
  demojam-ansible/playbooks/invoice/record-response.yml \
  demojam-ansible/playbooks/invoice/prepare-containment.yml \
  ansible-collection-demo.webapp/AGENTS.md \
  ansible-collection-demo.webapp/playbooks/deploy_webapp.yml \
  ansible-collection-demo.pythonapp/AGENTS.md \
  ansible-collection-demo.pythonapp/playbooks/invoice-remediate.yml \
  ansible-collection-demo.pythonapp/playbooks/contain-invoice.yml; do
  mkdir -p "$(dirname "$scratch/$file")"
  touch "$scratch/$file"
done
demo_source_preflight >/dev/null
rm "$scratch/demojam-ansible/playbooks/invoice/route.yml"
if (demo_source_preflight) >"$scratch/result" 2>&1; then
  echo 'Missing routing source must fail before reset.' >&2; exit 1
fi
rg -q 'lacks playbooks/invoice/route.yml' "$scratch/result"
export DEMO_SCENARIO=selinux
rm -rf "$scratch/ansible-collection-demo.pythonapp"
demo_source_preflight >/dev/null
printf 'Compatible source, missing router and nginx-only isolation checks passed.\n'
