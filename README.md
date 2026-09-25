# Demo OpenShift GitOps

This repository installs a disposable OpenShift demo with one Forgejo instance,
OpenShell container sandboxes, Omnigent, and Automation Orchestrator. Argo CD
installs the applications from `cluster/values.yaml`. The only sandbox runtime is
the cluster's ordinary CRI-O container runtime; no Kata operator, RuntimeClass,
worker labels, or warm pool is used.

## Bootstrap

Use an OpenShift cluster with OLM, the Red Hat and certified operator catalogs,
working ingress, a default RWO StorageClass, and enough capacity for AAP,
Orchestrator, Developer Hub, Forgejo, Omnigent, and their databases. The account
in `~/.kube/config` needs cluster-admin rights. Install `oc`, `kustomize`, `helm`,
`yq`, `jq`, `openssl`, `curl`, and `git` locally. The checkout must be on a
publishable `main` branch at the repository in `cluster/values.yaml`; Argo CD
reads that remote repository.

Run:

```bash
bash bootstrap/bootstrap.sh
```

On the first run, bootstrap prompts for an OpenCode Go API key. To use the
official OpenAI API instead:

```bash
MODEL_PROVIDER=openai MODEL_NAME=gpt-4.1-mini bash bootstrap/bootstrap.sh
```

For a noninteractive run, set `MODEL_API_KEY` in the environment. The key is
stored only in a Kubernetes Secret in `omnigent`, never in Git or a shell trace.
Subsequent runs reuse the existing Secret. Delete `omnigent-model` and
`omnigent-agent` before rerunning if you intend to change providers or models.

Bootstrap detects the cluster's ingress domain, updates checked-in Route hosts
when needed, commits that domain change, and pushes `main` before creating the
root Argo CD Application. It installs the OpenShift GitOps operator, creates the
two bootstrap Secrets, waits for the app-of-apps and OpenCode image build, then
publishes the `omnigent-dispatch` workflow in Automation Orchestrator. A dirty
checkout must be published first if the ingress domain differs.

## Sandbox interface

Install the [OpenShell CLI](https://github.com/NVIDIA/OpenShell), then use the
wrapper to reach the cluster-internal gateway through your authenticated `oc`
session:

```bash
bash scripts/sandbox.sh create --name demo --detach
bash scripts/sandbox.sh exec demo -- opencode --version
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
  -> OpenCode Go or OpenAI API with the bootstrap key
```

In Automation Orchestrator, run `omnigent-dispatch` with a task. The workflow
creates an Omnigent managed session and sends the task to the seeded OpenCode
agent. Open the Omnigent UI with `oc -n omnigent port-forward svc/omnigent
8000:8000` to inspect the session. Delete finished sessions in Omnigent to
remove their sandboxes. The Omnigent and OpenShell APIs are deliberately internal
and unauthenticated; access to their Kubernetes Services must remain trusted.

The disposable [Forgejo demo](cluster/forgejo-demo/README.md) supplies the sample
repository and issue. Bootstrap installs the Forgejo app; seed its users and
repositories with its documented `demo.sh` commands when needed.

## Validate and inspect

```bash
make test
KUBECONFIG="$HOME/.kube/config" oc -n openshift-gitops get applications
KUBECONFIG="$HOME/.kube/config" oc -n openshell get statefulset,builds,imagestream
KUBECONFIG="$HOME/.kube/config" oc -n omnigent get deployment,cluster,pvc
```
