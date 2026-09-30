# Demo AAP config as code

This public Forgejo repository follows the homelab `group_vars/aap` and
`infra.aap_configuration.dispatch` model. Inventory, AAP object definitions,
and VM/webapp playbooks share one project. No SCM credential is required.

## Bootstrap boundary

Run `bash bootstrap/bootstrap.sh` from the **openshift-gitops** repository,
after populating its root `.env` and supplying `aap_manifest.zip`.

1. GitOps reconciles AAP, VM namespaces/RBAC/Services, and monitoring.
2. OpenShift builds the EE defined by the root `execution-environment.yml`,
   using the cluster registry access and a mounted Automation Hub token.
3. A bootstrap script imports the license and manually creates/reuses AAP
   credentials: `demo-virtualmachine-admin`, `demo-webapp-ssh`,
   `demo-rhel-entitlement`, and `demo-aap-dispatch`. Its VM API token, SSH key,
   and dispatch Job inputs live in Kubernetes. They are never seeded in Git.
4. A Job clones this repo and runs dispatch to create the demo organization,
   EE, project, inventory sources, and job templates. Both inventory sources
   wait for synchronization. The static inventory supplies the first VM's
   API target; dynamic inventory discovers running VMs.

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
