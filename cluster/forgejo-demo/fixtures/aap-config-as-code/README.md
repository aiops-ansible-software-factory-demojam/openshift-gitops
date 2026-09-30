# Demo AAP config as code

This repository follows the homelab `igou-inventory/group_vars/aap` model:
declare AAP objects as inventory data and apply them with
`infra.aap_configuration.dispatch`. It combines the inventory and playbooks
in one repository so the demo needs one SCM project. Credentials come from
the runner environment rather than the homelab's 1Password integrations.

The dispatcher creates a `demo` organization, Forgejo project, SCM inventory,
execution environment, credentials, and the `openshift_virtualization_machine`
job template. Project and inventory refresh on launch. There are no schedules
or automatic CI jobs. Applying configuration does not launch a VM.

## Build the execution environment

The pinned Red Hat supported AAP 2.7 base image supplies the certified
Controller, Gateway, EDA, Hub, and OpenShift Virtualization collections.
The build adds the pinned config-as-code collection. Its API module
dependencies are already supplied by the supported base.
Galaxy installation skips transitive certified dependencies because they
are already in the base image. The dispatcher carries the same
`controller_applications` compatibility exclusion and extended async waits
as the homelab implementation.

Authenticate Podman to `registry.redhat.io` and to the registry where you
will publish the EE. Set `AAP_EE_IMAGE` to your writable registry image tag:

```bash
make ee
podman push "$AAP_EE_IMAGE"
```

Use a registry image the demo cluster can pull. A private destination also
needs an AAP Container Registry credential attached to the execution
environment. The shipped configuration assumes a public destination.

## Apply AAP configuration

Clone `__FORGEJO_URL__/demo-owner/aap-config-as-code.git`; the demo identities
are documented in the GitOps repository's Forgejo guide. Install
`ansible-navigator`, `ansible-builder` 3.1 or later, and Podman on the runner.

GitOps creates `automation-vms`, the `aap-vm-deployer` service account, and
namespace-scoped RBAC. The service account can manage VMs and DataVolumes
there and clone OS disks from `openshift-virtualization-os-images`. It cannot
create namespaces or change VMs in other namespaces.

With the demo cluster's `KUBECONFIG` active, verify the identity and supply
runtime inputs without adding credentials to files tracked by Git:

```bash
oc whoami --show-server
oc whoami
export AAP_HOST="https://$(oc -n ansible-automation-platform get route aap -o jsonpath='{.spec.host}')"
export AAP_USERNAME=admin
read -rsp 'AAP admin password: ' AAP_PASSWORD
export AAP_PASSWORD
export K8S_AUTH_HOST=$(oc whoami --show-server)
export K8S_AUTH_API_KEY=$(oc -n automation-vms create token aap-vm-deployer --duration=8h)
export K8S_AUTH_CA_CERT=$(oc -n automation-vms get configmap kube-root-ca.crt -o go-template='{{index .data "ca.crt"}}')
```

Set `FORGEJO_TOKEN` to the demo-agent token written by GitOps hydration and
keep the `AAP_EE_IMAGE` used for the build exported:

```bash
ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default -o jsonpath='{.status.domain}')
export FORGEJO_TOKEN=$(cat "/workspace/openshift-gitops/cluster/forgejo-demo/.state/$ingress_domain/agent-token")
make configure
```

TLS verification is enabled for AAP and Kubernetes. If the AAP Route uses
a private CA, add that CA to the EE trust store before building. The service
account token expires; mint a replacement and rerun `make configure` before
it expires or after a cluster reset. The dispatcher protects credential task
output, and navigator playbook artifacts are disabled.

## Create and remove a VM

Launch `openshift_virtualization_machine` from AAP with these extra variables:

```yaml
host: demo_cluster
vm_name: automation-demo
vm_state: present
```

The default guest is CirrOS with one CPU, 512 MiB RAM, a container disk, and
the pod network. The job waits for the VM to become Ready. The container
disk is disposable: use a DataSource clone for a persistent Fedora VM:

```yaml
host: demo_cluster
vm_name: automation-fedora
vm_state: present
vm_disk_source: datasource
vm_datasource_name: fedora
vm_memory: 2Gi
vm_disk_size: 30Gi
vm_user_data: |
  #cloud-config
  ssh_pwauth: false
```

Add your public SSH key to `vm_user_data` when you need guest access. The
DataSource must be Ready and the default StorageClass must support the disk.
For deletion, launch with the same `host` and `vm_name`, and `vm_state: absent`.
VM deletion also removes its owned DataVolume and PVC. Change disk source
only after deleting the existing VM.

To run the same playbook locally with navigator, write the non-secret CA
certificate to the ignored project file and point the EE at that mounted file:

```bash
printf '%s\n' "$K8S_AUTH_CA_CERT" > cluster-ca.crt
export K8S_AUTH_SSL_CA_CERT=/runner/project/cluster-ca.crt
make vm VM_ARGS='-e vm_name=automation-demo -e vm_state=present'
oc -n automation-vms get virtualmachines,virtualmachineinstances
make vm VM_ARGS='-e vm_name=automation-demo -e vm_state=absent'
```

## Seed and reset

The GitOps fixture supplies this repository only when it is empty. Normal
hydration preserves its commits, branches, issues, and PRs. The existing
`make demo-reset` wipes Forgejo and recreates the starting repository along
with the collection fixtures. It does not reset AAP objects or delete VMs;
delete a VM through the playbook and rerun configuration for AAP convergence.

References: [AAP configuration collection](https://github.com/redhat-cop/infra.aap_configuration),
[OpenShift Virtualization collection](https://catalog.redhat.com/en/software/collection/redhat/openshift_virtualization),
and [CDI clone authorization](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/clone-datavolume.md).
