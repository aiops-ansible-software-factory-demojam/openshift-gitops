# demo.${REPO_NAME}

${REPO_DESCRIPTION}

This collection was generated from the Ansible collection golden path in
Backstage. It follows the homelab starter layout with a role and Molecule
scenario, using a Podman container for this demo.

## Get started

Install Ansible development tools and Podman, then run:

```sh
ansible-galaxy collection install -r requirements.yml
ansible-lint
ansible-galaxy collection build --output-path /tmp
cd extensions && molecule test
```

The `roles/example` role demonstrates a fully qualified Ansible module and a
role default. Rename it or add your own role, then change the Molecule converge
and verify playbooks to exercise the behavior you want to deliver.

## Layout

- `galaxy.yml` defines the collection package.
- `roles/example/` is the starter role.
- `extensions/molecule/default/` tests the role in a disposable Rocky Linux 9 container.
- `devfile.yaml` defines development commands for editors that support Devfiles.
