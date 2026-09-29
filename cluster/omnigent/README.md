# Omnigent and Agent Sandbox

Omnigent serves the API in `omnigent` and uses the Red Hat Agent Sandbox
operator to create one `Sandbox` per managed session in `omnigent-sandboxes`.
The server ServiceAccount can manage Sandboxes, inspect their Pods, and create
short-lived launch-token Secrets only in that runner namespace. The runner has
no Kubernetes API token. Its fixed non-root UID uses the `nonroot-v2` SCC.

`omnigent-model` in `omnigent-sandboxes` holds the OpenCode Go key and inline
OpenCode configuration for `demo/gpt-6-luna`. Forgejo hydration adds the
scoped `demo-agent` token and internal URL to this Secret, so new Sandboxes
can clone and push the demo collection. `omnigent-agent` in `omnigent`
holds the `automation-developer` API agent specification, whose YAML name is
also `automation-developer`. Bootstrap creates both; no key is committed. The
image built from `image/` starts from the digest-pinned official
Ansible Development Tools image (26.9.0), which includes Molecule, pytest-ansible,
ansible-builder, ansible-creator, and ansible-navigator. It installs Omnigent
v0.15.0 in `/opt/omnigent` so its Python dependencies stay separate from the
Ansible tools, and adds Node.js, Bubblewrap, tmux, OpenCode 1.18.32, and the
`forgejo-issue` and `demo-goldenpath` helpers. The Ansible tools supply
development commands; running container or VM tests still needs a test target
and its corresponding runtime or provisioner. The server and sandbox use the
same Omnigent v0.15.0 release. The Sandbox has a 5 GiB
HOME claim, which survives idle suspension, and uses the cluster's normal
container runtime. This demo has no
warm pool or separate sandbox network policy.

The agent is a reusable template. Each managed session gets its own Sandbox
with a generated `omnigent-managed-*` name, rather than a fixed Sandbox bound
to the agent. New Sandboxes carry the label
`omnigent.ai/agent=automation-developer`.

From the repository root, build the sandbox image locally with:

```bash
podman build -f cluster/omnigent/image/Containerfile \
  -t omnigent-adt:local cluster/omnigent/image
```

`python3` remains the ADT image's Python; the `omnigent` command uses
`/opt/omnigent/bin/python`.

The `omnigent-dispatch` Automation Orchestrator workflow accepts a Forgejo
issue number, creates a managed session, and asks the agent to read that issue,
work on a branch, and open a PR. `forgejo-issue start` clones using Git askpass;
`forgejo-issue submit` pushes and creates or updates the open PR. Credentials do not
appear in Git URLs. A sidecar protects Omnigent's Route with the same machine
credential for inspection. `demo-goldenpath` can invoke the optional Backstage
templates, but AO's default issue workflow does not use them.

Check the resources with the selected kubeconfig:

```bash
oc -n omnigent rollout status deployment/omnigent
oc -n omnigent-sandboxes get builds,imagestream,sandboxes,pods
oc -n omnigent-sandboxes get sandboxes \
  -l omnigent.ai/agent=automation-developer
```

See [Omnigent's Kubernetes sandbox configuration](https://omnigent.ai/docs/reference/configuration/kubernetes)
for the provider's lifecycle and optional warm-pool settings.
