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

AAP uses the pinned Red Hat `ee-supported-rhel9` image directly. There is no
custom AAP EE build or Automation Hub token. Public project `requirements.yml`
installs `infra.aap_configuration` from Galaxy and the example collection from
Forgejo Git. Controller's project sync isolates its collection cache from the
image collection path. The requirements therefore copy CaC's four certified
dependencies from `/usr/share/ansible/collections` in the supported image into
that cache; no Hub download is performed. Project sync and execution use the
supported image's Python/system dependencies and Virtualization collection.
OpenShift pulls this image using its existing registry authentication.

OpenShift Pipelines remains installed for the separate OpenCode sandbox image.
It is not needed for AAP configuration or job execution.

`make aap-configure` imports `aap_manifest.zip`, seeds runtime credentials,
creates a gateway token for the Resource Operator, and applies the bootstrap
`AnsibleInventory` and `AnsibleProject` CRs. It waits for the real inventory and
synced project in AAP, then applies the `JobTemplate` CR and verifies its API
bindings. Bootstrap then registers the supported EE, attaches it and the runtime
dispatch credential to `aap_configure_all`, and syncs `inventory.yml` through an
SCM inventory source. This supplies the `aap` host that the initially empty
inventory CR does not contain. Bootstrap launches the template with
`POST /api/controller/v2/job_templates/<id>/launch/` and waits for the Controller
job to succeed. AAP's project update installs `requirements.yml`; dispatch
manages the remaining inventory sources and application templates. The CRs own
the initial inventory/project/template base fields. First and subsequent syncs
both run through `aap_configure_all`; no standalone Kubernetes configuration Job
or bootstrap password-copy Secret is created.

The VM service account and token live in `ansible-automation-platform`, with
RoleBindings granting access to `automation-vms` and `webapp-vms`. All AAP SCM
and Git collection reads use the internal Forgejo Service without credentials.
Certified collections are already bundled in the supported EE.
Project updates use anonymous Forgejo and an anonymous Galaxy source; no
Hub credential is needed.

The first install pulls several large images. If the node briefly reports
`DiskPressure`, inspect its free space and wait for kubelet to clear the
condition before retrying the rollout. The cluster's kubelet uses a five
minute pressure transition period. Do not add a disk pressure toleration to
the AAP pods.
