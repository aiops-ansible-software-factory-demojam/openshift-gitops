# Ansible Automation Platform

AAP runs the demo's Ansible configuration and VM jobs. The AAP 2.7 operator
is installed before this application, which creates a platform gateway,
automation controller, and Event-Driven Ansible (EDA). Services use single
replicas; Hub, Lightspeed, MCP, and metrics service are disabled.

Start with the [root quickstart](../../README.md). Bootstrap imports the license,
creates runtime credentials, and runs `aap_configure_all` inside Controller.
The seeded [demojam-ansible guide](https://github.com/aiops-ansible-software-factory-demojam/demojam-ansible/blob/main/README.md)
describes the configuration and playbooks. Jobs use the digest-pinned Red Hat
`ee-supported-rhel9` image and public Forgejo/Galaxy sources; certified
dependencies come from that image, without a separate Hub token.

## Run the webapp jobs

From the repository root:

```bash
make webapp-create    # Clone the RHEL 9 DataSource into webapp-vms
bash bootstrap/bootstrap.sh aap launch webapp_selinux_permissive
make webapp-nginx     # Install nginx using demo.webapp.nginx
make webapp-verify    # Check VM readiness, HTTPS, and the blackbox probe
```

Bootstrap already runs these jobs in order. `webapp_vm` provisions the guest
and SSH key; `webapp_selinux_permissive` prepares the demo baseline in a
separate playbook after provisioning. `webapp_nginx` discovers the guest and
uses the manifest's RHEL entitlement to install packages. GitOps owns its
namespace, Services, Route, and probe.
The probe is expected to be down until nginx is installed.

The nginx job leaves SELinux mode unchanged. After the fault job enables
Enforcing and the tested collection fix is merged, launch `webapp_nginx`
once and run `bash bootstrap/bootstrap.sh webapp verify-enforcing`.

Use `make aap-configure` to refresh the license, credentials, and configuration,
or `make aap-sync` to apply configuration alone. `make webapp-delete` deletes
only the webapp VM and its owned disk.

## Open AAP or check readiness

Find the gateway Route and workloads using `~/.kube/config`:

```bash
export KUBECONFIG="$HOME/.kube/config"
oc whoami --show-server
oc whoami
oc -n ansible-automation-platform get routes
oc -n ansible-automation-platform get ansibleautomationplatform aap
oc -n ansible-automation-platform get automationcontrollers,edas,pods
```

Browser login uses [demo Keycloak](../demojam-keycloak/README.md). The local
`admin` account uses the operator-generated `aap-admin-password` Secret for
bootstrap and recovery; credentials are not stored in Git.

Initial image pulls can cause `DiskPressure`. Inspect node free space and
wait for kubelet to clear the condition before retrying. Do not add a disk
pressure toleration to the AAP pods.
