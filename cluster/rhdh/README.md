# Developer Hub golden paths

The `rhdh` GitOps Application installs Red Hat Developer Hub (Backstage) and a
single-instance CloudNative-PG database. Bootstrap creates the database Secret
and, after Forgejo is ready, hydrates a scoped Forgejo token and endpoint
ConfigMap. No credentials are committed. The Route is `https://rhdh.<cluster
ingress domain>`.

The catalog exposes two templates:

- **New Ansible Collection** generates a Forgejo repository from the seeded
  `demo-agent/ansible-collection-template` and registers its catalog entry.
- **Contribute to the Demo Ansible Collection** reads an issue in
  `demo-owner/ansible-collection-demo` and creates `feature/issue-N`.

The first template produces a collection with a starter role, a Molecule
scenario backed by the cluster's CentOS Stream 10 CDI image, and a Devfile based
on Ansible Development Tools. In an Omnigent sandbox, `molecule test` from the
generated collection root uses scoped access to disposable VMs in
`molecule-tests`. The second only
prepares a branch; it does not change code or open a PR.

AO calls the internal Backstage feature gate before creating an agent session.
The gate uses guest authentication to run the feature template, waits for its
task to complete, and verifies the branch exists. A repeat dispatch reuses the
already prepared branch. Sandboxes have `BACKSTAGE_URL` and Forgejo credentials
through the existing `omnigent-model` Secret. The helper uses Git askpass for
Forgejo Git operations.

From an agent Sandbox working directory:

```bash
demo-goldenpath checkout 1
cd issue-1
# edit, verify, and commit the requested change
demo-goldenpath pr 1 --body-file /tmp/pr-body.md
```

`demo-goldenpath new <name> <description>` runs the new collection template.
`demo-goldenpath issue 1` reads the example issue. `checkout` requires the
branch to exist already and never runs the feature template. The scaffolder
and catalog are also available in the Developer Hub UI.

`make demo-reset` replaces the disposable Forgejo data and rehydrates both
tokens and the template source. It also removes catalog locations for
collections generated in the disposable `demo-agent` Forgejo account, so
their catalog entries do not outlive the wiped repositories. Bootstrap
verifies the two catalog templates,
demo collection entity, and scaffolder HTTP action before reporting ready.
