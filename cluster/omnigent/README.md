# Omnigent and Agent Sandbox

Omnigent serves the API in `omnigent` and uses the Red Hat Agent Sandbox
operator to create one `Sandbox` per managed session in `omnigent-sandboxes`.
The server ServiceAccount can manage Sandboxes, inspect their Pods, and create
short-lived launch-token Secrets only in that runner namespace. The runner has
no automatically mounted Kubernetes API token. Its fixed non-root UID uses the
`nonroot-v2` SCC. A dedicated test identity is mounted explicitly for Molecule;
it can manage test VMs only in `molecule-tests` and clone golden OS disks.

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
development commands. The image also installs the Kubernetes Python client
and configures root-level Molecule scenario discovery. The server and sandbox use the
same Omnigent v0.15.0 release. The Sandbox has a 5 GiB
HOME claim, which survives idle suspension, and uses the cluster's normal
container runtime. This demo has no
warm pool or separate sandbox network policy.

## KubeVirt Molecule tests

The new collection golden path uses `david_igou.molecule_provisioners` pinned to
`0.0.5-alpha`. From the generated collection root, an agent runs:

```bash
molecule test
```

Molecule installs test dependencies, clones the existing `centos-stream10` CDI
DataSource into a 30 GiB disk in `molecule-tests`, boots a two-vCPU/2 GiB VM,
converges over SSH to its pod IP, checks idempotence and the guest OS, then
destroys the VM. Inventory persists a random run ID for the entire lifecycle.
Independent sessions and scenarios cannot collide on VM names. The shared
namespace quota allows four VMs and 120 GiB of disk requests. This is shared test
access; it does not isolate sessions from each other by Kubernetes authorization.

`molecule-provisioner` is a separate ServiceAccount in `omnigent-sandboxes`.
Its controller-populated `molecule-provisioner-token` Secret is mounted read-only
at `/mnt/secrets/molecule` through Omnigent 0.15.0's `secret_mounts` configuration.
The login profile writes a mode-0600 kubeconfig into HOME with references to the
mounted token and CA files; it never copies token values into HOME.
`OMNIGENT_RUNNER_ENV_PASSTHROUGH` explicitly includes `KUBECONFIG` and
`MOLECULE_GLOB`, so native OpenCode tools retain the profile's test environment.
This explicit ServiceAccount token remains valid until revoked by deleting its
Secret or ServiceAccount. Credential values and the operator's admin kubeconfig
stay out of Git and out of the sandbox's configuration.

The test identity can create/update/delete VMs and create/delete DataVolumes in
`molecule-tests`, read VMIs there, read the CentOS DataSource, and request CDI
cross-namespace clones. It cannot read nodes, manage Services, fetch Secrets, or
manage VMs in application namespaces. CDI owns clone disks and Kubernetes garbage
collection removes them after VM deletion. Source-image updates can change the
DataSource's snapshot; the scenario references its stable DataSource name.

If a test fails or is interrupted, run `molecule destroy` in the same collection
and sandbox. Preserve its ephemeral state until cleanup succeeds. Serialize
runs of the same scenario in one checkout. A missing credential mount or an
unready DataSource must be resolved before testing. Existing generated
collections retain their previous scenarios; regenerate or update them to use
this setup. The fixture for the demo's separate existing collection is unchanged.

Read-only operator checks with the selected kubeconfig:

```bash
oc -n openshift-virtualization-os-images get datasource centos-stream10
oc -n molecule-tests get vm,vmi,datavolumes,pvc,resourcequota
oc -n molecule-tests get events --sort-by=.lastTimestamp
```

## Image and session lifecycle

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
