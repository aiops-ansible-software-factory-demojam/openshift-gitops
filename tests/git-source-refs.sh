#!/usr/bin/env bash
# Real local Git repositories exercise the release fetch path without GitHub,
# credentials, or cluster access. URL rewriting is confined to this process.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/bootstrap/bootstrap.sh"
scratch=$(mktemp -d)
trap 'find "$scratch" -type f -delete; find "$scratch" -depth -type d -empty -delete' EXIT
name=ansible-collection-demo.webapp
remote="https://github.com/aiops-ansible-software-factory-demojam/$name.git"
mkdir -p "$scratch/remotes"
git init -q -b main "$scratch/author"
git -C "$scratch/author" config user.name 'Release test'
git -C "$scratch/author" config user.email 'release-test@example.test'
git -C "$scratch/author" config commit.gpgsign false
git -C "$scratch/author" config tag.gpgsign false
printf 'release baseline\n' >"$scratch/author/content"
git -C "$scratch/author" add content
git -C "$scratch/author" commit -qm baseline
baseline=$(git -C "$scratch/author" rev-parse HEAD)
git -C "$scratch/author" tag -a v0.1.0-alpha.2 -m 'Annotated release fixture'
git -C "$scratch/author" tag lightweight
git -C "$scratch/author" tag collision
printf 'later development\n' >"$scratch/author/content"
git -C "$scratch/author" commit -qam development
development=$(git -C "$scratch/author" rev-parse HEAD)
git -C "$scratch/author" branch collision
git clone -q --bare "$scratch/author" "$scratch/remotes/$name.git"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.file://$scratch/remotes/.insteadOf"
export GIT_CONFIG_VALUE_0=https://github.com/aiops-ansible-software-factory-demojam/

assert_ref() {
  local selected=$1 expected=$2 resolved qualified commit
  resolved=$(demo_remote_revision "$remote" "$selected")
  read -r qualified commit <<<"$resolved"
  [[ $commit == "$expected" && $qualified == refs/* ]]
}
assert_ref main "$development"
assert_ref v0.1.0-alpha.2 "$baseline"
assert_ref lightweight "$baseline"
assert_ref refs/tags/collision "$baseline"
assert_ref refs/heads/collision "$development"
for selected in collision missing 'bad..ref' '--upload-pack=bad' refs/remotes/main; do
  if (demo_remote_revision "$remote" "$selected") >/dev/null 2>&1; then
    printf 'Expected ref to fail: %s\n' "$selected" >&2; exit 1
  fi
done

export SEED_CONFIG="$scratch/seed.json"
unset ANSIBLE_COLLECTION_DEMO_WEBAPP_BRANCH
jq -n --arg name "$name" --arg source "$remote" --arg commit "$baseline" \
  '{repositories:[{name:$name,source:$source,source_branch:"v0.1.0-alpha.2",source_commit:$commit}]}' >"$SEED_CONFIG"
checkout=$(demo_source_checkout "$name" "$scratch/checkout")
[[ $(git -C "$checkout" rev-parse HEAD) == "$baseline" ]]
[[ $(cat "$checkout/content") == 'release baseline' ]]
# A mismatched pin (including a moved release tag) cannot seed new contents.
jq --arg commit "$development" '.repositories[0].source_commit=$commit' "$SEED_CONFIG" >"$scratch/bad-pin.json"
if (SEED_CONFIG="$scratch/bad-pin.json" demo_source_checkout "$name" "$scratch/rejected") >/dev/null 2>&1; then
  echo 'A mismatched release commit must be rejected' >&2; exit 1
fi
git --git-dir="$scratch/remotes/$name.git" update-ref refs/tags/v0.1.0-alpha.2 "$development"
if (demo_source_checkout "$name" "$scratch/moved-tag") >/dev/null 2>&1; then
  echo 'A moved release tag must be rejected' >&2; exit 1
fi
# Explicit development overrides still work independently of release defaults.
checkout=$(ANSIBLE_COLLECTION_DEMO_WEBAPP_BRANCH=main demo_source_checkout "$name" "$scratch/development")
[[ $(git -C "$checkout" rev-parse HEAD) == "$development" ]]

# Every seeded input and the focused example must agree with the release lock.
release=$(jq -r .version "$root/release.json")
jq -e '.version as $release | .gitops.ref==$release and
  (.sources|length)==3 and all(.sources[]; .ref==$release)' "$root/release.json" >/dev/null
jq -e --slurpfile lock "$root/release.json" '
  (.repositories|length)==4 and all(.repositories[] | select(.name != "ansible-collection-demo.pythonapp"); . as $seed |
    any($lock[0].sources[]; .name==$seed.name and .repository==$seed.source and
      .ref==$seed.source_branch and .commit==$seed.source_commit and (.commit|test("^[0-9a-f]{40}$"))))
  ' "$root/cluster/forgejo/seed.json" >/dev/null
(
  source "$root/.env.demo.example"
  [[ $BOOTSTRAP_BRANCH == "$release" && $ANSIBLE_COLLECTION_TEMPLATE_BRANCH == "$release" &&
     $ANSIBLE_COLLECTION_DEMO_WEBAPP_BRANCH == "$release" && $DEMOJAM_ANSIBLE_BRANCH == "$release" ]]
  [[ -z $LITELLM_API_KEY && -z $AO_MODEL_API_KEY && -z $OMNIGENT_MODEL_API_KEY &&
     -z $AWS_BOOTSTRAP_ACCESS_KEY_ID && -z $AWS_BOOTSTRAP_SECRET_ACCESS_KEY ]]
  [[ $AWS_RHEL9_AMI_ID == "$(jq -r .aws.rhel9_ami_id "$root/release.json")" &&
     $AWS_RHEL10_AMI_ID == "$(jq -r .aws.rhel10_ami_id "$root/release.json")" ]]
)
gitops_branch=$release gitops_repo=$remote DEMO_BACKEND=aws demo_root_application gp3-csi |
  jq -e --arg release "$release" '.spec.source.targetRevision==$release and
    any(.spec.source.kustomize.patches[]; .target.kind=="Application" and
      (.patch|fromjson|any(.[]; .path=="/spec/source/targetRevision" and .value==$release)))' >/dev/null
printf 'Git refs: branches, annotated/lightweight tags, ambiguity, missing refs, commit pins and release configuration passed\n'
