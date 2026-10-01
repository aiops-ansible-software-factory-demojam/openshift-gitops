# Forgejo collection smoke demo

The `forgejo` namespace runs a disposable Forgejo instance with SQLite
and Git data on one PVC. GitOps owns the deployment, Service, Route, and PVC.
The fixture in `fixtures/collection` becomes the public
`demo-owner/ansible-collection-demo` repository, containing `demo.webapp`. It
follows the collection-template layout, with a default hello-world Molecule
scenario and an `nginx` scenario that exercises `demo.webapp.nginx`. In a demo
Omnigent sandbox, run `molecule test`, `molecule test -s nginx`, or `make test`
from the collection root. Both scenarios use the shared CentOS Stream 10 YAML inventory;
the RHEL 10 entry is commented out pending repository prerequisites; serialize runs because the VM names are fixed. The fixture in
`fixtures/collection-template` becomes the Forgejo template repository used
by Developer Hub. The issue text is in `fixtures/readme-test-issue.md`.
AO runs the Developer Hub feature template before it starts the agent.

The fixture in [`fixtures/demojam-ansible`](fixtures/demojam-ansible/README.md)
becomes `demo-owner/demojam-ansible`. It contains inventory-driven AAP
configuration and OpenShift Virtualization VM create/delete automation.
`demo-agent` and `demo-reviewer` have write access. Normal hydration preserves
this repository's feature branches and reconciles its seed-owned `main` from
the checked-in fixture; a reset restores all repositories to their baseline.

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
`read:user` scopes. The agent can push a branch and open a PR. Hydration only
adds the catalog descriptor to a populated demo collection, preserving feature
work. It reconciles the template source and AAP config from their checked-in
fixtures. All hydration logic lives in `bootstrap/bootstrap.sh`.

To seed a different collection checkout, set `COLLECTION_SOURCE` to its path
before hydration. The seed takes a snapshot of tracked `HEAD` files and does
not modify the source checkout. Keep that commit stable for repeatable resets.

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
`fixtures/collection` is intentionally missing the requested README line so
each reset presents the same work to the agent. Launch it through AO's explicit
API workflow.
