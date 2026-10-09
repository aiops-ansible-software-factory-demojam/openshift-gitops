# Demo OpenShift GitOps

Set up a disposable OpenShift cluster for an Ansible software factory demo.
The main flow takes a Forgejo issue through Automation Orchestrator (AO),
Red Hat Developer Hub (Backstage), and an Omnigent agent to a pull request.
The cluster also runs Ansible Automation Platform (AAP), a RHEL 9 nginx VM,
and monitoring.

A SELinux outage follows the complete automatic path: blackbox alert → EDA →
AO audit-log RCA → Forgejo incident → Forgejo webhook → EDA → AO → Omnigent
fix PR. Bootstrap installs and connects every stage; PR review and merge remain
manual. LiteLLM's `qwen38-27b` is the default model in the configuration template.
Bootstrap disables thinking for this model in the coding harness because the
demo endpoint can otherwise time out before returning a streamed tool call.

## Before you start

You need cluster-admin access, Operator Lifecycle Manager (OLM) with Red Hat and
certified operator catalogs, trusted HTTPS ingress, a default StorageClass for
ReadWriteOnce (RWO) volumes, and enough CPU, memory, and disk for the stack.
At least one node must expose hardware virtualization (KVM) for the VMs.
Bootstrap waits for Virtualization and the required OS DataSources.

Install Bash, GNU Make, `oc`, `kustomize`, `helm`, `jq`, jq-wrapper `yq`,
`openssl`, `curl`, `git`, `unzip`, `ssh-keygen`, and standard GNU utilities.
`yq '.'` must emit JSON that `jq` can read.

## Set up the cluster

From a fresh checkout:

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

In `.env`, use the [configuration template](.env.example) to select
`MODEL_PROVIDER` (`opencode-go` or `litellm`) and fill in its key, endpoint,
and model. Endpoints are HTTPS API base URLs,
before `/responses` or `/chat/completions`. Place your AAP subscription ZIP,
including RHEL CDN entitlement, at `aap_manifest.zip`, or set `AAP_LICENSE_FILE`.
The ZIP and `.env` are ignored by Git; quote values as trusted Bash configuration.

Argo CD reads published Git commits. Publish changes before setup and set
`BOOTSTRAP_BRANCH` if using a branch other than `main`. Source branches for the
three Ansible repos are configured separately; see [Forgejo](cluster/forgejo/README.md).

Bootstrap installs the stack, seeds Forgejo, builds the agent image, configures
AAP, provisions nginx, and checks HTTPS and monitoring. Wait for
`Bootstrap completed`, then open the printed Homepage URL. Sign in as
`demo-user` with `DEMO_USER_PASSWORD` (default `changeme` for new accounts).
This demo account has application administrator and OpenShift cluster-admin
access. Keep your populated `.env` for reruns.

## Run the demo

Run these commands from the repository root:

```bash
bash bootstrap/bootstrap.sh aap launch webapp_selinux_enable
```

The seeded job enables SELinux enforcing on the webapp VM. Follow the new
Forgejo incident and its RCA into the Omnigent session; the agent tests its
collection fix and submits a PR. Restore the permissive demo baseline with
`make webapp-nginx` after the demonstration. The fix PR stays open for review.

The starter issue exercises the Backstage feature flow directly:

```bash
make demo-hydrate     # Print the starter issue URL and number
make demo ISSUE=N     # Replace N with that positive issue number
make webapp-verify    # Check the RHEL webapp
```

AO waits for Backstage to create the issue branch, then starts the agent.
The command prints execution and session IDs; successful handoff precedes
the PR. Open the [Omnigent session](cluster/omnigent/README.md) for checks and
the PR URL.

`make demo-reset` deletes demo repositories, agent sessions, VMs, and disks,
then reseeds the baseline. It leaves demo VMs absent; rerun `make bootstrap`
to restore the full environment. `make teardown` removes the entire demo stack,
operators, identities, and persistent data. Both discard disposable demo work.
Use `make teardown-keep-aap` to retain AAP, its operator and database volumes
while removing the rest. It stops the demo EDA listeners until the next bootstrap.
Bootstrap reconciles Homepage's new reader password with the preserved AAP
account before verifying the dashboard.
After deploying a merged fix, enable SELinux with
`bash bootstrap/bootstrap.sh aap launch webapp_selinux_enable`, then run
`bash bootstrap/bootstrap.sh webapp verify-enforcing` to check Enforcing and HTTP.
For `qwen38-27b`, bootstrap also configures an authenticated LiteLLM bridge for
AO's RCA requests with thinking disabled, matching the Omnigent configuration.
Setup and reset silence only `WebappDown` while the baseline is unavailable.
Bootstrap waits for monitoring to observe recovery before ending maintenance.
Recovery notifications and a 30-second group interval allow repeat demo runs;
EDA dispatches only firing alerts, and repeats reuse the open incident.
Before script launches, bootstrap waits for node storage readiness and refreshes
the AAP project and inventories sequentially. Ensuing EDA/AO jobs reuse a
ten-minute dependency cache; script launches always refresh it, including after
creating a VM, so inventory still discovers the new guest.
Setup, reset, and teardown share the implementation in
`bootstrap/bootstrap.sh`; Make targets invoke that script directly.

## Find your next step

`make help-all` lists maintenance commands; `make preflight` checks prerequisites
without changing the cluster, and `make render` renders manifests locally.

- [Login and users](cluster/demojam-keycloak/README.md) · [Homepage](cluster/homepage/README.md)
- [Forgejo](cluster/forgejo/README.md) · [Developer Hub](cluster/rhdh/README.md) · [Agent sessions and tests](cluster/omnigent/README.md)
- [AO](cluster/automation-orchestrator/README.md) · [Workflows](cluster/automation-orchestrator/workflows/README.md)
- [AAP and the webapp](cluster/ansible-automation-platform/README.md) · [Virtualization](cluster/openshift-virtualization/README.md) · [Monitoring](cluster/user-workload-monitoring/README.md)
