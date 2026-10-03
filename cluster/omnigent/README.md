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
container runtime. A login profile registers OpenShift's assigned UID in the
ADT image's writable passwd file, allowing OpenSSH and Ansible to resolve the
sandbox user and HOME. This demo has no
warm pool or separate sandbox network policy.

The image includes Make, ripgrep, process utilities, and the collection's pinned
Ansible lint, YAML lint, and pre-commit packages. Bootstrap reads
`.pre-commit-config.yaml`, `requirements-dev.txt`, and
`extensions/molecule/requirements-test.yml` from the collection branch selected
by `ANSIBLE_COLLECTION_DEMO_WEBAPP_BRANCH`, resolving it to a commit before
launching the build. Tekton fetches that exact commit and uses bootstrap to
generate the ignored `image/dev-tools/` build context. These inputs prebuild
the isolated hook environments and install the real
Molecule collection dependencies. A new sandbox HOME receives a writable cache
database pointing to the image's hook environments and its own copy of the test
collections. Existing caches are preserved.

From a collection checkout, continue to run `make hooks`, `make lint`, and
`make build`. Git hooks and the source namespace are installed per checkout;
the image supplies cached packages and environments. `PIP_FIND_LINKS` points
project virtual-environment installs at the image's wheel directory. Repository
requirements remain authoritative: new versions can install normally when they
differ from the image cache. Update tooling only in the collection repository;
the image build reads those files rather than maintaining copies in GitOps.
The selected branch must contain all three tooling files.
The runner's explicit environment passthrough includes `PIP_FIND_LINKS`, so
native OpenCode commands can use those cached wheels too.

## KubeVirt Molecule tests

The new collection golden path uses `david_igou.molecule_provisioners` pinned to
`0.0.5-alpha`. From the generated collection root, an agent runs:

```bash
molecule test
```

Molecule installs test dependencies and provisions `centos-stream10` from the
shared YAML inventory, cloning its CDI DataSource. The VM gets a 30 GiB disk
in `molecule-tests`, two vCPUs, and 2 GiB RAM. The default scenario prints hello
world, checks idempotence, SSH connectivity and the expected guest OS, then
destroys the VM. Preflight checks its DataSource before provisioning. The
`rhel10` inventory entry is commented out until RHEL package repository
prerequisites are configured.
Shared lifecycle and host-verification playbooks live in `utils/playbooks/`.
Each scenario needs only `molecule.yml`, `converge.yml`, and `verify.yml`; shared
`config.yml` provides inventory and lifecycle paths.
The declarative YAML inventory uses the fixed VM name `centos-stream10`. Collision risk is accepted temporarily: serialize runs
across all demo sandboxes, collections, and scenarios sharing `molecule-tests`.
Overlapping runs can modify or delete each other's VM. The shared namespace
quota allows four VMs and 120 GiB of disk requests; it does not make concurrent
runs safe or isolate sessions from each other by Kubernetes authorization.
Provisioner-managed run naming is tracked in
[molecule_provisioners issue #59](https://github.com/david-igou/ansible-collection-molecule_provisioners/issues/59).

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
`molecule-tests`, read VMIs there, read the CentOS Stream 10 / RHEL 10 DataSources,
and request CDI cross-namespace clones. It cannot read nodes, manage Services, fetch Secrets, or
manage VMs in application namespaces. CDI owns clone disks and Kubernetes garbage
collection removes them after VM deletion. Source-image updates can change the
DataSource's snapshot; the scenario references its stable DataSource name.

If a test fails or is interrupted, run `molecule destroy` in the same collection
once no other run is using the test VM. A missing credential mount or an
unready DataSource must be resolved before testing. Existing generated
collections retain their previous scenarios; regenerate or update them to use
this setup. The seeded collection is now `demo.webapp` in the existing
`demo-owner/ansible-collection-demo.webapp` repository. Its default scenario prints
hello world, and `molecule test -s nginx` installs `demo.webapp.nginx` and
verifies HTTP service and the nginx worker account. `make test` runs both
scenarios sequentially from the collection root.

Read-only operator checks with the selected kubeconfig:

```bash
oc -n openshift-virtualization-os-images get datasource centos-stream10 rhel10
oc -n molecule-tests get vm,vmi,datavolumes,pvc,resourcequota
oc -n molecule-tests get events --sort-by=.lastTimestamp
```

## Image and session lifecycle

The demo uses one mutable `omnigent-opencode:latest` image. Its reference in
`omnigent-sandbox-config-configmap.yaml` also drives bootstrap's existence check
and the Tekton build destination. Omnigent 0.15.0 omits the container pull policy;
Kubernetes defaults new containers using `:latest` to `Always`, including the
workspace init container. The registry is checked at each container start,
while unchanged image layers can still be reused from the node cache.

The agent is a reusable template. Each managed session gets its own Sandbox
with a generated `omnigent-managed-*` name, rather than a fixed Sandbox bound
to the agent. New Sandboxes carry the label
`omnigent.ai/agent=automation-developer`.

Bootstrap builds this image with a one-off Tekton run. Buildah keeps its layers
on a temporary PVC to avoid filling the SNO node disk. To rebuild explicitly:

```bash
make sandbox-build
```

Publish image source changes before building; the script builds the checked-out
Git commit unless `SANDBOX_BUILD_REVISION` selects another published revision.
Wait for the build to succeed, then start a fresh demo session. Successful runs
report `IMAGE`, `IMAGE_DIGEST`, `SOURCE_COMMIT`, and `COLLECTION_SOURCE_COMMIT`.
The image records its collection source in `/opt/demo-dev/collection-source.json`.
A failed build stops bootstrap
before dispatch; inspect that PipelineRun before trying again. This mutable tag
does not provide automatic rollback or preserve the previous registry mapping
if a push completes before a later failure.

Bootstrap removes terminal runs' temporary build pods and workspace PVCs while
retaining the PipelineRun results. PVC cleanup uses the owning run's UID because
Tekton does not put the PipelineRun label on generated workspace claims.
Active builds and session HOME claims are preserved.

Bootstrap reuses the tag when it exists, the latest successful build used the
selected collection commit, and the image, pipeline, and bootstrap inputs are
unchanged. Changes to the selected collection branch invalidate the cache.
`BOOTSTRAP_FORCE_SANDBOX_BUILD=true` rebuilds
and overwrites the same tag, allowing refreshed downloaded dependencies without
a version bump. No image tag edits or Omnigent server restart are needed after a
rebuild. The initial switch to `:latest` changes the subPath-mounted config;
bootstrap reloads the server when its mounted image reference differs.

Running containers keep their current image. New or restarted containers,
including a session resumed after suspension, can use a newer build. Existing
Sandbox templates with the old versioned tag keep their original selection;
start a fresh session to switch to this policy. Do not rebuild during an active
demo run if it must keep one image version throughout.

To inspect image selection and the actual defaulted pull policies:

```bash
oc -n omnigent-sandboxes get imagestreamtag omnigent-opencode:latest
oc -n omnigent-sandboxes get pods -l omnigent.ai/agent=automation-developer \
  -o json | jq '.items[] | {pod: .metadata.name, containers: [.spec.initContainers[], .spec.containers[]] | map({name, image, imagePullPolicy})}'
```

For local image development:

```bash
make sandbox-image-context
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
credentials out of Git URLs. Browser login uses native OIDC against
[demojam-keycloak](../demojam-keycloak/README.md), with verified email identities
and per-user session permissions. Omnigent has no proxy sidecars. AO obtains a
native bearer token from `/oauth/token` using client credentials and grants each
enabled configured user read access to new workflow sessions. Reset uses that
same token endpoint. Direct Keycloak access tokens are not Omnigent API tokens.
Configured `demo-admins` emails populate the native admin roster; removal from
that roster does not automatically demote an existing Omnigent administrator.

Check the resources with the selected kubeconfig:

```bash
oc -n omnigent rollout status deployment/omnigent
oc -n omnigent-sandboxes get pipelineruns,imagestream,sandboxes,pods
oc -n omnigent-sandboxes get sandboxes \
  -l omnigent.ai/agent=automation-developer
```

See [Omnigent's Kubernetes sandbox configuration](https://omnigent.ai/docs/reference/configuration/kubernetes)
for the provider's lifecycle and optional warm-pool settings.
