# Agent guide

- AAP object definitions live in `group_vars/aap/`; apply them through
  `playbooks/aap/configure-aap.yml` and `infra.aap_configuration.dispatch`.
- Keep runtime credential lookups in inventory variables. Never commit
  credentials or print their resolved values.
- Use the custom EE built by OpenShift's `demo-aap-ee` BuildConfig. `make ee`
  builds in the cluster; `make configure` runs config-as-code in an EE Job.
  Use `ansible-navigator` for local syntax checks with an accessible EE image.
  Run Ansible lint before submitting changes. There is no CI.
- Write Ansible YAML in block style with FQCNs and named plays/tasks.
- VM automation targets `automation-vms`. The `host` launch variable selects
  the inventory host; the AAP template sets it to `demo_cluster`.
- Verify the active cluster and identity before cluster operations, and
  obtain current user authorization before applying AAP config or changing VMs.
- Read `README.md` for the seed/reset boundary and token renewal procedure.
