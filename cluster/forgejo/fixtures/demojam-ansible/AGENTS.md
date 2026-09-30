# Agent guide

- AAP objects are inventory data under `group_vars/aap/`; apply them through
  `playbooks/aap/configure-aap.yml` and `infra.aap_configuration.dispatch`.
- Runtime credentials are owned by openshift-gitops bootstrap scripts. Do not
  manage their secret inputs through dispatch or commit secret values.
- Resource Operator CRs own the initial project/inventory and dispatch template
  base fields. Dispatch extends the template with its EE and credentials.
- This repo defines the custom EE; openshift-gitops builds it through Tekton. Use it for syntax
  checks and run Ansible lint. There is no CI.
- Write block-style YAML with FQCNs and named plays/tasks. Inventory carries
  runtime lookups; content consumes the values.
- `webapp_vm` manages only webapp in webapp-vms. The generic VM playbook stays
  confined to automation-vms. Preserve the `host: demo_cluster` launch variable.
- Verify cluster identity and current user authorization before live changes.
- Read README.md for bootstrap, public SCM, and reset behavior.
