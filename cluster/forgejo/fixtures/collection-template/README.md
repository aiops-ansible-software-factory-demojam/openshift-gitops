# demo.${REPO_NAME}

${REPO_DESCRIPTION}

This collection was generated from the Ansible collection golden path in
Backstage. It follows the homelab starter layout with a role and Molecule
scenario, using disposable CentOS Stream 10 and RHEL 10 KubeVirt VMs for this demo.

## Get started

Run these commands from the collection root in a demo Omnigent agent sandbox:

```sh
ansible-galaxy collection install -r extensions/molecule/requirements-test.yml
ansible-lint
ansible-galaxy collection build --output-path /tmp
molecule test
```

The default scenario prints hello world on both test hosts, then verifies SSH
connectivity and the guest operating systems. `roles/example` remains a starter
role; add a scenario to converge your role and verify its intended behavior.

The sandbox supplies Ansible Development Tools, the Kubernetes Python client,
SSH, `KUBECONFIG`, and `MOLECULE_GLOB`. Molecule installs its pinned collection
dependencies automatically. Run from the collection root so the shared
`extensions/molecule/config.yml` is discovered. `make test` runs all scenarios.

The shared `utils/inventory/hosts.yml` contains two hosts: `centos-stream10`
clones the `centos-stream10` DataSource, and `rhel10` clones `rhel10`. Both
DataSources are in `openshift-virtualization-os-images`; both VMs are created in
`molecule-tests`. One test run provisions, converges, verifies, and destroys both:

```sh
molecule test                 # CentOS Stream 10 and RHEL 10
make test                     # Same default scenario
```

Each VM gets two vCPUs, 2 GiB RAM, a disposable 30 GiB disk, and a generated SSH key. Connections
use the VM's pod IP; no NodePort or cluster-wide node permissions are needed.
The namespace quota permits up to four test VMs and 120 GiB of requested disks.

The YAML inventory uses fixed hostnames `centos-stream10` and `rhel10`,
which the provisioner also uses as VM names. Collision risk is accepted
temporarily: serialize test runs across all demo sandboxes, collections, and scenarios sharing
`molecule-tests`. Overlapping runs can modify or delete each other's VM. After
an interrupted run, use `molecule destroy` from the same collection once no
other run is using either VM. Provisioner-managed run naming is tracked in
[molecule_provisioners issue #59](https://github.com/david-igou/ansible-collection-molecule_provisioners/issues/59).

These VM tests are configured for the demo's agent sandboxes. Local devcontainers
and standalone Devfile workspaces need their own credentials and VM network
access. Preflight checks each host's golden image is ready before provisioning.
Verification checks each connected guest's distribution and major version
against that host's inventory settings.

To add another OS image, add a host to
`extensions/molecule/utils/inventory/hosts.yml` with a distinct fixed name,
its `mp.kubevirt.boot_source`, and expected distribution / major version.
Common compute and SSH settings stay in `utils/inventory/group_vars/molecule.yml`;
override them in the host's `mp.kubevirt` settings when required.
Grant `get` for the new DataSource in the GitOps `molecule-image-cloner` Role
before using it. The disk must be at least as large as the source image, and the
guest must support cloud-init SSH key injection. Each VM gets one boot DataVolume.

To add a scenario, create a directory under `extensions/molecule/` with only
`molecule.yml`, `converge.yml`, and `verify.yml`. Set `scenario.name` to the
directory name. The shared `config.yml` supplies inventory and lifecycle paths;
scenario playbooks target `hosts: molecule`. Import
`../utils/playbooks/verify.yml` to reuse host connectivity and OS checks, then
add behavioral assertions for your scenario. No lifecycle copies or role
symlinks are needed; shared `config.yml` supplies Molecule's role search path.

## Layout

- `galaxy.yml` defines the collection package.
- `roles/example/` is the starter role.
- `extensions/molecule/config.yml` shares lifecycle configuration across scenarios.
- `extensions/molecule/requirements-test.yml` pins the provisioner release.
- `extensions/molecule/utils/inventory/` tracks boot images and expected OS versions for all scenarios.
- `extensions/molecule/utils/playbooks/` supplies create, prepare, destroy, and common host verification.
- `extensions/molecule/default/` contains only `molecule.yml`, hello-world `converge.yml`, and `verify.yml`.
- `ansible.cfg` and `Makefile` configure collection resolution and root-level test commands.
- `devfile.yaml` defines development commands for editors that support Devfiles.
