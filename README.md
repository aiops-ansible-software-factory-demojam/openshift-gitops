# Demo OpenShift GitOps

For the AAP and AO invoice-processing security demo using a Lightwell PyPDF2
backport and RHEL EC2 guests, see the detailed
[invoice setup and recording walkthrough](docs/invoice-lightwell-demo.md).
Select `DEMO_SCENARIO=invoice` and `DEMO_BACKEND=aws`; the existing SELinux
scenario remains the default.

Set up a disposable OpenShift cluster for an Ansible software factory demo.
The main flow takes a Forgejo issue through Automation Orchestrator (AO),
Red Hat Developer Hub (Backstage), and an Omnigent agent to a pull request.
The cluster also runs Ansible Automation Platform (AAP), a RHEL 9 nginx VM,
and monitoring.

A SELinux outage follows the complete automatic path: blackbox alert → EDA →
AO audit/MCP RCA → Forgejo incident → Forgejo webhook → EDA → AO → Omnigent
fix PR. Bootstrap installs and connects every stage; PR review and merge remain
manual. LiteLLM's `qwen38-27b` is the default model in the configuration template.
Bootstrap disables thinking by default for Qwen consumers because the demo
endpoint can otherwise time out before returning a tool response.

## RHEL MCP diagnostics for AO RCA

Bootstrap installs the stock Linux MCP 1.7.0 executable on the webapp guest
after nginx, then publishes an RCA agent with nine native diagnostic tools.
Its first `read_log_file` call reads 20 lines from `/var/log/audit/audit.log`.
The non-root account has audit-log read access through auditd's `log_group`
configuration, which preserves access after rotation. It has no sudo,
capabilities, script execution or audit-log write access. No custom server,
collector, timer, audit snapshot or SELinux tool is deployed.

The native policy allows the selected tools on localhost; native journal and
service scope applies. The prompt requests at most 20 lines, rather than
custom middleware enforcing that limit. Raw audit entries can include other
host events, and absence of nginx denials in the current tail is inconclusive.

The primary RCA receives no AAP stdout or audit artifact in its starting prompt.
It queries audit facts and nginx/service/resource diagnostics as needed. A
condition requires both completed RCA and available MCP audit evidence before
publishing the diagnosis. Otherwise the workflow runs AAP's `pull_audit_logs`
and then a text-only fallback using its compact facts. Disabled mode uses AAP
from the start. Exactly one completed diagnosis reaches the issue job.

Tool traces stay in AO. There are no workflow script nodes, and worker script
execution remains disabled. Both prompts fit the shipped invocation API's hard
10,000-character limit; the separate configurable workflow limit defaults to
100,000 and cannot bypass that lower validation limit. MCP applies no fixes;
the incident-to-PR, human review and AAP recovery flow remain in place.

`WEBAPP_MCP_ENABLED` defaults to true for CNV and false for AWS. Set it to
true to opt an AWS deployment into MCP diagnostics.
Set it to false and run `make webapp-mcp` to restore audit-only RCA before
stopping the daemon and removing its guest authentication/TLS material.

```bash
make webapp-mcp         # Configure AAP, apply guest setup and reconcile AO
make webapp-mcp-verify  # Validate an authenticated TLS MCP session and tool selection
make webapp-mcp-rotate  # Rotate the machine credential through AAP and AO
```

The internal endpoint is `https://webapp-mcp.webapp-vms.svc:8443/mcp`, without
a public Route. Guest ingress restricts 8443 to AO backend/worker/background
worker pods while retaining HTTP/SSH. The AO operator permits outbound
integration traffic for those components; verify actual pod labels and CNV
policy enforcement during the live acceptance run. The integration hostname
is added to the integration allowlist without changing workflow HTTP-node rules.

AO 2026.8's shipped adapter supports an `HTTP Bearer Token` credential, without
OAuth token renewal. Bootstrap configures a dedicated `demojam-ao-rca` Keycloak
service client with no administrative roles or interactive login and issues a
90-day client-credentials JWT. The stock server's JWT verifier checks issuer,
audience, signature and expiry using Keycloak's HTTPS signing-key endpoint.
The native tool policy also matches the current `jti`; rotating the credential
changes the policy so the previous JWT loses tool access even before expiry.

Bootstrap preserves the source Secret, client secret and TLS CA across reruns
and reset, renews tokens within one day of expiry and TLS leaf certificates
within seven days. The guest receives public JWT metadata/trust and leaf TLS
material; the bearer token, client secret and CA signing key stay outside it.
Its trust bundle combines the system roots with the cluster ingress CA, and
it must reach the public Keycloak Route to fetch signing keys. AO binds its
credential separately for health/discovery and workflow execution. Run
`make webapp-mcp-rotate` to force renewal; AO cannot renew tokens itself.

Bootstrap first publishes audit-only RCA before the VM exists; it enables MCP
only after the guest service and authenticated discovery pass, before resuming
alerting. `webapp-mcp-ready` records that installation milestone. Reset clears
the marker, and explicit VM deletion restores audit-only RCA first. Select the
matching published `demojam-ansible` implementation branch when testing these
changes, using `DEMOJAM_ANSIBLE_BRANCH` and `BOOTSTRAP_BRANCH`.
For an existing demo, refresh only the seeded `demojam-ansible` repository and
force its AAP project sync before publishing a workflow that consumes new
artifacts. The seeding helper accepts an optional repository name and preserves
the other repositories and account passwords during that selective refresh.
Refreshing every baseline would overwrite a previously merged collection fix.

For AWS, bootstrap removes the Service selector and publishes an EndpointSlice
using the EC2 webapp's current public address. The same Service hostname and TLS
certificate remain valid. It discovers public IPv4 egress from the running AO
caller pods using `https://checkip.amazonaws.com`, then opens the owned EC2
security group's TCP 8443 only to those `/32` addresses. Rerunning setup removes
stale owned rules; disable/reset removes the endpoint and closes the port.
Reconcile MCP after cluster egress changes. The AWS firewall identifies cluster
egress, so other workloads sharing that address can reach the listener; the
MCP bearer credential and tool policy enforce AO's identity. CNV's pod-level
ingress policy does not apply to external EC2 endpoints.

Local checks include `bash tests/git-source-refs.sh`,
`bash tests/webapp-mcp-bootstrap.sh`,
`python tests/mcp-aws-network.py`, Kustomize rendering,
the companion repository's HTTPS/credential tests, and the shipped AO adapter
and workflow models. The complete CNV outage-to-PR/recovery run, guest reboot
and namespace isolation checks require the installed demo; do not substitute
local schema or adapter success for those live acceptance checks. RHEL MCP
remains Developer Preview.

## Before you start

You need cluster-admin access, Operator Lifecycle Manager (OLM) with Red Hat and
certified operator catalogs, trusted HTTPS ingress, a default StorageClass for
ReadWriteOnce (RWO) volumes, and enough CPU, memory, and disk for the stack.
For CNV guests, at least one node must expose hardware virtualization (KVM).
For AWS guests, block storage is sufficient; bootstrap omits Virtualization.

Install Bash, GNU Make, `oc`, `kustomize`, `helm`, `jq`, jq-wrapper `yq`,
`openssl`, `curl`, `git`, `unzip`, `ssh-keygen`, and standard GNU utilities.
`yq '.'` must emit JSON that `jq` can read.
AWS bootstrap also needs Python 3 with `venv` support. It installs its pinned
SDK in an isolated directory under `.rendered/`.

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

The environment examples put required inputs first and optional overrides
below. Fill the subscription and selected model provider, plus the AWS and
Lightwell sections when those scenarios apply. For the AWS invoice demo, use
[.env.invoice.example](.env.invoice.example) and the
[invoice runbook](docs/invoice-lightwell-demo.md).

For the released AWS/native MCP demo with Qwen on both consumers, follow the
[v0.1.0-alpha.2 reproduction instructions](docs/releases/v0.1.0-alpha.2.md).
The focused [demo environment example](.env.demo.example) selects that tag in
all four repositories. The [command record](docs/native-mcp-demo-2026-10-16.md)
preserves the original live run and its tested revisions.

To put the Linux guests in AWS, fill `AWS_BOOTSTRAP_ACCESS_KEY_ID` and
`AWS_BOOTSTRAP_SECRET_ACCESS_KEY` in `.env`, then run `make bootstrap BACKEND=aws`.
Bootstrap uses those credentials locally to create a dedicated public VPC/subnet
and separate scoped AAP and Molecule keys. It mounts only the Molecule key into
the coding sandbox. Defaults are `us-east-2`, `t3.medium`, and encrypted 30 GiB
gp3 disks. Account, availability zone and RHEL image choices are discovered and
saved; normal resets reuse them. The monitored guest uses RHEL 9, while
`make molecule` tests RHEL 9 and RHEL 10. AWS guests use their AMI's RHUI repositories.

Use `BACKEND=cnv` for the existing guest behavior. The recorded backend prevents
an accidental switch on a live installation. See the
[backend specification](docs/specs/aws-cnv-backends.md) for credential scopes,
overrides and resource ownership.

In `.env`, use the [configuration template](.env.example) to select
the provider (`opencode-go`, `litellm`, or `openshift-ai`) and fill in its key, endpoint,
and model. `MODEL_PROVIDER` and the provider-specific fields remain shared
defaults. AO and Omnigent can select providers and models independently:

```bash
AO_MODEL_PROVIDER='litellm'
AO_MODEL='qwen38-27b'
AO_QWEN_REASONING_EFFORT='none'
OMNIGENT_MODEL_PROVIDER='opencode-go'
OMNIGENT_MODEL='claude-haiku-5-5'
OMNIGENT_MODEL_PROTOCOL='anthropic'
```

This uses `LITELLM_ENDPOINT`/`LITELLM_API_KEY` for AO and
`OPENCODE_GO_ENDPOINT`/`OPENCODE_GO_API_KEY` for Omnigent. Optional
`AO_MODEL_ENDPOINT`, `AO_MODEL_API_KEY`, `OMNIGENT_MODEL_ENDPOINT` and
`OMNIGENT_MODEL_API_KEY` override those defaults for separate accounts.
`AO_MODEL_PROTOCOL` and `OMNIGENT_MODEL_PROTOCOL` select each consumer's transport.
Empty overrides inherit the defaults for that consumer's selected provider.
`make model-config` applies both selections; existing coding sessions retain
their startup configuration, so use a new session to test a model change.

Endpoints are HTTPS API base URLs,
before `/responses`, `/chat/completions`, or `/messages`. Place your AAP subscription ZIP,
including RHEL CDN entitlement, at `aap_manifest.zip`, or set `AAP_LICENSE_FILE`.
The ZIP and `.env` are ignored by Git; quote values as trusted Bash configuration.

Argo CD reads published Git commits. Publish changes before setup and set
`BOOTSTRAP_BRANCH` to the published branch or release tag. Source refs for the
three Ansible repos are configured separately; see [Forgejo](cluster/forgejo/README.md).

Bootstrap installs the stack, seeds Forgejo, builds the agent image, configures
AAP, provisions the RHEL VM, runs the separate permissive setup playbook,
installs nginx, and checks HTTPS and monitoring. Wait for
`Bootstrap completed`, then open the printed Homepage URL. Sign in as
`demo-user` with `DEMO_USER_PASSWORD` (default `changeme` for new accounts).
This demo account has application administrator and OpenShift cluster-admin
access. Keep your populated `.env` for reruns.

## Run the demo

Agents can use the repository's
[run-demojam skill](.agents/skills/run-demojam/SKILL.md) to run the full demo
without coaching the coding agent or repairing the run. It merges the Forgejo
fix only after tests pass on the published commit.

Run these commands from the repository root:

```bash
bash bootstrap/bootstrap.sh aap launch webapp_selinux_enable
```

The seeded job enables SELinux enforcing on the webapp VM. Follow the new
Forgejo incident and its RCA into the Omnigent session; the agent tests its
collection fix and submits a PR. Merge the tested PR, then run
`make webapp-nginx` once to deploy it. This job preserves SELinux Enforcing;
run `bash bootstrap/bootstrap.sh webapp verify-enforcing` to check recovery.
To restore only the permissive mode for an unmerged demonstration, run
`bash bootstrap/bootstrap.sh aap launch webapp_selinux_permissive`.
A full reset and bootstrap also restore the unfixed collection.

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
The permissive setup job runs after VM provisioning during bootstrap.
It is separate from nginx installation, so deploying a merged fix preserves
the Enforcing state established by the fault job.
For `qwen38-27b`, bootstrap also configures an authenticated LiteLLM bridge for
AO's RCA requests. Set `AO_QWEN_REASONING_EFFORT` or
`OMNIGENT_QWEN_REASONING_EFFORT` to `medium`, `low`, or `xhigh` to enable
thinking for the corresponding Qwen consumer. Each falls back to
`QWEN_REASONING_EFFORT`; the default `none` keeps Qwen thinking disabled.
Use `AO_QWEN_REASONING_EFFORT='none'` for MCP RCA on the demo endpoint.
The `low` preset has produced upstream disconnects and exceeded the RCA node's
180-second limit. The non-thinking preset has completed the same audit-first
MCP investigation within that limit, without using the AAP audit fallback.
Bootstrap sets AO's per-attempt LLM timeout to 90 seconds in backend, worker,
and background worker. Override it with `AO_LLM_REQUEST_TIMEOUT_SECONDS` in `.env`.
Setup and reset silence only `WebappDown` while the baseline is unavailable.
Bootstrap waits for monitoring to observe recovery before ending maintenance.
Recovery notifications and a 30-second group interval allow repeat demo runs;
EDA dispatches only firing alerts, and repeats reuse the open incident.
Before script launches, bootstrap waits for node storage readiness and refreshes
the AAP project and inventories sequentially. Ensuing EDA/AO jobs reuse a
ten-minute dependency cache; script launches always refresh it, including after
creating a VM, so inventory still discovers the new guest.
The Enforcing check waits for its AAP result event to become visible after
command completion. A returned non-Enforcing state fails immediately; the
verification command is never re-executed while waiting for its event.
Setup, reset, and teardown share the implementation in
`bootstrap/bootstrap.sh`; Make targets invoke that script directly.
Bootstrap waits up to fifteen minutes for Keycloak's public OIDC discovery
endpoint, covering its ten-minute container startup probe window.

## Find your next step

The [AWS and CNV backend specification](docs/specs/aws-cnv-backends.md) describes
the AWS guest support and the existing CNV behavior.

`make help-all` lists maintenance commands; `make preflight` checks prerequisites
without changing the cluster, and `make render` renders manifests locally.

Use the
[run-demojam skill](.agents/skills/run-demojam/SKILL.md) for the operator sequence.

- [Login and users](cluster/demojam-keycloak/README.md) · [Homepage](cluster/homepage/README.md)
- [Forgejo](cluster/forgejo/README.md) · [Developer Hub](cluster/rhdh/README.md) · [Agent sessions and tests](cluster/omnigent/README.md)
- [AO](cluster/automation-orchestrator/README.md) · [Workflows](cluster/automation-orchestrator/workflows/README.md)
- [AAP and the webapp](cluster/ansible-automation-platform/README.md) · [Virtualization](cluster/openshift-virtualization/README.md) · [Monitoring](cluster/user-workload-monitoring/README.md)
