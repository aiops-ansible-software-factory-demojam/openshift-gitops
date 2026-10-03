# Forgejo collection smoke demo

The `forgejo` namespace runs a disposable Forgejo instance with SQLite
and Git data on one PVC. GitOps owns the deployment, Service, Route, and PVC.
Bootstrap snapshots the three GitHub sources declared in `seed.json`:

- `ansible-collection-demo.webapp` → `demo-owner/ansible-collection-demo.webapp`
- `ansible-collection-template` → `demo-agent/ansible-collection-template`
- `demojam-ansible` → `demo-owner/demojam-ansible`

GitHub owns the baseline contents. Each hydration refreshes Forgejo `main`
from the selected source branch with a normal commit; source history is not
imported. Forgejo stays writable, so the agent can push feature branches and
open PRs. Existing branches and PRs survive hydration. Changes merged only
into Forgejo `main` are replaced by the next GitHub refresh. Public GitHub
links and `__FORGEJO_URL__` placeholders are localized to this Forgejo instance.
GitHub fetches use the repository-scoped ghapp credential helper.
The example issue text remains in `fixtures/readme-test-issue.md`.
AO runs the Developer Hub feature template before it starts the agent.

Browser users authenticate through the independent
[demo Keycloak](../demojam-keycloak/README.md). Bootstrap maintains the `demojam-keycloak` OIDC
source; accounts are created on first login and `demo-admins` maps to site
administrators. The seed's local automation accounts remain available for
repository hydration and API tokens. Hydration restores OIDC after a reset.

The [demojam-ansible source](https://github.com/aiops-ansible-software-factory-demojam/demojam-ansible)
contains inventory-driven AAP configuration and OpenShift Virtualization
VM create/delete automation. `demo-agent` and `demo-reviewer` have write access.

## Hydrate

From the repository root, with `KUBECONFIG` set for the demo cluster:

```bash
oc whoami --show-server
oc whoami
bash scripts/feature-demo.sh hydrate
```

Hydration waits for Forgejo, creates or repairs demo users and collaborators,
seeds the collection, template source, and AAP config repository, and ensures the example issue
exists. It creates scoped `demo-agent` tokens for the Sandbox and Developer
Hub, then updates their Kubernetes Secrets. New agent Sandboxes receive
the agent token with the model settings. Credentials stay in ignored
`cluster/forgejo/.state/<ingress-domain>/` and Kubernetes Secrets.

The demo identities are `demo-owner`, `demo-agent`, and `demo-reviewer`; their
passwords equal their usernames on this disposable instance. `demo-agent` is
a write collaborator and its token has `write:repository`, `write:issue`, and
`read:user` scopes. The agent can push a branch and open a PR. All hydration logic lives in
`bootstrap/bootstrap.sh`. To change a baseline, update its GitHub source and
run `make demo-hydrate`. `seed.json` selects each source URL and branch.

Override source branches in the root `.env` using
`ANSIBLE_COLLECTION_TEMPLATE_BRANCH`, `ANSIBLE_COLLECTION_DEMO_WEBAPP_BRANCH`
and `DEMOJAM_ANSIBLE_BRANCH`. Nonempty inherited shell values override `.env`;
unset or empty settings use `seed.json`'s `source_branch`, then `main`.
For example, refresh just the demo collection from a feature branch while the
other repositories use their configured branches:

```bash
ANSIBLE_COLLECTION_DEMO_WEBAPP_BRANCH=feature/dev-tools make demo-hydrate
```

All three selected GitHub branches are fetched before any Forgejo baseline
changes. An invalid or missing branch stops hydration without a partial source
refresh. Branch names may contain slashes; a tag is not accepted as a branch.
The destination stays Forgejo `main`, and feature branches and PRs remain
writable. Bootstrap and demo reset honor the same settings. The initial AAP
metadata checkout uses the selected `DEMOJAM_ANSIBLE_BRANCH` too.

## Launch and inspect

Hydration prints the issue URL. Use its number in the AO API launcher:

```bash
bash scripts/dispatch-issue.sh 1
```

AO launches the `automation-developer` OpenCode agent in a new Agent Sandbox.
Backstage creates `feature/issue-1` before the agent session starts. The agent
runs `demo-goldenpath checkout 1` to read the issue and clone that branch,
then implements, checks, commits, and runs `demo-goldenpath pr 1 --body-file
<path>` to push and open a PR against `main`. The PR body references the
issue. Repeating `submit` updates the body of the open PR after review fixes.
The seeded issue asks for a single README line so reset and dispatch cycles
exercise the workflow without spending time on feature implementation.
AO completes when the task reaches Omnigent; the PR is asynchronous.
Inspect the Omnigent session for its outcome. There is no webhook trigger or
CI runner in this stage.

## Reset

From the repository root, use `make demo-reset` for a complete repeatable
cycle. It deletes `automation-developer` sessions and Sandboxes, removes the
seeded demo VMs through AAP and labelled Molecule VMs, then refuses to proceed
if VM/disk resources remain in the demo namespaces. It recreates
the selected `.env` model and agent configuration, resets Forgejo, and republishes
AO's dispatch workflow and refreshes AAP configuration. It leaves demo VMs
absent. It loads the selected provider credentials from the root `.env`.
It also removes catalog entries for collections generated in this disposable
Forgejo account. Other Omnigent sessions are preserved.

To reset only Forgejo, first stop active agent sessions. This command confirms
the cluster and Route, scales Forgejo down, deletes only the `forgejo`
PVC, waits for GitOps to recreate it, then hydrates the collection, issue, and
new agent token:

```bash
bash scripts/feature-demo.sh reset --confirm-forgejo
```

Reset erases all demo repositories, issues, PRs, users, tokens, and webhooks.
The new token reaches new Sandbox Pods; an older running Pod retains its old
environment, so use a new session after reset. The reset script requires the
GitOps Application to have self-heal enabled. A `Retain` storage reclaim
policy may leave the old PV; reset is not secure erasure.

`seed.json` declares the collection, collection template, and AAP config repositories.
The GitHub collection baseline is intentionally missing the requested README line so
each reset presents the same work to the agent. Launch it through AO's explicit
API workflow.
