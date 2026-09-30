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

## Requirements

Use a disposable OpenShift cluster with OLM, Red Hat and certified operator
catalogs, ingress, a default RWO StorageClass, and enough capacity for the
operators, databases, and applications. OpenShift Virtualization requires
hardware KVM support on at least one node; bootstrap waits for its
`HyperConverged` resource to become available. The active `KUBECONFIG`
identity needs cluster-admin rights. Install `oc`, `kustomize`, `helm`, `yq`,
`jq`, `openssl`, `curl`, `git`, `python3`, `ssh-keygen`.

Argo CD reads this repository from its Git remote. Publish your changes before
bootstrap. `BOOTSTRAP_BRANCH` selects an already published branch; it defaults
to `main`. Bootstrap sets a cluster-local Argo Kustomize patch for child
Applications so the checked-in defaults can remain on `main`.

## Local secrets

From the repo root, copy the template on a fresh checkout and populate it:

```bash
cp .env.example .env
chmod 600 .env
```

All bootstrap and demo entry points load the root `.env`. Quote values as in
the template. Set `KUBECONFIG` to your cluster config path (default
`$HOME/.kube/config`), and optionally set `EXPECTED_SERVER` to its API URL.
Place the subscription ZIP at root `aap_manifest.zip`; it must include AAP
licensing and a RHEL CDN entitlement for the guest. Both files are gitignored.

| Input | Purpose |
| --- | --- |
| `MODEL_PROVIDER=opencode-go` | Uses `OPENCODE_GO_API_KEY`, `OPENCODE_GO_ENDPOINT`, `OPENCODE_GO_MODEL` (default `gpt-6-luna`) |
| `MODEL_PROVIDER=litellm` | Uses `LITELLM_API_KEY`, `LITELLM_ENDPOINT`, `LITELLM_MODEL` |
| `RH_AUTOMATIONHUB_TOKEN` | Certified collection downloads during the EE build |
| `AAP_LICENSE_FILE` | Optional override for the root subscription ZIP |

Provider endpoints are HTTPS API base URLs, ending before `/responses` or
`/chat/completions`. To switch providers, edit `.env`, then run:

```bash
bash bootstrap/model-config.sh
```

New sessions use that configuration. Existing sessions keep their launch
credentials; use `make demo-reset` when a clean issue-to-PR cycle is needed.
Bootstrap handles generated secrets: database passwords, Forgejo/Backstage
tokens, AAP admin credentials, a namespace-scoped VM API token, and a VM SSH
key. It reuses runtime VM identities across reruns. The RHEL entitlement is
extracted from the manifest into an AAP credential. No local registry login,
Forgejo read token, or manually copied generated AAP password is required.

## Bootstrap

From the repository root:

```bash
oc whoami --show-server
oc whoami
bash bootstrap/bootstrap.sh
```

The script installs GitOps, creates the model and internal Secrets, rolls out
all applications, hydrates Forgejo, builds the sandbox image, verifies golden
paths, and publishes AO's issue workflow. After reconciliation it builds the
AAP EE, creates runtime AAP credentials by script, imports the license, and
runs dispatch in a Job that clones the public Forgejo config repository.
It waits for project/inventory synchronization. Rerunning preserves the VM
SSH identity and applies current config. `BOOTSTRAP_FORCE_SANDBOX_BUILD=true`
forces a sandbox image rebuild.

On SNO, scripts wait for the API server to finish reconciling before AAP work.
EE builds tolerate interrupted log streams and status reads. AAP status checks
retry brief network interruptions; launch requests are sent once. Inspect AAP
before repeating a launch whose response was lost.

## Provision and automate the RHEL webapp

Log into the AAP gateway Route as `admin`, using the operator-generated
`aap-admin-password` Secret in `ansible-automation-platform`. Launch these
templates in order:

1. **webapp_vm** clones the `rhel9` DataSource into `webapp-vms`, installs the
   bootstrap-generated public SSH key via cloud-init, and waits for VM Ready.
2. **webapp_nginx** refreshes VM inventory, connects with the matching SSH key,
   enables RHEL repositories using the manifest entitlement, and runs
   `demo.greetings.nginx` from the public example collection's Git repository.

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
**aap_configure_all** template or `make aap-sync`. To rebuild/bootstrap only
AAP, use `make aap-ee` then `make aap-configure`. The seeded `demojam-ansible` repository owns its
[execution-environment.yml](cluster/forgejo/fixtures/demojam-ansible/execution-environment.yml). It is converted to a build
context by the Tekton ansible-builder task; Buildah builds it and pushes
to its internal registry. The Automation Hub token is a build-only mounted
Secret, deleted after the build, and never copied into the image.

See the [AAP config guide](cluster/forgejo/fixtures/demojam-ansible/README.md)
for the script/dispatch boundary and reset behavior.

## Run an issue through AO

```bash
oc -n openshift-gitops get applications
oc -n agent-sandbox-system get csv
oc -n openshift-cnv get hyperconverged,kubevirt
oc -n omnigent rollout status deployment/omnigent
oc -n omnigent-sandboxes get pipelineruns,imagestream,sandboxes,pods
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
selected `.env` model and agent Secrets, wipes the disposable Forgejo PVC, and
reseeds the one-line README issue, Backstage collection template source, and
the `demo-owner/demojam-ansible` repository.
It removes catalog registrations for generated collections that the Forgejo
wipe deletes. Other Omnigent agents and sessions remain.
Run `bash scripts/dispatch-issue.sh 1` afterward. See the
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
covers the blackbox probe and user Alertmanager. No alert receiver is set yet.
