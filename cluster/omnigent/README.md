# Omnigent agent sessions

Omnigent runs the coding agent in a Kubernetes Sandbox. The API lives in
`omnigent`; each managed session gets a Sandbox and a 5 GiB home volume in
`omnigent-sandboxes`. The volume survives idle suspension.

## Follow an issue to a PR

After [bootstrap](../../README.md), run `make demo-hydrate` from the repository
root to find the issue number, then `make demo ISSUE=N`. Backstage prepares
`feature/issue-N` before AO starts `automation-developer`. Open the Omnigent
URL from Homepage, sign in with [demo Keycloak](../demojam-keycloak/README.md),
and inspect the printed session ID for checks and the PR URL. AO completion
confirms handoff; the agent keeps working asynchronously.

Enabled configured users receive read access to new workflow sessions.
Omnigent uses verified email identities and per-session permissions. AO obtains
a native token at `/oauth/token`; direct Keycloak tokens are not API tokens.
Removing an email from the admin roster does not demote an existing administrator.

Inside a Sandbox, the agent uses:

```bash
demo-goldenpath checkout 1
cd issue-1
# Implement, check, and commit the requested change.
demo-goldenpath pr 1 --body-file /tmp/pr-body.md
```

Replace `1` with the issue number. Checkout requires the existing Backstage
branch. Bootstrap supplies model configuration and scoped Forgejo credentials
through Secrets; Git askpass keeps credentials out of Git URLs.

## Run Molecule tests

The image includes Ansible Development Tools and OpenCode. From a generated
collection root, run `molecule test`. In the seeded `demo.webapp` collection,
`molecule test -s nginx` checks nginx; `make test` runs both scenarios sequentially.

Tests clone CentOS Stream 10 into `molecule-tests` with a 30 GiB disk, two
vCPUs, and 2 GiB RAM. The RHEL 10 inventory entry stays disabled until repository
prerequisites are configured. The dedicated test identity can manage test VMs
and clone OS disks; it cannot read Secrets or manage application VMs. The runner
does not automatically mount a Kubernetes API token.

Serialize runs across **all** sandboxes, collections, and scenarios sharing
`molecule-tests`: the fixed `centos-stream10` name means overlapping runs can
modify or delete each other's VM. The four-VM/120 GiB quota does not isolate runs.
After an interrupted test, run `molecule destroy` only when no other run uses
that VM. Resolve missing credential mounts or unready DataSources before testing.

## Image and session lifecycle

Publish image changes, run `make sandbox-build`, wait for success, then start
a fresh session. The build uses the checked-out published commit unless
`SANDBOX_BUILD_REVISION` overrides it, and reports `IMAGE`, `IMAGE_DIGEST`, and
`SOURCE_COMMIT`. `BOOTSTRAP_FORCE_SANDBOX_BUILD=true` forces a rebuild.

The mutable `omnigent-opencode:latest` tag uses `Always` pulls. Running containers
keep their image; restarted or resumed containers can pick up a newer build.
Do not rebuild during a demo that must keep one image version. The tag provides
no automatic rollback. Inspect failures before retrying:

```bash
export KUBECONFIG="$HOME/.kube/config"
oc whoami --show-server
oc whoami
oc -n omnigent rollout status deployment/omnigent
oc -n omnigent-sandboxes get pipelineruns,imagestream,sandboxes,pods
```
