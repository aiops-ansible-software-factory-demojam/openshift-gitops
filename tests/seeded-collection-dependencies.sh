#!/usr/bin/env bash
# Exercise real selective hydration against local Git repositories, without a cluster.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/bootstrap/bootstrap.sh"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
export FORGEJO_URL=https://forgejo.test FORGEJO_TOKEN=fixture-only
export SEED_CONFIG="$scratch/seed.json"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.file://$scratch/mirrors/.insteadOf"
export GIT_CONFIG_VALUE_0="$FORGEJO_URL/"
mkdir -p "$scratch/source" "$scratch/mirrors/demo-owner"
git init -q -b main "$scratch/source"
git init -q --bare "$scratch/mirrors/demo-owner/demojam-ansible.git"
cat >"$SEED_CONFIG" <<'JSON'
{"users":[{"username":"demo-owner"}],"repositories":[
{"owner":"demo-owner","name":"ansible-collection-demo.webapp","source":"https://github.com/aiops-ansible-software-factory-demojam/ansible-collection-demo.webapp.git","collaborators":[]},
{"owner":"demo-owner","name":"ansible-collection-demo.pythonapp","source":"https://github.com/aiops-ansible-software-factory-demojam/ansible-collection-demo.pythonapp.git","collaborators":[]},
{"owner":"demo-owner","name":"demojam-ansible","source":"https://github.com/aiops-ansible-software-factory-demojam/demojam-ansible.git","collaborators":[]}]}
JSON
cat >"$scratch/source/requirements.yml" <<'YAML'
---
collections:
  # Certified image directories and Galaxy dependencies must remain intact.
  - name: /usr/share/ansible/collections/ansible_collections/ansible/controller
    type: dir
  - name: ansible.posix
    version: 2.2.2
    source: https://galaxy.ansible.com
  - name: https://github.com/aiops-ansible-software-factory-demojam/ansible-collection-demo.webapp.git
    type: git
    version: main
  - name: https://github.com/aiops-ansible-software-factory-demojam/ansible-collection-demo.pythonapp.git
    type: git
    version: main
YAML
git -C "$scratch/source" add requirements.yml
git -C "$scratch/source" -c user.name=Fixture -c user.email=fixture@example.test commit -qm fixture
demo_source_checkout() {
  git clone -q "$scratch/source" "$2"
  printf '%s\n' "$2"
}
forgejo_api() {
  case "$1 $2" in
    'GET /admin/users?limit=50&page=1') printf '[]' ;;
    'GET /users/demo-owner/repos?limit=50&page=1') jq '[.repositories[]|{name}]' "$SEED_CONFIG" ;;
    'PATCH /repos/demo-owner/demojam-ansible') printf '{}' ;;
    *) printf 'Unexpected Forgejo operation: %s %s\n' "$1" "$2" >&2; return 1 ;;
  esac
}
demo_forgejo_seed_repos demojam-ansible
# Inspect the actual committed seed output, not only a rendering helper.
git --git-dir="$scratch/mirrors/demo-owner/demojam-ansible.git" show main:requirements.yml >"$scratch/seeded.yml"
yq . "$scratch/seeded.yml" | jq -e '
  .collections[0].name=="/usr/share/ansible/collections/ansible_collections/ansible/controller" and
  .collections[1].source=="https://galaxy.ansible.com" and .collections[1].version=="2.2.2" and
  .collections[2].name=="https://forgejo.test/demo-owner/ansible-collection-demo.webapp.git" and
  .collections[3].name=="https://forgejo.test/demo-owner/ansible-collection-demo.pythonapp.git" and
  all(.collections[]|select(.type=="git"); .version=="main")' >/dev/null
rg -q '^  # Certified image directories' "$scratch/seeded.yml"
# Repeating hydration must preserve the same baseline commit.
before=$(git --git-dir="$scratch/mirrors/demo-owner/demojam-ansible.git" rev-parse main)
demo_forgejo_seed_repos demojam-ansible
after=$(git --git-dir="$scratch/mirrors/demo-owner/demojam-ansible.git" rev-parse main)
[[ $before == "$after" ]]
printf 'Seeded collection dependencies: Forgejo source, main refs, other requirements and idempotence passed\n'
