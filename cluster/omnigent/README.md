# Omnigent agent sessions

Omnigent runs the coding agent in a Kubernetes Sandbox. The API lives in
`omnigent`; each managed session gets a Sandbox and a 5 GiB home volume in
`omnigent-sandboxes`. The volume survives idle suspension.

## Follow an issue to a PR

After [bootstrap](../../README.md), incident detection creates a Forgejo issue
and EDA starts its remediation workflow. Backstage prepares `feature/issue-N`
before AO starts `automation-developer`. Open Omnigent from Homepage, sign in
with [demo Keycloak](../demojam-keycloak/README.md), and follow the session linked
from the AO execution for checks and the PR URL. The operator independently tests
and merges the nginx PR before its AAP recovery launch. Invoice AO retains native
production approval and deployment verification. The manual
issue-number dispatcher used for early testing has been removed.

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

The image includes Ansible Development Tools, OpenCode, the Kubernetes Python
client, and the pinned Ansible collections in
[`image/requirements.yml`](image/requirements.yml). This preloads the Molecule
provisioner, its dependencies, and `ansible.posix` for SELinux modules. The
collection search path includes the agent's home directory and the image's
`/usr/share/ansible/collections`, so unchanged test requirements need no download.

From the seeded `demo.webapp` collection root, run `molecule test --all`
to test every discovered scenario; nginx is currently the only scenario. New scenarios under
`extensions/molecule/` are included automatically. Set
`MOLECULE_GLOB=extensions/molecule/*/molecule.yml` when running outside the image;
the collection Makefile wrappers have been removed.
Keep the image's provisioner pin aligned with the collections' test requirements.
If an agent changes requirements, it must install them before testing. Production
dependencies still belong in the collection's `galaxy.yml` for AAP project sync.

The selected backend controls guests. AWS uses pinned RHEL 9 and RHEL 10 EC2
images with scoped Molecule credentials. CNV uses the existing CentOS Stream 10
DataSource in `molecule-tests`; that alternative was not part of the latest
AWS dual-application rehearsal. The dedicated test identity can manage test VMs
and clone OS disks; it cannot read Secrets or manage application VMs. The runner
does not automatically mount a Kubernetes API token.

With both scenarios enabled, separate nginx and Python coding sessions can run
concurrently. Each uses its own checkout and test ownership records. Source
`/etc/profile.d/molecule.sh` before testing; Python also requires
`/etc/profile.d/invoice.sh` and the committed `INVOICE_SOURCE_COMMIT`.
Every separate test/create/converge/check provisions fresh owned guests after
cleanup. Retain state and use `molecule destroy --all` in the same sandbox after interruption.
Never repair an agent branch while claiming its tests passed unchanged.

Independently export the exact published SHA with `git archive` into a temporary
source directory and use a separate collection installation directory. Require
clean matching source before/after; capture real exit codes for lint, units, build
and the complete lifecycle. Both AWS RHEL versions must pass. The PR publication
helper rejects generated collection caches and links outside the checkout.
An idle session alone is not acceptance; failed Python independent validation
stops AO. Automatic CI repair and a Forgejo Actions runner remain deferred.

Before pushing or opening a PR, `demo-goldenpath pr` exports the committed HEAD,
builds and installs it separately, and runs full production lint and unit tests.
It rejects unconditional command failure suppression and overrides of
`restorecon` failure handling. Uncommitted fixes cannot satisfy these checks.
The image includes the pinned baseline PDF parser for isolated unit fixtures;
production releases still use the separately approved artifact. These publication
checks complement the required fresh Molecule lifecycle and independent review.

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
