# Demo OpenShift GitOps

This repository bootstraps a disposable OpenShift enablement cluster with
OpenShift GitOps, the Agent Sandbox operator, Omnigent, and Automation
Orchestrator (AO). Omnigent uses the Kubernetes Agent Sandbox API directly:

```text
AO workflow -> Omnigent API -> Sandbox in omnigent-sandboxes
                             -> OpenCode with OpenCode Go glm-5.3-flash
```

Forgejo supplies the seeded collection and issue for an issue-to-PR demo.
Developer Hub remains disabled in `cluster/values.yaml`; this flow uses no
golden path or Backstage template.

## Requirements

Use a disposable OpenShift cluster with OLM, Red Hat and certified operator
catalogs, ingress, a default RWO StorageClass, and enough capacity for the
operators, databases, and applications. The active `KUBECONFIG` identity needs
cluster-admin rights. Install `oc`, `kustomize`, `helm`, `yq`, `jq`, `openssl`,
`curl`, `git`, and `op` (or supply `MODEL_API_KEY`).

Argo CD reads this repository from its Git remote. Bootstrap publishes the
checkout to a chosen branch, then points the root and child Applications to
that branch. Use one branch per demo cluster. The checkout must be clean and
published before running bootstrap.

## Bootstrap

From the repository root:

```bash
make test
oc whoami --show-server
oc whoami
BOOTSTRAP_BRANCH=demo-yourname bash bootstrap/bootstrap.sh
```

The script installs OpenShift GitOps, creates the bootstrap-owned model and
machine-credential Secrets, starts the app-of-apps, waits for the OpenCode
image and Omnigent deployment, hydrates Forgejo's collection and issue, and
publishes AO's `omnigent-dispatch` workflow. It is safe to rerun. Set
`BOOTSTRAP_SEED_DEMO=false` only when testing the platform without Forgejo
data. Developer Hub stays disabled.

The default model is OpenCode Go `glm-5.3-flash` at
`https://opencode.ai/zen/go/v1`. Bootstrap reads
`op://lab_agents/opencode-go-subscription-key/password` when `op` is available,
or prompts for the key. For noninteractive use, set `MODEL_API_KEY` in the
environment. The key is stored in a Kubernetes Secret in
`omnigent-sandboxes`, never in Git. Repeat runs reuse the existing Secret.
Set `MODEL_API_KEY` again to rotate it. `MODEL_BASE_URL` and `MODEL_NAME` can
select another OpenAI-compatible endpoint; the base URL ends before
`/chat/completions`.

## Run an issue through AO

```bash
oc -n openshift-gitops get applications
oc -n agent-sandbox-system get csv
oc -n omnigent rollout status deployment/omnigent
oc -n omnigent-sandboxes get builds,imagestream,sandboxes,pods
bash scripts/feature-demo.sh hydrate
bash scripts/dispatch-issue.sh 1
```

`hydrate` is idempotent and prints the issue URL. Pass its issue number to
`dispatch-issue.sh`; the script calls AO's published workflow through its API
and prints the AO execution and Omnigent session IDs. AO completion means the
agent accepted the task. Inspect the session for its branch, checks, and PR URL.
Each session gets its own Sandbox. Delete the session when finished.

To return Forgejo to the fixture baseline and rotate the agent token, stop the
session and run:

```bash
bash scripts/feature-demo.sh reset --confirm-forgejo-demo
```

This erases only the disposable Forgejo PVC and re-creates the collection,
issue, and sandbox credential. See the [Forgejo demo guide](cluster/forgejo-demo/README.md)
for the reset guardrails and fixture details.

The [Omnigent component guide](cluster/omnigent/README.md) describes the
permissions, image, and session lifecycle. The [AO workflow guide](cluster/automation-orchestrator/workflows/README.md)
describes workflow reconciliation.
