# demo.${REPO_NAME}

${REPO_DESCRIPTION}

This collection was generated from the Ansible collection golden path in
Backstage. It follows the homelab starter layout with a role and Molecule
scenario, using a disposable CentOS Stream 10 KubeVirt VM for this demo.

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

The test clones the existing `centos-stream10` DataSource from
`openshift-virtualization-os-images` into `molecule-tests`. Each VM gets two
vCPUs, 2 GiB RAM, a disposable 30 GiB disk, and a generated SSH key. Connections
use the VM's pod IP; no NodePort or cluster-wide node permissions are needed.
The namespace quota permits up to four test VMs and 120 GiB of requested disks.

The YAML inventory uses the fixed hostname `instance`, which the provisioner
also uses as the VM name. Collision risk is accepted temporarily: serialize
test runs across all demo sandboxes, collections, and scenarios sharing
`molecule-tests`. Overlapping runs can modify or delete each other's VM. After
an interrupted run, use `molecule destroy` from the same collection once no
other run is using that VM. Provisioner-managed run naming is tracked in
[molecule_provisioners issue #59](https://github.com/david-igou/ansible-collection-molecule_provisioners/issues/59).

These VM tests are configured for the demo's agent sandboxes. Local devcontainers
and standalone Devfile workspaces need their own credentials and VM network
access. The scenario checks that the golden image is ready and verifies the
connected guest is CentOS Stream 10.

## Layout

- `galaxy.yml` defines the collection package.
- `roles/example/` is the starter role.
- `extensions/molecule/config.yml` shares lifecycle configuration across scenarios.
- `extensions/molecule/requirements-test.yml` pins the provisioner release.
- `extensions/molecule/default/` tests the role on a disposable CentOS Stream 10 VM.
- `ansible.cfg` and `Makefile` configure collection resolution and root-level test commands.
- `devfile.yaml` defines development commands for editors that support Devfiles.
