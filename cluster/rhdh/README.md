# Developer Hub templates

Red Hat Developer Hub (Backstage) provides the demo's Ansible templates.
Open its link from Homepage after [bootstrap](../../README.md) and sign in
with [demo Keycloak](../demojam-keycloak/README.md). Catalog users come from
`DEMO_USERS_FILE`. Guest login is disabled, but permission enforcement is
disabled for this disposable demo, giving `demo-user` unrestricted catalog
and scaffolder access.

## Choose a template

- **New Ansible Collection** creates a Forgejo repository from
  `demo-agent/ansible-collection-template` and registers its catalog entry.
  It includes a starter role, a Molecule scenario, CentOS Stream 10 and RHEL 10
  inventory hosts, and an Ansible Development Tools Devfile.
- **Contribute to the Demo Ansible Collection** reads a Forgejo issue in
  `demo-owner/ansible-collection-demo.webapp` and creates `feature/issue-N`.
  It prepares the branch; the coding agent implements the change and opens the PR.

AO must run the feature template before creating the agent session. Its internal
gate waits for the Scaffolder task and verifies the branch. Repeat dispatches
reuse the prepared branch.

## Use the Sandbox helper

From an agent Sandbox working directory, replace `1` with the issue number:

```bash
demo-goldenpath issue 1
demo-goldenpath checkout 1
cd issue-1
# Implement, check, and commit the change.
demo-goldenpath pr 1 --body-file /tmp/pr-body.md
```

`checkout` requires an existing branch and never runs the feature template.
`demo-goldenpath new <name> <description>` runs the new collection template.
In a generated collection, `molecule test` uses disposable VMs; follow the
[shared test limits](../omnigent/README.md#run-molecule-tests).

Bootstrap creates the database and scoped Forgejo/Backstage service credentials
in Secrets. Sandboxes receive the endpoint and tokens through `omnigent-model`;
the helper uses Git askpass for Forgejo Git operations.

`make demo-reset` wipes generated Forgejo repositories and removes their catalog
registrations, then refreshes tokens and template sources. Bootstrap verifies
both templates, the demo collection entity, and the scaffolder HTTP action.
