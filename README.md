# Demo OpenShift GitOps

This repository bootstraps a disposable OpenShift enablement cluster with
OpenShift GitOps, the Agent Sandbox operator, Omnigent, and Automation
Orchestrator (AO). Omnigent uses the Kubernetes Agent Sandbox API directly:

```text
AO workflow -> Omnigent API -> Sandbox in omnigent-sandboxes
                             -> OpenCode with OpenCode Go glm-5.3-flash
```

Forgejo and Developer Hub manifests remain available for the later collection
feature demo. The Developer Hub Application is disabled in `cluster/values.yaml`
until that stage. This stage proves that AO can create and task an OpenCode session.
It does not seed a collection repository or run the feature pipeline.

## Requirements

Use a disposable OpenShift cluster with OLM, Red Hat and certified operator
catalogs, ingress, a default RWO StorageClass, and enough capacity for the
operators, databases, and applications. The identity in `~/.kube/config` needs
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
KUBECONFIG="$HOME/.kube/config" oc whoami --show-server
KUBECONFIG="$HOME/.kube/config" oc whoami
BOOTSTRAP_BRANCH=demo-yourname KUBECONFIG="$HOME/.kube/config" bash bootstrap/bootstrap.sh
```

The script installs OpenShift GitOps, creates the bootstrap-owned model and
machine-credential Secrets, starts the app-of-apps, waits for the OpenCode
image and Omnigent deployment, and publishes AO's `omnigent-dispatch` workflow.
It is safe to rerun. It skips Forgejo data seeding and Backstage template
verification by default. The Developer Hub app, seed credentials, and catalog
checks are deferred to the later feature stage.

The default model is OpenCode Go `glm-5.3-flash` at
`https://opencode.ai/zen/go/v1`. Bootstrap reads
`op://lab_agents/opencode-go-subscription-key/password` when `op` is available,
or prompts for the key. For noninteractive use, set `MODEL_API_KEY` in the
environment. The key is stored in a Kubernetes Secret in
`omnigent-sandboxes`, never in Git. Repeat runs reuse the existing Secret.
Set `MODEL_API_KEY` again to rotate it. `MODEL_BASE_URL` and `MODEL_NAME` can
select another OpenAI-compatible endpoint; the base URL ends before
`/chat/completions`.

## Verify the session path

```bash
KUBECONFIG="$HOME/.kube/config" oc -n openshift-gitops get applications
KUBECONFIG="$HOME/.kube/config" oc -n agent-sandbox-system get csv
KUBECONFIG="$HOME/.kube/config" oc -n omnigent rollout status deployment/omnigent
KUBECONFIG="$HOME/.kube/config" oc -n omnigent-sandboxes get builds,imagestream,sandboxes,pods
```

In AO, run `omnigent-dispatch` with a small task such as “Reply with the
OpenCode model name and the installed Ansible version.” Its HTTP Request nodes
call Omnigent's internal Service to create a managed session and send the
message once the runner is ready. A new `Sandbox` and Pod should appear in
`omnigent-sandboxes`. Inspect the conversation in Omnigent using the Route
credential created by bootstrap. Delete the test session when finished to
remove its Sandbox and workspace claim.

The [Omnigent component guide](cluster/omnigent/README.md) describes the
permissions, image, and session lifecycle. The [AO workflow guide](cluster/automation-orchestrator/workflows/README.md)
describes workflow reconciliation.
