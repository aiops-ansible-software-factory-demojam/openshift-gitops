# Ansible Automation Platform

The `ansible-automation-platform-operator` Argo CD application installs the
AAP 2.7 operator. This application creates one AAP instance with platform
gateway, automation controller, and Event-Driven Ansible. Hub, Lightspeed,
MCP, and metrics service are disabled. The instance uses the cluster's RBD
StorageClass and single replicas for its gateway, controller, Redis, and EDA
services.

The operator generates the initial admin credentials in a Secret; they are
not stored in Git. Find the gateway Route and confirm the components with:

```bash
oc -n ansible-automation-platform get ansibleautomationplatform aap
oc -n ansible-automation-platform get routes
oc -n ansible-automation-platform get automationcontrollers,edas
oc -n ansible-automation-platform get deployments,statefulsets,pods
aap_host=$(oc -n ansible-automation-platform get route aap -o jsonpath='{.status.ingress[0].host}')
curl -fsS "https://$aap_host/api/gateway/v1/ping/"
```

The operator is installed in sync wave 10, before the instance in wave 30.
This is a standalone AAP deployment; AO's existing issue workflow does not
depend on it.

Forgejo hydration seeds the public `demo-owner/demojam-ansible` repository.
Its [guide](../forgejo/fixtures/demojam-ansible/README.md) describes the
homelab-style dispatcher and VM lifecycle. GitOps owns `aap-vm-admin` and its
RBAC in `automation-vms` and `webapp-vms`, plus OS disk clone permissions.
Bootstrap creates its persistent API token and the AAP credential directly;
config-as-code references that credential without owning its secret inputs.

The public `demojam-ansible` repo owns its `execution-environment.yml` and
`requirements.yml` for the mutable Git collection. Certified collections are
pinned in the EE definition. `make aap-ee` starts one
Tekton PipelineRun: clone the public repo, render with ansible-builder, build
with Buildah, and push `demo-aap-ee:latest` to the internal registry. The
OpenShift Pipelines operator is installed by GitOps. This is an explicit build,
with no CI trigger. Hub credentials are temporary mounted Secrets,
never build arguments or task results. Bootstrap removes completed task pods,
build workspaces and the Hub Secret after collecting the image digest.
Failed task pods are retained for log inspection.
Buildah does not inherit kubelet authentication. Instead, a pipeline step
imports the repository-defined base into an ImageStream with local reference
policy. OpenShift performs the authenticated import; Buildah pulls through the
internal registry using its service account token. The namespace service CA
verifies registry TLS. No global pull Secret is copied into the task.

`make aap-configure` imports `aap_manifest.zip`, seeds runtime credentials,
creates a gateway token for the Resource Operator, and applies the bootstrap
`AnsibleInventory` and `AnsibleProject` CRs. It waits for the real inventory and
synced project in AAP, then applies the `JobTemplate` CR and verifies its API
bindings. An EE Job then
clones public Forgejo and runs configuration dispatch. The installed operator
template role does not set an EE; dispatch attaches it and runtime credentials, and
manages inventory sources and application templates. The CRs own the initial
inventory and project. Subsequent sync uses `aap_configure_all`.

The VM service account and token live in `ansible-automation-platform`, with
RoleBindings granting access to `automation-vms` and `webapp-vms`. All AAP SCM
and Git collection reads use the internal Forgejo Service without credentials.
Certified collections are built into the EE using temporary Hub authentication.
Project updates use anonymous Forgejo and an anonymous Galaxy source; no runtime
Hub credential is needed.

The first install pulls several large images. If the node briefly reports
`DiskPressure`, inspect its free space and wait for kubelet to clear the
condition before retrying the rollout. The cluster's kubelet uses a five
minute pressure transition period. Do not add a disk pressure toleration to
the AAP pods.
