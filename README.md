# Demo OpenShift GitOps

This repository installs a disposable OpenShift demo with one Forgejo instance,
OpenShell container sandboxes, Omnigent, and Automation Orchestrator. Argo CD
installs the applications from `cluster/values.yaml`. The only sandbox runtime is
the cluster's ordinary CRI-O container runtime; no Kata operator, RuntimeClass,
worker labels, or warm pool is used.

## Bootstrap

Use an OpenShift cluster with OLM, the Red Hat and certified operator catalogs,
working ingress, a default RWO StorageClass, and enough capacity for
Orchestrator, Developer Hub, Forgejo, Omnigent, and their databases. The account
in `~/.kube/config` needs cluster-admin rights. Install `oc`, `kustomize`, `helm`,
`yq`, `jq`, `openssl`, `curl`, and `git` locally. Argo CD reads the remote
repository in `cluster/values.yaml`; bootstrap can publish the checkout to a
branch you choose so concurrent demos do not fight over `main`.

Run:

```bash
bash bootstrap/bootstrap.sh
```

When prompted, accept `main` or enter a personal branch such as `demo-alice`.
Noninteractive runs can set the branch explicitly:

```bash
BOOTSTRAP_BRANCH=demo-alice bash bootstrap/bootstrap.sh
```

Bootstrap checks out or creates that branch, points Application
`targetRevision` values at it, commits when needed, and pushes
`origin/<branch>` before creating the root Argo CD Application. Use a distinct
branch per cluster when multiple people bootstrap from the same repository.

On the first run, bootstrap uses OpenCode Go at
`https://opencode.ai/zen/go/v1` with model `glm-5.3-flash`. It reads the
subscription key from the configured `lab_agents/opencode-go-subscription-key`
1Password item when available, and otherwise prompts for the key. LiteLLM MaaS
uses the same three parameters: base URL, model, and key.
For the MaaS example in `/workspace/scratch/litellm.txt`, run:

```bash
MODEL_BASE_URL=https://maas-rhdp.apps.maas.redhatworkshops.io/v1 \
  MODEL_NAME=gpt-oss-120b bash bootstrap/bootstrap.sh
```

For a noninteractive run, set `MODEL_API_KEY` in the environment. The key is
stored only in a Kubernetes Secret in `omnigent`, never in Git or a shell trace.
Subsequent runs reuse the existing Secret. Set `MODEL_API_KEY` again to replace
the key or change endpoints or models. Repeat `MODEL_BASE_URL` and `MODEL_NAME`
when the desired values differ from the OpenCode Go defaults. The base URL ends
at `/v1`, before `/chat/completions`. For another API host, add it to the
sandbox egress policy in `cluster/openshell/image/policy.yaml`.
OpenCode Go always uses `glm-5.3-flash`; repeat bootstrap runs update older Go
model configurations while keeping their existing API key.

Bootstrap reads the cluster's ingress domain. OpenShift assigns the requested
Route subdomains, and bootstrap supplies Forgejo's public URL through a
ConfigMap. It does not rewrite or commit cluster-specific hostnames. It installs
the OpenShift GitOps operator, creates the model, gateway, and Omnigent Route
credential Secrets, waits for the app-of-apps and OpenCode image build, then
publishes the `omnigent-dispatch` workflow in Automation Orchestrator and waits
for the Backstage templates to appear in the catalog. Publish
the checked-out revision to the chosen branch before running bootstrap. When
upgrading a demo that used explicit Route hosts, bootstrap recreates those
Routes after the new GitOps revision is read so OpenShift can assign hosts for
this cluster. A dirty checkout must be clean before bootstrap can switch
branches.

## Sandbox interface

Install the [OpenShell CLI](https://github.com/NVIDIA/OpenShell), then use the
wrapper to reach the cluster-internal gateway through your authenticated `oc`
session:

```bash
bash scripts/sandbox.sh create --name demo --detach
bash scripts/sandbox.sh exec -n demo -- opencode --version
bash scripts/sandbox.sh delete demo
```

The gateway has no public Route. The wrapper opens a short local port-forward for
each command. Omnigent reaches the same gateway through the internal Service.
OpenShell creates ordinary pods in `openshell`; the pinned host image adds the
OpenCode CLI and a narrow egress policy. OpenShell 0.0.116 requires its sandbox
ServiceAccount to use the privileged SCC, so this is a disposable demonstration
rather than a production security boundary.

## Dispatch path

```text
Automation Orchestrator workflow
  -> Omnigent API (cluster Service)
  -> OpenShell gateway (cluster Service)
  -> OpenCode agent in a container sandbox
  -> OpenCode Go or LiteLLM MaaS with the bootstrap key
```

In Automation Orchestrator, run `omnigent-dispatch` with a task. The workflow
uses an HTTP Basic credential to mint a short-lived Omnigent token, creates a
managed session through Omnigent's cluster Service, and sends the task to the
seeded OpenCode agent. The Omnigent Route uses that generated credential for
external access; the internal callback Service remains reachable by managed
hosts and runners. Delete finished sessions in Omnigent to remove their
sandboxes. The OpenShell gateway remains cluster-internal.

The disposable [Forgejo demo](cluster/forgejo-demo/README.md) supplies the sample
repository and issue. Bootstrap seeds those resources, creates scoped Forgejo
credentials for RHDH and Omnigent, and registers two Backstage templates:
`New Ansible Collection` and `Contribute to the Demo Ansible Collection`.
The first creates a Forgejo collection repository and catalog entry. The second
reads an issue and creates its feature branch. Dispatch the existing
`omnigent-dispatch` workflow with a task such as "Deliver issue #1 in
demo-owner/ansible-collection-demo as a pull request." The sandbox has
`demo-goldenpath issue 1`, `demo-goldenpath feature 1`, and
`demo-goldenpath pr 1 'Title'`; Git authentication and Backstage access are
injected at launch. The agent leaves the pull request for review.

## Validate and inspect

```bash
make test
KUBECONFIG="$HOME/.kube/config" oc -n openshift-gitops get applications
KUBECONFIG="$HOME/.kube/config" oc -n openshell get statefulset,builds,imagestream
KUBECONFIG="$HOME/.kube/config" oc -n omnigent get deployment,cluster,pvc
```
