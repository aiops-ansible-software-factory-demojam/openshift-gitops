# demojam-ansible

This public Forgejo repository follows the homelab `group_vars/aap` and
`infra.aap_configuration.dispatch` model. Inventory, AAP object definitions,
and VM/webapp playbooks share one project. No SCM credential is required.

## Bootstrap boundary

Run `bash bootstrap/bootstrap.sh` from the **openshift-gitops** repository,
after populating its root `.env` and supplying `aap_manifest.zip`.

1. GitOps reconciles AAP, OpenShift Pipelines, VM namespaces/RBAC/Services,
   Forgejo and monitoring.
2. A one-off Tekton pipeline clones this repository and renders its
   `execution-environment.yml` using ansible-builder. Buildah mounts Hub
   authentication only for collection installation, then pushes the EE into
   the cluster registry. The root `requirements.yml` is the single collection
   dependency list used for both EE builds and AAP project synchronization.
3. Bootstrap imports the license and creates/reuses the VM API, SSH, RHEL
   entitlement, Hub and dispatch credentials. It creates an OAuth connection
   Secret and applies Resource Operator CRs for the project, inventory and
   dispatch template. No credential values are seeded in Git.
4. An EE Job clones this public repo and runs dispatch to configure the EE,
   inventory sources and templates. The Resource Operator owns the initial
   project/inventory; dispatch attaches the EE and credentials missing from
   the operator's JobTemplate schema. Static inventory supplies the VM API
   target; dynamic inventory discovers running VMs.

SCM and Git collection URLs use `http://forgejo.forgejo.svc.cluster.local:3000`.
They are reachable from the EE pipeline and AAP execution pods, without
Forgejo authentication. For local development outside the cluster, replace
that hostname with your Forgejo Route or use a port forward. Certified
collection installs additionally need Automation Hub authentication supplied
by bootstrap; no Forgejo token is required.

Dispatch references the runtime credentials by name and does not create or
rotate their secret inputs. Rerun `make aap-configure` in openshift-gitops to
reconcile runtime credentials and dispatch. Subsequent configuration changes
can use the AAP `aap_configure_all` template (`make aap-sync`). That template
pulls current Forgejo content and uses its runtime AAP dispatch credential.

## Launch and automate the RHEL webapp

In AAP, launch **webapp_vm**, then **webapp_nginx**. The first clones the
cluster's `rhel9` DataSource into `webapp-vms` and adds the generated public
SSH key through cloud-init. The second refreshes discovery, waits for SSH,
enables the entitled RHEL 9 BaseOS/AppStream repositories, and uses
`demo.greetings.nginx` from the public example collection. Controller installs
that collection from `collections/requirements.yml` on project synchronization;
root `requirements.yml` links to the same file. No Galaxy upload is required.

VM inventory queries only `automation-vms` and `webapp-vms`. The webapp is
`webapp-webapp-vms` in group `webapps`; its SSH hostname is the internal Service.
GitOps owns the HTTP/SSH Services, HTTPS Route and blackbox probe. The probe
becomes healthy once nginx serves HTTP. No automatic CI or schedule is added.

From openshift-gitops, the corresponding commands are:

```bash
make webapp-create
make webapp-nginx
make webapp-verify
make webapp-delete
```

`webapp-delete` launches the same VM template with `vm_state: absent`, removing
its owned disk. The namespace, Services and Route remain GitOps-managed.
The VM API account has no VM access outside the two demo namespaces. It can
clone OS disks but cannot create namespaces. TLS verification stays enabled.
The SSH key and API token are runtime demo credentials preserved by reruns.

## Generic VM example

The **openshift_virtualization_machine** template remains available for
CirrOS/Fedora examples in `automation-vms`, with `host: demo_cluster` and
`vm_state: present` or `absent`. It is separate from the fixed RHEL webapp.

## Reset

`make demo-reset` in openshift-gitops wipes Forgejo and developer-agent
sessions, then seeds this starting config and the README feature issue.
It preserves AAP runtime credentials and existing VMs. Delete the webapp
first when testing fresh provisioning, then reset, bootstrap, and launch it
again. Normal hydration preserves user commits; config changes must be pushed
to Forgejo before dispatch. Manifest ZIPs and `.env` files are excluded from
fixture snapshots.
