# Forgejo issue-to-PR demo

A disposable OpenShift Forgejo 16.0.5 instance, SQLite and Git repositories on one
5 GiB PVC, with Bash automation (curl, jq, git, tar, openssl). Deployment/reset also
need `oc`. No dedicated Forgejo operator, PostgreSQL, Ansible runtime, or CI runner.
The image is pinned by digest. HTTP Git is served through an HTTPS Route; SSH and
Actions are disabled. Self-registration is disabled.

## Deploy and seed

The target is your OpenShift cluster, in a dedicated `forgejo-demo` namespace.
The root app-of-apps creates the `forgejo-demo` child Application, which owns the
namespace, `nonroot-v2` SCC grant, PVC, workload, Service, and Route. Bootstrap
reads the cluster's ingress domain and creates the ConfigMap used for Forgejo's
public URL. `bootstrap.sh` also seeds the users, three repositories, and the
example nginx UID issue, then provisions Backstage and sandbox credentials.
The manual scripts below remain useful for reset and standalone testing.
The script needs the cluster API URL and the assigned public HTTPS
Route URL; they must match the GitOps-managed resources.

```bash
cd cluster/forgejo-demo
cp .env.example .env
# Edit .env with your cluster API URL and published Forgejo Route URL.
source .env
./scripts/demo.sh deploy
./scripts/demo.sh seed
```

`deploy` waits for the GitOps child Application to be Synced and the Deployment to
be ready, then creates the demo administrator and bootstrap token. It does not
apply manifests. Use an HTTPS DNS hostname without a port or path. The PVC uses
the cluster's default StorageClass.

By default, `fixtures/collection` supplies `demo.greetings`, generated with
`ansible-galaxy collection init` (ansible-core 2.21.4). Its `nginx` role installs
and starts nginx on Rocky Linux 9. The UID request in `fixtures/nginx-uid-issue.md`
is the agent task. No external checkout is required.

To use a real collection, export `COLLECTION_SOURCE=/path/to/collection-checkout`.
Choose a collection with no tracked secrets. For a remote collection, clone
it locally first using that host's normal authentication. The snapshot excludes Git
history and untracked files, but includes all tracked files. The source checkout is
never modified. Seed preserves populated repositories and restores each demo password to its username.
Use reset when you need to remove demo changes and reproduce the baseline. Keep the
source checkout at the same commit for repeatable resets.

`seed.json` declares users, repository names and write collaborators. The default is:

- `demo-owner`: maintainer, owns `ansible-collection-demo` and `demo-notes`.
- `demo-agent`: write collaborator on the collection, able to push branches and open PRs.
- `demo-agent/ansible-collection-template`: source for the Backstage collection golden path.
- `demo-reviewer`: write collaborator on both repositories.
- `demo-admin`: separate bootstrap administrator.

Each repository may have a `source` pointing to a local Git checkout. The default
collection uses `COLLECTION_SOURCE`; other repos without a source get a README.
The default lifecycle token and webhook commands assume these default user/repo names.
If changing them, adjust those commands too.

For this private demo, every password equals the username: `demo-admin`,
`demo-owner`, `demo-agent`, and `demo-reviewer`. Deploy/seed restores these defaults.
No password files or password environment variables are needed.

Generated API credentials are stored in ignored, private `.state/` files:
`admin-token` and `agent-token`. Bootstrap keeps per-cluster copies under
`.state/<ingress-domain>/` and places the scoped agent token in Kubernetes
Secrets for Backstage and Omnigent. Give a standalone agent only `agent-token`, the instance URL, and
`demo-owner/ansible-collection-demo`. Its scopes are `write:repository`, `write:issue`,
and `read:user`, constrained by the user's collaborator permissions. These are
standalone demo identities.

## Configure the integration, then open the issue

Use a receiver reachable **from the Forgejo pod**. `localhost` on your laptop is
not reachable as the pod's localhost. Private network destinations are allowed;
add a specific hostname to `FORGEJO__webhook__ALLOWED_HOST_LIST` if needed.

```bash
# Keep FORGEJO_URL exported from .env.
export FORGEJO_TOKEN="$(cat .state/admin-token)"
export WEBHOOK_URL=https://your-agent-receiver.example/events
# Generate once; configure the same secret in the receiver.
(umask 077; openssl rand -hex 32 > .state/webhook-secret)
export WEBHOOK_SECRET="$(cat .state/webhook-secret)"
./scripts/webhook.sh demo-owner/ansible-collection-demo "$WEBHOOK_URL"

./scripts/create-nginx-uid-issue.sh
```

The webhook subscribes to every repository event supported by the pinned Forgejo
version: pushes, branches/tags, forks, all issue and PR events (including reviews),
wiki, repository, releases, packages and Actions outcomes. Actions outcomes require
Actions to be enabled separately. Forgejo's API has no wildcard. The event list
should be reviewed on a version upgrade.

Running `webhook.sh` again replaces hooks with the **same URL**, preserving other
integrations. It creates the replacement first; if deleting an old hook fails,
rerun to remove duplicates. Briefly overlapping hooks are possible during replacement.
A different URL adds an integration; remove a retired destination in the UI.

The receiver should verify the `X-Forgejo-Signature` HMAC-SHA256 over the raw body,
filter `X-Forgejo-Event: issues` with action `opened`, and deduplicate deliveries.
Ignore the agent's subsequent push/PR/comment events as task triggers to avoid loops.
The agent service itself is external to this bundle. OAuth, SMTP and CI runners are
not configured. Inspect webhook delivery history under repository Settings → Webhooks.

Setting `WEBHOOK_URL` and `WEBHOOK_SECRET` during seed/reset restores that integration
automatically. Issue creation is deliberately separate and creates a new issue on each
invocation, so a reset does not launch the agent before you are ready.

## Reset

Stop any external agent run before reset. This command stops the Deployment,
deletes the **demo PVC**, waits for ArgoCD to recreate it, and seeds users/repos:

```bash
export WEBHOOK_SECRET="$(cat .state/webhook-secret)"
# Keep WEBHOOK_URL exported to restore the integration.
./scripts/demo.sh reset --confirm-forgejo-demo
export FORGEJO_TOKEN="$(cat .state/admin-token)"
```

All demo repositories, issues, PRs, users, tokens, hooks and app configuration are
recreated. Passwords return to the usernames; admin and agent tokens rotate.
Update the external agent's token after reset. The webhook secret stays the same.
This touches only the `forgejo-demo` namespace and PVC. The script checks the
cluster URL, Route host, demo namespace label, and GitOps self-heal before deleting
anything. ArgoCD ignores only the Deployment replica count, so it does not
restore the pod while reset is replacing the PVC. A storage class
with `Retain` reclaim policy can leave old PVs behind; reset is not secure erasure.

## Using the scripts with another Forgejo

`seed.sh`, `webhook.sh` and `issue.sh` use `FORGEJO_URL` and `FORGEJO_TOKEN` directly.
Seed needs an admin token; `COLLECTION_SOURCE` is optional. The lifecycle
wrapper is the only part that invokes `oc`. User/repo seed is additive, not full
configuration reconciliation. All failures return nonzero without printing API
response bodies or credentials. Don't run these scripts with shell tracing.

## Verification

```bash
(cd scripts && shellcheck -x *.sh)
kustomize build . | kubeconform -strict -summary -skip Route
ansible-galaxy collection build fixtures/collection --output-path /tmp
```

Connect your agent endpoint with `scripts/webhook.sh` when ready.

Keep the deploying checkout's `.state/` when moving this bundle to another checkout:
it holds the generated API tokens and webhook secret.

References: [Forgejo Docker installation](https://forgejo.org/docs/v16.0/admin/installation/docker/),
[API schema](https://code.forgejo.org/swagger.v1.json),
[pinned webhook implementation](https://code.forgejo.org/forgejo/forgejo/src/tag/v16.0.5/routers/api/v1/utils/hook.go).

## nginx UID feature-request demo

The seeded collection contains `demo.greetings.nginx`, a Rocky Linux 9 role
that installs and starts nginx with its package-provided worker account.

After configuring your agent webhook, open the UID feature request with:

```bash
./scripts/create-nginx-uid-issue.sh
```

The script uses the exported `FORGEJO_URL` and reads `.state/admin-token` unless
`FORGEJO_TOKEN` is exported. Optionally pass another `owner/repo`.
Each invocation creates a new issue, so it can trigger the connected agent. The
request in `fixtures/nginx-uid-issue.md` covers default behavior, custom UID, UID
changes/conflicts, writable paths, worker identity, and HTTP availability.
UID configuration is intentionally left for the agent to implement.
