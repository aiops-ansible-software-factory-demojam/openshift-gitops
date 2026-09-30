# Demo AAP config as code

This repository follows the homelab `igou-inventory/group_vars/aap` model:
declare AAP objects as inventory data and apply them with
`infra.aap_configuration`. Inventory and playbooks share one SCM project.
Credentials come from the runner environment rather than 1Password.

The configuration creates a `demo` organization, Forgejo project, execution
environment, credentials, inventory, and `openshift_virtualization_machine`
job template. The inventory combines the static `demo_cluster` API target
with VM discovery in `automation-vms`. There are no schedules or automatic CI.
Applying configuration imports the subscription and syncs inventory; it does
not launch a VM.

## Build and configure from the GitOps repository

GitOps creates the `demo-aap-ee` BuildConfig and ImageStream in
`ansible-automation-platform`. OpenShift pulls the pinned supported AAP 2.7
base using its existing registry credentials, adds `infra.aap_configuration`,
and pushes `demo-aap-ee:latest` to the internal registry. Certified Controller,
Platform and OpenShift Virtualization collections come from the base.
No local build, image tag input, or Red Hat registry password is needed.

From the GitOps repository root, populate `.env` with `AAP_PASSWORD` and the
hydration-generated demo-agent `FORGEJO_TOKEN`. The operator's gateway admin
password is in `aap-admin-password`. Place your subscription manifest at
`aap_manifest.zip` in the same directory; both files are gitignored.

```bash
make aap-ee
make aap-configure
```

These explicit commands require `oc`, `yq`, `jq`, and `tar`. They load `.env`
from the current directory, default `KUBECONFIG` to `$HOME/.kube/config`, and
verify the cluster identity. `EXPECTED_SERVER` can pin the intended API URL.
`AAP_LICENSE_FILE` overrides the default root manifest path. `AAP_EE_IMAGE`
is an optional image override; the default is the internal BuildConfig output.
From a clone of this Forgejo repository, use `make ee` and `make configure`
instead, with the same `.env` and manifest conventions.

Configuration runs in an explicit OpenShift Job using the built EE. It
streams the manifest into the Job, uploads the project, and imports the license through
`infra.aap_configuration.controller_license` **before** dispatching other
objects. Missing manifests fail before a Job is created. Credential task
output is protected, the temporary input Secret is deleted after the run,
and the Job expires after an hour. Large manifests are supported without
putting the ZIP in a size-limited Kubernetes Secret. This is an on-demand
bootstrap operation.

The helper discovers the AAP and Forgejo Routes, cluster API URL and public
CA. It mints an eight-hour token from GitOps' `aap-vm-admin` service account
when `K8S_AUTH_API_KEY` is unset. Rerun configuration to renew that token.
`AAP_HOST`, `FORGEJO_URL`, `K8S_AUTH_HOST`, `K8S_AUTH_API_KEY`, and
`AAP_K8S_CA_CERT` remain optional overrides in `.env`.

The same `demo-virtualmachine-admin` AAP credential is attached to the
`demo-virtualmachines` inventory source and the VM job template. Its service
account can manage VMs/DataVolumes in `automation-vms`, read their services,
and clone standard OS disks. It cannot change VMs in other namespaces or
create namespaces. Discovery uses the certified
`redhat.openshift_virtualization.kubevirt` inventory plugin and explicitly
limits its namespace to `automation-vms`. VM hosts use `<name>-<namespace>`.
The static inventory remains available to create the first VM.

Both inventory sources wait for their updates; configuration reports failed
syncs instead of returning while they are pending. The dispatcher retains
the homelab's `controller_applications` compatibility exclusion. AAP and
Kubernetes TLS verification remain enabled. `AAP_K8S_CA_CERT` is certificate
**contents** for the AAP credential; `K8S_AUTH_SSL_CA_CERT` is a **file path**
for local navigator checks. Do not put PEM contents in `K8S_AUTH_CA_CERT`.

## Create and remove a VM

Launch `openshift_virtualization_machine` from AAP with these extra variables:

```yaml
host: demo_cluster
vm_name: automation-demo
vm_state: present
```

The default guest is CirrOS with one CPU, 512 MiB RAM, a disposable container
disk, and the pod network. The job waits for Ready. For a persistent Fedora
VM, use a DataSource clone:

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

Add a public SSH key to `vm_user_data` when guest login is needed. No guest
SSH credential is needed for API creation/deletion. The DataSource must be
Ready and the default StorageClass must support the disk. For deletion, use
the same `host` and `vm_name` with `vm_state: absent`. VM deletion removes
its owned DataVolume and PVC. Delete a VM before changing its disk source.

```bash
oc -n automation-vms get virtualmachines,virtualmachineinstances,datavolumes
```

## Seed and reset

GitOps seeds this repository only when it is empty. Normal hydration
preserves commits, branches, issues and PRs. `make demo-reset` wipes Forgejo
and recreates the starting repositories. It does not reset AAP objects or
delete VMs; delete VMs through the playbook and rerun configuration for AAP
convergence. Manifest ZIPs, `.env` files and local runtime artifacts are
excluded from fixture snapshots.

References: [AAP configuration collection](https://github.com/redhat-cop/infra.aap_configuration),
[OpenShift Virtualization collection](https://catalog.redhat.com/en/software/collection/redhat/openshift_virtualization),
and [CDI clone authorization](https://github.com/kubevirt/containerized-data-importer/blob/main/doc/clone-datavolume.md).
