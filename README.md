# Demo OpenShift GitOps

This repository bootstraps a disposable OpenShift enablement cluster with
OpenShift GitOps, OpenShift Virtualization, the Agent Sandbox operator,
Omnigent, and Automation Orchestrator (AO). Omnigent uses the Kubernetes
Agent Sandbox API directly:

```text
AO workflow -> Omnigent API -> Sandbox in omnigent-sandboxes
                             -> OpenCode with OpenCode Go gpt-6-luna
```

Forgejo supplies the seeded collection and issue for an issue-to-PR demo.
Red Hat Developer Hub (Backstage) offers two optional Ansible collection
templates. AO's default issue workflow continues to use Forgejo directly.

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
agent accepted the task. Inspect the session for its branch, checks, and PR URL.
Each session gets its own Sandbox. Delete the session when finished.

To reset the full issue-to-PR demo, run:

```bash
make demo-reset
```

This removes `automation-developer` sessions and Sandboxes, recreates its
OpenCode Go model and agent Secrets, wipes the disposable Forgejo PVC, and
reseeds the one-line README issue and Backstage collection template source.
It removes catalog registrations for generated collections that the Forgejo
wipe deletes. Other Omnigent agents and sessions remain.
Run `bash scripts/dispatch-issue.sh 1` afterward. See the
[Forgejo demo guide](cluster/forgejo-demo/README.md) for the fixture details.

The [Omnigent component guide](cluster/omnigent/README.md) describes the
permissions, image, and session lifecycle. The [AO workflow guide](cluster/automation-orchestrator/workflows/README.md)
describes workflow reconciliation.
The [Developer Hub guide](cluster/rhdh/README.md) describes the optional
templates and their relationship to the AO workflow.
