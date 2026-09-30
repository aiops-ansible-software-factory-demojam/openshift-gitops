# demojam-ansible

This public Forgejo repository follows the homelab `group_vars/aap` and
`infra.aap_configuration.dispatch` model. Inventory, AAP object definitions,
and VM/webapp playbooks share one project. No SCM credential is required.

## Bootstrap boundary

Run `bash bootstrap/bootstrap.sh` from the **openshift-gitops** repository,
after populating its root `.env` and supplying `aap_manifest.zip`.

1. GitOps reconciles AAP, OpenShift Pipelines, VM namespaces/RBAC/Services,
   Forgejo and monitoring.
2. Bootstrap imports the license and creates/reuses the VM API, SSH, RHEL
   entitlement and dispatch credentials. It creates an OAuth connection
   Secret and applies the inventory/project CRs, waits for the real project
   to sync, then creates the dispatch template CR. No credential values are seeded in Git.
3. Bootstrap registers Red Hat `ee-supported-rhel9`, attaches it and the runtime
   dispatch credential to the template, and syncs `inventory.yml` from this
   project so the `aap` host exists. It launches `aap_configure_all` through the
   AAP API and waits for the Controller job to succeed. Project updates install
   `requirements.yml`; dispatch configures the remaining inventory sources and
   templates. The Resource Operator owns the initial project/inventory/template
   base fields. Static inventory supplies the VM API target; dynamic inventory
   discovers running VMs. There is no standalone Kubernetes configuration Job.

There is no custom AAP image build or Automation Hub token. Root `requirements.yml`
installs `infra.aap_configuration` from public Galaxy and `demo.webapp` from
public Forgejo Git on project updates. Controller's isolated collection cache
cannot see the supported image's collection path during installation, so four
`type: dir` entries copy CaC's certified dependencies from that image into the
cache. They require no downloads or Hub authentication. The supported image
already contains the Virtualization collection and required Python/system packages.

SCM and Git collection URLs use `http://forgejo.forgejo.svc.cluster.local:3000`.
They are reachable from AAP project updates and execution pods, without
Forgejo authentication. For local development outside the cluster, use the supported EE and replace
that hostname with your Forgejo Route or use a port forward. No Hub or Forgejo
token is required for project requirements.

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
`demo.webapp.nginx` from the public example collection. Controller installs
that collection from `requirements.yml` on project synchronization;
No Galaxy upload is required.

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
