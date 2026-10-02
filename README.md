# Demo OpenShift GitOps

This repository bootstraps a disposable OpenShift enablement cluster with
OpenShift GitOps, OpenShift Virtualization, the Agent Sandbox operator,
Omnigent, Automation Orchestrator (AO), Ansible Automation Platform, and user
workload monitoring. Omnigent uses the Kubernetes
Agent Sandbox API directly:

```text
AO workflow -> Backstage feature template -> Forgejo feature branch
            -> Omnigent API -> Sandbox in omnigent-sandboxes
                            -> OpenCode with the .env model provider
```

Forgejo supplies the seeded collection and issue for an issue-to-PR demo.
Red Hat Developer Hub (Backstage) provides the mandatory issue branch golden
path. AO waits for its Scaffolder task and verifies the branch before it
launches the agent. The agent implements the change, pushes, and opens the PR.

## Quickstart

After meeting [Requirements](#requirements), run this transcript for a fresh
checkout. In the editor, populate the selected model provider's inputs and set
`AAP_LICENSE_FILE` to your subscription ZIP. Its default is `aap_manifest.zip`
in this checkout. Bootstrap creates `demojam-keycloak` for OpenShift console
and application login, retaining existing cluster providers for recovery.
Set `DEMO_USER_PASSWORD` in `.env`; it defaults to `changeme` for new users.

```bash
git clone https://github.com/aiops-ansible-software-factory-demojam/openshift-gitops.git
cd openshift-gitops
cp .env.example .env
chmod 600 .env
"${EDITOR:-vi}" .env
export KUBECONFIG="$HOME/.kube/config"
oc whoami --show-server
oc whoami
make bootstrap
```

The one bootstrap command checks prerequisites, installs the platform and apps,
seeds Forgejo, builds the sandbox image, configures AAP, creates the RHEL 9 VM,
installs nginx, and verifies HTTPS and monitoring. Wait for `Bootstrap completed`
and the printed application URLs before starting the demo.

Open the printed **Homepage** URL for a navigation page linking to all demo
applications, the OpenShift console, GitOps and monitoring. It uses the homelab
Homepage appearance and signs in through `demojam-keycloak`. Bootstrap generates
the links from actual Routes; `make homepage-refresh` updates them later.
See [Homepage configuration](cluster/homepage/README.md).

For a subsequent run from the same checkout, retain your populated `.env`:

```bash
git pull --ff-only
export KUBECONFIG="$HOME/.kube/config"
make bootstrap
```

Publish the checked-out revision to the selected `BOOTSTRAP_BRANCH` before
bootstrap. Successful bootstrap reports healthy applications, configured AAP,
and a ready RHEL webapp with working HTTPS and blackbox monitoring.
Run `make bootstrap` for the full setup. Plain `make` and `make help` list
commands without contacting services. Optional commands:

```bash
make help             # Show commands without contacting services
make render           # Render manifests locally into .rendered/
make preflight        # Check prerequisites without changing the cluster
make identity         # Reconcile demo users, groups and application login
make sandbox-build    # Rebuild the sandbox image through Tekton
```

Bootstrap runs the complete webapp flow. These commands remain available for
subsequent maintenance:

```bash
make webapp-create    # Clone the RHEL 9 guest through AAP
make webapp-nginx     # Configure nginx using demo.webapp.nginx
make webapp-verify    # Require healthy VM, HTTPS response and blackbox probe
```

For the issue-to-PR flow:

```bash
make demo-hydrate     # Print the seeded issue URL and its number
make demo ISSUE=N     # Replace N with that positive issue number
```

`demo` hydrates first, then prints the AO execution and Omnigent session IDs.
Its success confirms agent handoff. The agent continues asynchronously;
inspect its session for checks and the PR URL using the
[Omnigent session guide](cluster/omnigent/README.md).
Run `make demo-reset` to restore the configured starting point after either flow.
See the detailed [AAP guide](cluster/forgejo/fixtures/demojam-ansible/README.md)
and [Forgejo guide](cluster/forgejo/README.md).

## Requirements

Use a disposable OpenShift cluster with OLM, Red Hat and certified operator
catalogs, trusted HTTPS ingress, a default RWO StorageClass, and enough capacity for the
operators, databases, and applications. OpenShift Virtualization requires
hardware KVM support on at least one node; bootstrap waits for its
`HyperConverged` resource to become available and the `centos-stream10` and
`rhel9` DataSources to become Ready before sandbox testing or webapp cloning. The active `KUBECONFIG`
identity needs cluster-admin rights. Install `oc`, `kustomize`, `helm`, `yq`,
`jq`, `openssl`, `curl`, `git`, `unzip`, `ssh-keygen`, and standard GNU utilities
(`base64`, `tar`, `sed`, `awk`, `find`, `xargs`). The local bootstrap implementation
is Bash throughout; JSON/YAML and HTTP use the listed CLI tools.
Use GNU Make for setup and maintenance, and jq-wrapper `yq`: `yq '.'` must emit
JSON that `jq` can read. Preflight checks that contract with a small YAML fixture.

Validated tool versions on the workshop run (2026-10-01):

| Tool | Version |
| --- | --- |
| Bash | 5.2.26 |
| oc | 4.21 client |
| kustomize | 5.8.1 |
| helm | 4.3.0 |
| yq | 4.1.2, jq-wrapper contract |
| jq | 1.7.1 (installed RPM; version banner reports `jq-`) |
| OpenSSL | 3.5.8 |
| curl | 8.12.1 |
| git | 2.52.0 |
| unzip | 6.00 |
| OpenSSH / ssh-keygen | 9.9p1 |
| GNU Make | 4.4.1 |

`make preflight` aggregates required failures and advisory uncertainty. It checks
local tools, selected model inputs, both manifest ZIP layers and required RHEL
certificate/key material, then verifies the cluster identity, admin permissions,
ingress, default storage configuration, catalogs, registry, node pressure, and
the configured demo users file and legacy workshop Keycloak ownership. Secret existence uses metadata-only
API responses; it does not retrieve Secret data, contact AAP, or call a model.
Bootstrap runs these checks before its first mutation. The `demojam-keycloak` application
owns Red Hat build of Keycloak 26.6, its CNPG database, and an edge Route using
the default ingress certificate. Bootstrap provisions realm `demo`, generated
credentials, users and OIDC clients. Application containers and the bootstrap
host must trust the ingress certificate. See the [identity guide](cluster/demojam-keycloak/README.md)
for user configuration and migration from the previous workshop setup. The
default `demo-user` is an application administrator and OpenShift cluster
administrator for this disposable demo.

ZIP checks establish local structure and RHEL material; AAP's import validates
licensing. Preflight does not establish expiry, authenticity or CDN access.
Storage metadata does not prove new provisioning/RWO support; registry status
does not prove pulls; node metadata does not prove capacity or hardware KVM.
Installed-later APIs may be absent before bootstrap. The shared script's read-only
readiness functions gate KubeVirt, Tekton, Sandbox controllers and CentOS before
sandbox builds, and AAP workloads/RHEL 9 before AAP setup or webapp creation.

Argo CD reads this repository from its Git remote. Publish your changes before
bootstrap. `BOOTSTRAP_BRANCH` selects an already published branch; it defaults
to `main`. Bootstrap sets a cluster-local Argo Kustomize patch for child
Applications so the checked-in defaults can remain on `main`.

For a published feature-branch checkout, set `BOOTSTRAP_BRANCH` in `.env` or run:

```bash
BOOTSTRAP_BRANCH="$(git branch --show-current)" make bootstrap
```

`BOOTSTRAP_REPO_URL` optionally selects a public HTTPS repository instead of
`origin`; the root Application, children, AppProject and sandbox build use the
same source. `BOOTSTRAP_STORAGE_CLASS` optionally selects the AAP/monitoring
StorageClass; otherwise bootstrap discovers the cluster default. These overrides
are managed through Argo's Kustomize patches rather than temporary live edits.

## Local secrets

From the repo root, copy the template on a fresh checkout and populate it:

```bash
cp .env.example .env
chmod 600 .env
```

All bootstrap and demo entry points load the root `.env`. This is trusted Bash
configuration; quote values as in the template. Repository-relative license
paths and template expansions resolve from the checkout, even when invoked from
another directory. Export a nonempty `KUBECONFIG` in your shell; that value takes
precedence over `.env`. Otherwise set it explicitly in `.env`; missing
configuration fails with remediation. Colon-separated lists and paths containing
spaces are passed unchanged to `oc` for merging. Scripts discover the API
server and identity from the
active kubeconfig and retain that server through each workflow. No server URL
needs to be entered.
Place the subscription ZIP at root `aap_manifest.zip`; it must include AAP
licensing and a RHEL CDN entitlement for the guest. Both files are gitignored.

| Input | Purpose |
| --- | --- |
| `MODEL_PROVIDER=opencode-go` | Uses `OPENCODE_GO_API_KEY`, `OPENCODE_GO_ENDPOINT`, `OPENCODE_GO_MODEL` (default `gpt-6-luna`) |
| `MODEL_PROVIDER=litellm` | Uses `LITELLM_API_KEY`, `LITELLM_ENDPOINT`, `LITELLM_MODEL` |
| `AAP_LICENSE_FILE` | Optional override for the root subscription ZIP |
| `BOOTSTRAP_BRANCH` | Published branch, default `main`; a nonempty inherited value takes precedence |
| `BOOTSTRAP_REPO_URL` | Public HTTPS GitOps source, default `origin` |
| `BOOTSTRAP_STORAGE_CLASS` | AAP/monitoring StorageClass, default cluster default |
| `DEMO_USERS_FILE` | JSON user definitions, default `bootstrap/users.example.json` |

Provider endpoints are HTTPS API base URLs, ending before `/responses` or
`/chat/completions`. To switch providers, edit `.env`, then run:

```bash
make model-config
```

New sessions use that configuration. Existing sessions keep their launch
credentials; use `make demo-reset` when a clean issue-to-PR cycle is needed.
Bootstrap handles generated secrets: Keycloak administration and OIDC client
credentials, the RHDH database password,
Forgejo/Backstage tokens, AAP admin credentials, a namespace-scoped VM API token, and a VM SSH
key. It reuses runtime VM identities across reruns. The RHEL entitlement is
extracted from the manifest into an AAP credential. No local registry login,
Forgejo read token, or manually copied generated AAP password is required.

## Bootstrap

From the repository root:

```bash
oc whoami --show-server
oc whoami
make bootstrap
```

The same entry point works without Make:

```bash
bash bootstrap/bootstrap.sh
bash bootstrap/bootstrap.sh --help
```

The Makefile is the primary setup and maintenance interface. It invokes
`bootstrap/bootstrap.sh`, which contains platform setup and command dispatch.
`bootstrap/identity.sh` implements identity setup and `bootstrap/homepage.sh`
implements dashboard setup; both are sourced by `bootstrap.sh`. Demo scripts
source `bootstrap.sh` and call `demo_load_env` to load configuration. Sourcing
the script defines functions without executing setup.

| Command | Purpose |
| --- | --- |
| `make` / `make help` | List commands without contacting services |
| `make bootstrap` | Install and configure the full platform, provision the RHEL webapp, install nginx, and verify |
| `make preflight` | Check local inputs and cluster prerequisites without changes |
| `make render` | Render manifests locally into `.rendered/` |
| `make identity` | Reconcile demo users, groups, OIDC clients, and application login |
| `make homepage-refresh` | Refresh dashboard links, repositories, and environment details |
| `make model-config` | Apply `.env` model and agent configuration for new sessions |
| `make sandbox-build` | Build and publish the sandbox image through Tekton |
| `make demo-hydrate` | Seed Forgejo, refresh credentials, and print the starter issue URL |
| `make demo ISSUE=N` | Hydrate and dispatch issue N through AO; the agent continues asynchronously |
| `make demo-reset` | Remove disposable sessions, repos, VMs, and disks; reseed Forgejo and refresh AAP |
| `make aap-configure` | Refresh AAP credentials, license, foundation, and configuration from Forgejo |
| `make aap-sync` | Run the seeded AAP configuration playbook |
| `make webapp-create` | Provision the RHEL webapp VM through AAP |
| `make webapp-nginx` | Configure nginx through AAP |
| `make webapp-verify` | Check VM readiness, HTTPS login redirect, and blackbox probe |
| `make webapp-delete` | Delete the webapp VM and its owned disk through AAP |

The script installs GitOps, creates the model and internal Secrets, rolls out
all applications, hydrates Forgejo, builds the sandbox image, verifies golden
paths, and publishes AO's issue workflow. After reconciliation it imports the license, prepares persistent runtime
material, creates the minimal AAP foundation, and launches
`aap_configure_all` inside AAP Controller using the pinned Red Hat supported EE.
Bootstrap owns the organization, supported EE, public project, base inventory,
Galaxy/dispatch credentials and configuration template. Config-as-code owns
VM/SSH/RHEL credential types and credentials, inventory sources, demo job templates,
and gateway OIDC. No objects have competing Resource Operator and API owners.

GitOps installation disables the operator's default Argo instance and creates
`demojam-gitops` in `openshift-gitops` with native OIDC from its first start.
Existing default installations migrate once: the operator removes the old
controllers before the explicit instance starts. Argo UI access briefly pauses;
Application resources and deployed workloads persist. Keycloak callbacks and
Homepage links are refreshed for the new Route. Ordinary reruns need no Dex
patch, transport restart, or migration.

The Controller project clones public Forgejo and installs requirements from
Galaxy and Git. No custom AAP EE or Automation Hub token is required.
It waits for project/inventory synchronization. Rerunning preserves the VM
SSH identity and applies current config. It then launches `webapp_vm` and
`webapp_nginx`, waits for their Controller jobs, and requires VM readiness,
HTTPS access and a successful blackbox probe before reporting completion.
`BOOTSTRAP_FORCE_SANDBOX_BUILD=true`
forces a sandbox image rebuild.
Sandbox builds overwrite one `:latest` tag; new sandbox containers use Kubernetes'
`Always` pull policy. Publish image changes, finish the build, then start a fresh
session. Running containers retain their image, while restarted or resumed
containers can pick up a newer build. See
[image and session lifecycle](cluster/omnigent/README.md#image-and-session-lifecycle)
for rebuild and inspection commands.

On SNO, scripts wait for the API server to finish reconciling before AAP work.
Forgejo seeding waits for the public version API after Deployment readiness.
Sandbox builds tolerate interrupted log streams and status reads. AAP status checks
retry brief network interruptions; launch requests are sent once. Inspect AAP
before repeating a launch whose response was lost.

## Provision and automate the RHEL webapp

Bootstrap launches these templates in order. To run them again through the UI,
log into the AAP gateway Route as `admin`, using the operator-generated
`aap-admin-password` Secret in `ansible-automation-platform`:

1. **webapp_vm** clones the `rhel9` DataSource into `webapp-vms`, installs the
   bootstrap-generated public SSH key via cloud-init, and waits for VM Ready.
2. **webapp_nginx** refreshes VM inventory, connects with the matching SSH key,
   enables RHEL repositories using the manifest entitlement, and runs
   `demo.webapp.nginx` from the public example collection's Git repository.

GitOps owns the namespace, SSH/HTTP Services, HTTPS Route, RBAC and blackbox
Probe. Inventory discovers `webapp-webapp-vms` in the `webapps` group. The
blackbox target is expected to be down until nginx is installed.

The same operations are available from the repo root:

```bash
make webapp-create
make webapp-nginx
make webapp-verify
# Remove only the webapp VM and its owned disk:
make webapp-delete
```

To apply subsequent Forgejo config changes through AAP, run the
**aap_configure_all** template or `make aap-sync`. To bootstrap only
AAP, use `make aap-configure`. Bootstrap prepares the operator-created dispatch
template and its SCM inventory, launches it through the AAP API, and waits for
its Controller job to succeed. First and subsequent dispatches run inside AAP.
All demo templates and inventory sources use
Red Hat `ee-supported-rhel9`, pinned by digest. The seeded `demojam-ansible`
repository's [requirements.yml](cluster/forgejo/fixtures/demojam-ansible/requirements.yml)
installs `infra.aap_configuration` from public Galaxy and the example collection
from public Forgejo. Controller isolates its collection cache, so requirements
also copy CaC's certified dependencies from the supported image into that cache.
They do not download certified content or require a Hub token. OpenShift uses
its existing registry authentication to pull the supported EE. Tekton remains
for the separate OpenCode sandbox image build.

See the [AAP config guide](cluster/forgejo/fixtures/demojam-ansible/README.md)
for the script/dispatch boundary and reset behavior.

## Run an issue through AO

```bash
oc -n openshift-gitops get applications
oc -n agent-sandbox-system get csv
oc -n openshift-cnv get hyperconverged,kubevirt
oc -n omnigent rollout status deployment/omnigent
oc -n omnigent-sandboxes get pipelineruns,imagestream,sandboxes,pods
make demo-hydrate
make demo ISSUE=N
```

The [OpenShift Virtualization guide](cluster/openshift-virtualization/README.md)
includes a temporary CirrOS VM and a KVM acceleration check.

`demo-hydrate` is idempotent and prints the issue URL. Replace `N` with its
number. `demo` validates that number before hydration and calls AO's published
workflow through its API
and prints the AO execution and Omnigent session IDs. AO completion means the
branch exists and the agent accepted the task. Inspect the session for its
checks and PR URL.
Each session gets its own Sandbox. Delete the session when finished.

To reset the full issue-to-PR demo, run:

```bash
make demo-reset
```

This restores a configured demo with no running demo VMs. It removes
`automation-developer` sessions, Sandboxes and their home volumes; deletes
`webapp` and `automation-demo` through the seeded AAP templates; and removes
labelled Molecule VMs and their owned test disks from `molecule-tests`. It
refuses to continue if VM or disk resources remain in the three demo VM
namespaces. It recreates the selected `.env` model and agent Secrets, wipes
the disposable Forgejo PVC, and reseeds the README issue, collection template,
and `demo-owner/demojam-ansible` project. It then refreshes AAP's project,
inventory and configuration against that baseline. Generated collection catalog
registrations are removed. Other Omnigent agents and sessions remain.
AAP job and AO execution history is retained.
Reset uses the AAP configuration command rather than full bootstrap, so it
does not recreate nginx or the webapp. Use `make bootstrap` for the complete
environment, or the individual webapp commands to recreate only that flow.
Use `make demo-hydrate` and `make demo ISSUE=N` afterward. See the
[Forgejo demo guide](cluster/forgejo/README.md) for the fixture details.

The [Omnigent component guide](cluster/omnigent/README.md) describes the
permissions, image, and session lifecycle. The [AO workflow guide](cluster/automation-orchestrator/workflows/README.md)
describes workflow reconciliation.
The [Developer Hub guide](cluster/rhdh/README.md) describes the templates
and their relationship to the AO workflow.
The [AAP guide](cluster/ansible-automation-platform/README.md) covers the
single replica controller and EDA deployment. The seeded
[AAP config-as-code guide](cluster/forgejo/fixtures/demojam-ansible/README.md)
covers configuration and VM lifecycle automation. The [monitoring guide](cluster/user-workload-monitoring/README.md)
covers blackbox probes and the webapp outage flow: user Alertmanager → EDA →
AAP → a Forgejo collection issue.
