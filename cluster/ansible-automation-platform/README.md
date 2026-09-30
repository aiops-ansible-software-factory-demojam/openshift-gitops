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

Forgejo hydration seeds the public `demo-owner/aap-config-as-code` repository.
Its [guide](../forgejo-demo/fixtures/aap-config-as-code/README.md) describes the
homelab-style dispatcher and VM lifecycle. GitOps owns `aap-vm-admin` and its
RBAC in `automation-vms` and `webapp-vms`, plus OS disk clone permissions.
Bootstrap creates its persistent API token and the AAP credential directly;
config-as-code references that credential without owning its secret inputs.

The root `execution-environment.yml` defines `demo-aap-ee`. Bootstrap generates
its context with ansible-builder and builds it with OpenShift's binary
BuildConfig. The cluster supplies Red Hat registry access; `.env` supplies the
Automation Hub token as a build-only Secret. `make aap-ee` rebuilds explicitly.

After GitOps settles, `make aap-configure` uses the generated AAP admin
credential to import root `aap_manifest.zip` and create VM API, SSH, RHEL CDN
entitlement and dispatch credentials by script. An EE Job then clones Forgejo
without authentication and runs `infra.aap_configuration.dispatch` to create
all other demo AAP objects. `webapp_vm`, `webapp_nginx` and `aap_configure_all`
are ready after synchronization. VM creation remains an explicit AAP launch.

The first install pulls several large images. If the node briefly reports
`DiskPressure`, inspect its free space and wait for kubelet to clear the
condition before retrying the rollout. The cluster's kubelet uses a five
minute pressure transition period. Do not add a disk pressure toleration to
the AAP pods.
