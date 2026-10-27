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
demo_source_checkout() { printf '%s\n' "$scratch/source"; }
mkdir -p "$scratch/source"
if (demo_source_preflight) >"$scratch/preflight" 2>&1; then
  echo 'Missing companion CI source must fail before reset.' >&2; exit 1
fi
rg -q 'Selected source demojam-ansible lacks playbooks/ci/webapp.yml' "$scratch/preflight"
aap_connect() { :; }
aap_find() { printf '{"id":30}\n'; }
aap_wait() { :; }
aap_request() {
  if [[ $1 == GET && $2 == projects/30/playbooks/ ]]; then
    printf '["playbooks/ci/webapp.yml"]\n'
  else
    printf '{"id":999}\n'
  fi
}
aap_upsert() { touch "$scratch/wrote-template"; return 1; }
if (demo_ci_configure) >"$scratch/configure" 2>&1; then
  echo 'Incomplete project playbooks must prevent CI configuration.' >&2; exit 1
fi
rg -q 'lacks playbooks/ci/publish.yml' "$scratch/configure"
[[ ! -e $scratch/wrote-template ]]
printf 'Stale source and missing Controller playbooks fail before destructive reset or CI template writes.\n'
