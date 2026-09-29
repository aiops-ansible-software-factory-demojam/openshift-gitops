# Optional Developer Hub golden paths

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
scenario, and a Devfile based on Ansible Development Tools. The second only
prepares a branch; it does not change code or open a PR.

Sandboxes have `BACKSTAGE_URL` and Forgejo credentials through the existing
`omnigent-model` Secret. The `demo-goldenpath` helper obtains a short-lived
Backstage guest token itself, so an agent does not need to copy a token or
configure a login. It uses Git askpass for Forgejo Git operations.

From an agent Sandbox working directory:

```bash
demo-goldenpath feature 1
cd issue-1
# edit, verify, and commit the requested change
demo-goldenpath pr 1
```

`demo-goldenpath new <name> <description>` runs the new collection template.
`demo-goldenpath issue 1` reads the example issue. `feature` is safe to rerun:
it reuses the existing branch, fetches it, and checks it out locally. The
scaffolder and catalog can also be used in the Developer Hub UI.

AO's published issue workflow still directs the agent to `forgejo-issue`.
It does not call Backstage. This keeps the current smoke demo repeatable while
the golden path is available for explicit agent sessions and later AO use.

`make demo-reset` replaces the disposable Forgejo data and rehydrates both
tokens and the template source. It also removes catalog locations for
collections generated in the disposable `demo-agent` Forgejo account, so
their catalog entries do not outlive the wiped repositories. Bootstrap
verifies the two catalog templates,
demo collection entity, and scaffolder HTTP action before reporting ready.
