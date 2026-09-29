# Forgejo collection feature demo

The `forgejo-demo` namespace runs a disposable Forgejo instance with SQLite
and Git data on one PVC. GitOps owns the deployment, Service, Route, and PVC.
The fixture in `fixtures/collection` becomes the private
`demo-owner/ansible-collection-demo` repository. The issue text is in
`fixtures/nginx-uid-issue.md`. Developer Hub and its golden paths are not used.

## Hydrate

From the repository root, with `KUBECONFIG` set for the demo cluster:

```bash
oc whoami --show-server
oc whoami
bash scripts/feature-demo.sh hydrate
```

Hydration waits for Forgejo, creates or repairs demo users and collaborators,
seeds the collection if its repository is empty, and ensures the example issue
exists. It creates a scoped `demo-agent` token and adds it to the existing
`omnigent-model` Secret in `omnigent-sandboxes`. New agent Sandboxes receive
that token with the model settings. Credentials stay in ignored
`cluster/forgejo-demo/.state/<ingress-domain>/` and Kubernetes Secrets.

The demo identities are `demo-owner`, `demo-agent`, and `demo-reviewer`; their
passwords equal their usernames on this disposable instance. `demo-agent` is
a write collaborator and its token has `write:repository`, `write:issue`, and
`read:user` scopes. The agent can push a branch and open a PR. The seed does
not touch populated repositories, so rerunning hydration preserves agent work.

To seed a different collection checkout, set `COLLECTION_SOURCE` to its path
before hydration. The seed takes a snapshot of tracked `HEAD` files and does
not modify the source checkout. Keep that commit stable for repeatable resets.

## Launch and inspect

Hydration prints the issue URL. Use its number in the AO API launcher:

```bash
bash scripts/dispatch-issue.sh 1
```

AO launches the `automation-developer` OpenCode agent in a new Agent Sandbox.
The agent runs `forgejo-issue start 1` to read the issue and clone the repo,
then implements, checks, commits, and runs `forgejo-issue submit 1 --body-file
<path>` to push and open a PR against `main`. The PR body references the
issue. Repeating `submit` updates the body of the open PR after review fixes.
The issue asks the agent to execute UID-dependent Ansible expressions with a
numeric YAML value; lint and syntax checks do not evaluate task conditions.
AO completes when the task reaches Omnigent; the PR is asynchronous.
Inspect the Omnigent session for its outcome. There is no webhook trigger or
CI runner in this stage.

## Reset

Stop any active agent session before resetting. The command confirms the
cluster and Route, scales Forgejo down, deletes only the `forgejo-demo` PVC,
waits for GitOps to recreate it, then hydrates the collection, issue, and new
agent token:

```bash
bash scripts/feature-demo.sh reset --confirm-forgejo-demo
```

Reset erases all demo repositories, issues, PRs, users, tokens, and webhooks.
The new token reaches new Sandbox Pods; an older running Pod retains its old
environment, so use a new session after reset. The reset script requires the
GitOps Application to have self-heal enabled. A `Retain` storage reclaim
policy may leave the old PV; reset is not secure erasure.

`seed.json` declares the single collection repository and collaborators.
`fixtures/collection` is intentionally missing the nginx UID feature so each
reset presents the same work to the agent. Forgejo's optional webhook helper
scripts remain available for a later event-driven demo, but this flow uses
AO's explicit API launch.
