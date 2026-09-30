# Demo OpenShift GitOps

This repository bootstraps a disposable OpenShift enablement cluster with
OpenShift GitOps, OpenShift Virtualization, the Agent Sandbox operator,
Omnigent, Automation Orchestrator (AO), Ansible Automation Platform, and user
workload monitoring. Omnigent uses the Kubernetes
Agent Sandbox API directly:

```text
AO workflow -> Backstage feature template -> Forgejo feature branch
            -> Omnigent API -> Sandbox in omnigent-sandboxes
                            -> OpenCode with OpenCode Go gpt-6-luna
```

Forgejo supplies the seeded collection and issue for an issue-to-PR demo.
Red Hat Developer Hub (Backstage) provides the mandatory issue branch golden
path. AO waits for its Scaffolder task and verifies the branch before it
launches the agent. The agent implements the change, pushes, and opens the PR.

## Requirements

Use a disposable OpenShift cluster with OLM, Red Hat and certified operator
catalogs, ingress, a default RWO StorageClass, and enough capacity for the
operators, databases, and applications. OpenShift Virtualization requires
hardware KVM support on at least one node; bootstrap waits for its
`HyperConverged` resource to become available. The active `KUBECONFIG`
identity needs cluster-admin rights. Install `oc`, `kustomize`, `helm`, `yq`,
`jq`, `openssl`, `curl`, `git`, and `op` (or supply `MODEL_API_KEY`).

Argo CD reads this repository from its Git remote. Bootstrap publishes the
checkout to a chosen branch, then points the root and child Applications to
that branch. Use one branch per demo cluster. The checkout must be clean and
published before running bootstrap.

## Local secrets

Populate the repository-root `.env` with your local inputs. The checked-in
[.env.example](.env.example) is the blank template for a fresh checkout:

```bash
cp .env.example .env  # Fresh checkout only; keep an existing populated .env.
chmod 600 .env
```

The `.env` file, root `aap_manifest.zip`, and `.secrets/` directory are gitignored. Quote values as
shown in the template; certificate contents can use multiline single quotes.
The scripts read exported variables, so load the file from the repo root
before bootstrap, reset, or Forgejo API commands. The AAP shortcuts load
`.env` themselves:

```bash
set -a
source .env
set +a
```

`KUBECONFIG` defaults to `$HOME/.kube/config`. For bootstrap/reset, fill
`MODEL_API_KEY`. For AAP config, fill `AAP_PASSWORD` and `FORGEJO_TOKEN` with
the demo-agent token. URLs, the internal EE image and VM API inputs have
defaults described in the
[AAP fixture guide](cluster/forgejo-demo/fixtures/aap-config-as-code/README.md).
Admin-only Forgejo API operations need the admin token
instead. Bootstrap and operators still generate internal database and
application credentials; hydration still manages Forgejo/Backstage tokens.

Place your subscription manifest at `aap_manifest.zip` in the repo root:

```bash
make aap-ee
make aap-configure
```

GitOps supplies the EE BuildConfig and ImageStream. Builds run in OpenShift
using existing cluster registry credentials. The configuration shortcut runs
the built EE in an explicit Job, imports the manifest through config-as-code,
then configures AAP and waits for inventory syncs. `AAP_LICENSE_FILE` overrides
the default root ZIP path. No local build or registry password is needed.
GitOps also creates `aap-vm-admin`; its token serves both VM inventory
discovery and deployment in `automation-vms`.

## Bootstrap

From the repository root:

```bash
oc whoami --show-server
oc whoami
BOOTSTRAP_BRANCH=demo-yourname bash bootstrap/bootstrap.sh
```

The script installs OpenShift GitOps, creates the bootstrap-owned model,
database, and machine-credential Secrets, starts the app-of-apps, hydrates
Forgejo before Developer Hub starts, waits for the OpenCode image and
Omnigent deployment, verifies the Backstage catalog, and publishes AO's
`omnigent-dispatch` workflow. It is safe to rerun. Set
`BOOTSTRAP_FORCE_SANDBOX_BUILD=true` to rebuild the image even when its source
has not changed.

The default model is OpenCode Go `gpt-6-luna` at
`https://opencode.ai/zen/go/v1`. Bootstrap reads
`op://lab_agents/opencode-go-subscription-key/password` when `op` is available,
or prompts for the key. For noninteractive use, set `MODEL_API_KEY` in the
environment. The key is stored in a Kubernetes Secret in
`omnigent-sandboxes`, never in Git. Repeat runs reuse the existing Secret.
Set `MODEL_API_KEY` again to rotate it. `MODEL_BASE_URL` and `MODEL_NAME` can
select another OpenAI-compatible endpoint; the base URL ends before its API
operation. The Go default uses the Responses API through `@ai-sdk/openai`.

## Run an issue through AO

```bash
oc -n openshift-gitops get applications
oc -n agent-sandbox-system get csv
oc -n openshift-cnv get hyperconverged,kubevirt
oc -n omnigent rollout status deployment/omnigent
oc -n omnigent-sandboxes get builds,imagestream,sandboxes,pods
bash scripts/feature-demo.sh hydrate
bash scripts/dispatch-issue.sh 1
```

The [OpenShift Virtualization guide](cluster/openshift-virtualization/README.md)
includes a temporary CirrOS VM and a KVM acceleration check.

`hydrate` is idempotent and prints the issue URL. Pass its issue number to
`dispatch-issue.sh`; the script calls AO's published workflow through its API
and prints the AO execution and Omnigent session IDs. AO completion means the
branch exists and the agent accepted the task. Inspect the session for its
checks and PR URL.
Each session gets its own Sandbox. Delete the session when finished.

To reset the full issue-to-PR demo, run:

```bash
make demo-reset
```

This removes `automation-developer` sessions and Sandboxes, recreates its
OpenCode Go model and agent Secrets, wipes the disposable Forgejo PVC, and
reseeds the one-line README issue, Backstage collection template source, and
the `demo-owner/aap-config-as-code` repository.
It removes catalog registrations for generated collections that the Forgejo
wipe deletes. Other Omnigent agents and sessions remain.
Run `bash scripts/dispatch-issue.sh 1` afterward. See the
[Forgejo demo guide](cluster/forgejo-demo/README.md) for the fixture details.

The [Omnigent component guide](cluster/omnigent/README.md) describes the
permissions, image, and session lifecycle. The [AO workflow guide](cluster/automation-orchestrator/workflows/README.md)
describes workflow reconciliation.
The [Developer Hub guide](cluster/rhdh/README.md) describes the templates
and their relationship to the AO workflow.
The [AAP guide](cluster/ansible-automation-platform/README.md) covers the
single replica controller and EDA deployment. The seeded
[AAP config-as-code guide](cluster/forgejo-demo/fixtures/aap-config-as-code/README.md)
covers configuration and VM lifecycle automation. The [monitoring guide](cluster/user-workload-monitoring/README.md)
covers the blackbox probe and user Alertmanager. No alert receiver is set yet.
