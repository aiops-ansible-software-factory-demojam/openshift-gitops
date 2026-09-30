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
`demo-goldenpath` helper. The Ansible tools supply
development commands; running container or VM tests still needs a test target
and its corresponding runtime or provisioner. The server and sandbox use the
same Omnigent v0.15.0 release. The Sandbox has a 5 GiB
HOME claim, which survives idle suspension, and uses the cluster's normal
container runtime. This demo has no
warm pool or separate sandbox network policy.

The Sandbox Pod uses `IfNotPresent` image pulls. Bump the ImageStreamTag in
the Tekton pipeline, sandbox config, and bootstrap together when changing `image/`,
so new sessions cannot reuse a node-cached older image under the same tag.

The agent is a reusable template. Each managed session gets its own Sandbox
with a generated `omnigent-managed-*` name, rather than a fixed Sandbox bound
to the agent. New Sandboxes carry the label
`omnigent.ai/agent=automation-developer`.

Bootstrap builds this image with a one-off Tekton run. Buildah keeps its layers
on a temporary PVC to avoid filling the SNO node disk. To rebuild explicitly:

```bash
bash bootstrap/sandbox-image.sh
```

For local image development:

```bash
podman build -f cluster/omnigent/image/Containerfile \
  -t omnigent-adt:local cluster/omnigent/image
```

`python3` remains the ADT image's Python; the `omnigent` command uses
`/opt/omnigent/bin/python`.

The `omnigent-dispatch` Automation Orchestrator workflow accepts a Forgejo
issue number and waits for the Backstage feature template to create its branch
before creating a managed session. The agent uses `demo-goldenpath checkout`
to fetch that existing branch, then `demo-goldenpath pr` to push and open or
update the PR. The helper cannot create the feature branch. Git askpass keeps
credentials out of Git URLs. A sidecar protects Omnigent's Route with the
same machine credential for inspection.

Check the resources with the selected kubeconfig:

```bash
oc -n omnigent rollout status deployment/omnigent
oc -n omnigent-sandboxes get pipelineruns,imagestream,sandboxes,pods
oc -n omnigent-sandboxes get sandboxes \
  -l omnigent.ai/agent=automation-developer
```

See [Omnigent's Kubernetes sandbox configuration](https://omnigent.ai/docs/reference/configuration/kubernetes)
for the provider's lifecycle and optional warm-pool settings.
