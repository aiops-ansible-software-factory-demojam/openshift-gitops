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

The `roles/example` role demonstrates a fully qualified Ansible module and a
role default. Rename it or add your own role, then change the Molecule converge
and verify playbooks to exercise the behavior you want to deliver.

The sandbox supplies Ansible Development Tools, the Kubernetes Python client,
SSH, `KUBECONFIG`, and `MOLECULE_GLOB`. Molecule installs its pinned collection
dependencies automatically. Run from the collection root so the shared
`extensions/molecule/config.yml` is discovered. `make test` runs all scenarios.

The `default` scenario's YAML inventory contains two hosts: `instance` clones
the `centos-stream10` DataSource, and `instance-rhel10` clones `rhel10`. Both
DataSources are in `openshift-virtualization-os-images`; both VMs are created in
`molecule-tests`. One test run provisions, converges, verifies, and destroys both:

```sh
molecule test                 # CentOS Stream 10 and RHEL 10
make test                     # Same default scenario
```

Each VM gets two vCPUs, 2 GiB RAM, a disposable 30 GiB disk, and a generated SSH key. Connections
use the VM's pod IP; no NodePort or cluster-wide node permissions are needed.
The namespace quota permits up to four test VMs and 120 GiB of requested disks.

The YAML inventory uses fixed hostnames `instance` and `instance-rhel10`,
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
`extensions/molecule/default/inventory/hosts.yml` with a distinct fixed name,
its `mp.kubevirt.boot_source`, and expected distribution / major version.
Common compute and SSH settings stay in `inventory/group_vars/molecule.yml`;
override them in the host's `mp.kubevirt` settings when required.
Grant `get` for the new DataSource in the GitOps `molecule-image-cloner` Role
before using it. The disk must be at least as large as the source image, and the
guest must support cloud-init SSH key injection. Each VM gets one boot DataVolume.

## Layout

- `galaxy.yml` defines the collection package.
- `roles/example/` is the starter role.
- `extensions/molecule/config.yml` shares lifecycle configuration across scenarios.
- `extensions/molecule/requirements-test.yml` pins the provisioner release.
- `extensions/molecule/default/` tests the role on both CentOS Stream 10 and RHEL 10 VMs.
- `ansible.cfg` and `Makefile` configure collection resolution and root-level test commands.
- `devfile.yaml` defines development commands for editors that support Devfiles.
