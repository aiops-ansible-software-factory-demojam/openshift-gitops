# Molecule tests from demo agent sandboxes

## Goal and scope

An agent in a demo Omnigent sandbox can run `molecule test` from a generated
Ansible collection's root. The provisioner clones an existing OpenShift CDI
golden image into a disposable KubeVirt VM, converges and verifies the role over
SSH, and removes the test resources.

- Target only the demo's Omnigent Agent Sandbox pods.
- Use an existing OpenShift VM template or CDI golden image.
- Share one dedicated `molecule-tests` namespace. YAML inventories use fixed VM
  names `instance` and `instance-rhel10`; collision risk is accepted temporarily.
- Guest OS images: existing CentOS Stream 10 and RHEL 10 CDI DataSources, each
  with a 30 GiB disk.
- Worktree: `/workspace/openshift-gitops-molecule-kubevirt`.
- Branch: `feature/sandbox-molecule-kubevirt`.
- Base: `origin/main` at `97f8eed`, after demo PR #10 merged.
- The user authorized rollout and live tests against `~/.kube/config` on
  2026-09-30. Other sessions' checkouts and Application revisions stay intact.

## Confirmed inputs

- The demo template currently selects Podman and pins
  `david_igou.molecule_provisioners` to `0.0.5-alpha` in `requirements.yml`.
- The provisioner's `0.0.5-alpha` source supports `PodIP` connections and
  `data_volume_source_ref` boot sources. Its dispatchers remain responsible for
  VM creation, SSH key injection, runtime inventory, preparation, and destruction.
- The existing lab golden path uses `PodIP` for in-cluster controllers. It avoids
  NodePort Services and cluster-wide node lookup.
- The published Omnigent `0.15.0` package supports
  `sandbox.kubernetes.secret_mounts` with `secret_name` and `mount_path` fields.
  Its sandbox builder explicitly disables automatic ServiceAccount token mounts.
  Changing the runner ServiceAccount alone therefore cannot enable API access.
- Read-only inspection of the workshop cluster found ready `centos-stream10`,
  `rhel10`, and `rhel9` DataSources in
  `openshift-virtualization-os-images`. All three currently reference snapshots.
- The local provisioner checkout is behind its cached `origin/main`; inspect the
  pinned release rather than copying the older checked-out defaults.

## Implementation sequence

1. **Select and describe the golden image.** Confirm the guest OS with the user.
   Prefer the provisioner's existing DataSource boot mode to processing an
   OpenShift Template unless the selected template has necessary custom behavior.
   Check source disk size, target storage class, required compute resources, and
   cloud-init/SSH compatibility. Reference the DataSource rather than its rotating
   snapshot name. Keep guest/image settings configurable in scenario inventory.

2. **Declare test access and infrastructure.** Add `molecule-tests` and a dedicated
   provisioner identity. Grant only the VM/VMI and CDI operations the pinned
   lifecycle needs in that namespace. Add the source-namespace CDI clone grant;
   check snapshot-backed DataSource authorization during preflight. Do not grant
   cluster-wide node access or general Secret access. Use the confirmed Omnigent
   Secret-mount interface for test credentials. Keep credential values outside
   Git; generate any kubeconfig at runtime with file references to the mounted
   token and CA. Keep test credentials separate from the operator's admin config.
   Add appropriate resource bounds for concurrent disposable guests.
   Verify the manifests render and the declared grants match the lifecycle.

3. **Prepare the sandbox runtime.** Ensure the ADT interpreter used by Ansible
   has the Kubernetes client and required SSH tools. Keep Omnigent's Python
   environment separate. Configure test credential paths and collection-root
   scenario discovery in the sandbox. Validate file access for its fixed non-root
  OpenShift-assigned UID. Bump the sandbox image tag consistently in the pipeline, config, and
   bootstrap if the image changes. Check the image tools and configuration locally.

4. **Update the collection golden path.** Move the exact provisioner pin into
   shared test requirements, centralize scenario configuration, and add the root
   Ansible configuration and Makefile expected by the provisioner guidance.
   Switch inventory to KubeVirt/DataSource/PodIP. Keep lifecycle operations in
   `david_igou.molecule_provisioners`, with no custom VM provisioner. Use the
   declarative YAML inventories with fixed hostnames. Serialize runs
   across the shared namespace until the provisioner supports run-scoped naming.
   Include dependency installation, idempotence, meaningful verification, and cleanup in the test
   sequence. Update the Devfile and collection instructions so plain
   `molecule test` works from the collection root in a demo sandbox.
   Lint and build a generated collection, and inspect its effective Molecule config.

5. **Validate the complete path when live testing is authorized.** Use a newly
   generated collection and a fresh managed sandbox. Confirm its identity can
   perform the declared lifecycle and is denied outside the intended namespaces.
   Run plain `molecule test`, then inspect the resulting test namespace directly
   with read-only `oc` commands. Confirm the guest was cloned from the selected
   DataSource and that VM, DataVolume, and PVC cleanup finishes. Test a failure
   followed by `molecule destroy`. Concurrent runs are deferred until
   provisioner-managed naming is implemented.
   Keep lifecycle evidence free of credentials. Do not use AAP templates to run
   verification and do not reset unrelated demo state.

6. **Document the supported workflow.** Update the sandbox and golden-path
   READMEs, including image/credential prerequisites and failed-run cleanup.
   Update the applicable note in a separate `igou-docs` worktree, likely
   `openshift/Using the Ansible Golden Path.md`, distinguishing this workshop demo
   from the existing lab Dev Spaces flow. Review the final diff and report which
   checks ran, which passed, and any live verification still outstanding.

## Expected file scope

- `cluster/omnigent/`: sandbox config, test credential mounts, runtime image,
  runtime initialization, and documentation.
- Test namespace, quota, provisioner credentials, and source-image clone RBAC
  registered in the existing Omnigent component.
- `cluster/forgejo/fixtures/collection-template/`: test requirements and shared
  config, YAML inventory, scenario, root tooling, Devfile, and docs.
- `cluster/rhdh/README.md` and bootstrap image/config prerequisites as needed.
- A relevant page in `igou-docs`, using an isolated worktree.

## Constraints

- Leave the other session's checkout, branch, credentials, and bootstrap run alone.
- Use `oc` and explicitly set `KUBECONFIG` for the workshop kubeconfig. Verify the
  active server and identity before cluster commands; name the target namespace.
- Do not copy the operator's admin kubeconfig into agent pods.
- Never print or commit credentials, tokens, raw kubeconfigs, or private SSH keys.
- Write YAML in block style and keep secret lookup logic outside roles.
- The shared test namespace does not prevent name collisions or provide security
  isolation between agent sessions that share the provisioner identity. Serialize
  runs across all sandboxes, collections, and scenarios using the fixed VM name.
- Handle a missing or unready source image, missing credentials, and denied clone
  permission with actionable errors before convergence.

## Local validation completed

The following validation preceded the switch back to YAML inventory. The six
Python inventory tests and simultaneous-run results below describe the removed
workaround, not the current fixed-name inventory.

- Built `localhost/demo-omnigent-molecule:centos10` from the changed Containerfile.
- Passed all six inventory identity/concurrency tests in
  `tests/test_molecule_inventory.py`.
- Accepted the sandbox config through the published Omnigent 0.15.0 parser.
- Loaded the token-file kubeconfig as UID 1000 without copying token values.
- Verified the native OpenCode environment preserves `KUBECONFIG` and
  `MOLECULE_GLOB`, and discovers the collection-root scenario.
- Passed dependency installation, syntax, production-profile Ansible lint,
  and collection build inside the candidate image with Molecule 26.9.0.
- Exercised a controller-side Ansible module through Molecule as UID 1000.
- Rendered the VM through the published provisioner's offline harness and
  validated it against the workshop cluster's installed KubeVirt v1 schema.
- Rendered the Omnigent component and app-of-apps, checked YAML and shell syntax,
  and verified the edited documentation note's metadata and wikilinks.

## Live rollout and validation (2026-09-30)

- Verified the workshop server selected by the supplied kubeconfig and its
  `admin` identity before rollout.
- Added a named Omnigent revision override to the root Application's existing
  Kustomize patches. Only Omnigent follows `feature/sandbox-molecule-kubevirt`;
  the other Applications remain on `feature/aap-config-seed`.
- Reconciled the Forgejo collection template through the sandbox's scoped Git
  identity, preserving the separate seeded collection and existing branches.
- Created `molecule_smoke_20260930` through the real Developer Hub scaffolder.
- Passed a full root-level `molecule test` in a managed sandbox after fixing the
  arbitrary-UID SSH failure. Omnigent overrides ADT's entrypoint, so the image
  now registers a missing UID in the existing writable passwd file at login.
- Passed two simultaneous full tests through native OpenCode's environment
  filter, creating different VMs from the CentOS DataSource in the shared
  namespace. Both runs passed convergence, idempotence, guest verification,
  and destruction.
- Deliberately failed convergence, observed its nonzero exit, then passed
  `molecule destroy` and confirmed removal of the VM, VMI, DataVolume, and PVC.
- Built and published the final v9 image from `ccea978`, digest
  `sha256:c91746c4730ee67b04e9dbc40247b48528f0af18785cbbdfce4027e7441c5644`.
  Rolled Omnigent to reload its subPath-mounted image configuration.
- Confirmed an unmodified v9 managed sandbox resolves UID `1000660000`, can
  invoke OpenSSH, and discovers the scenario through native OpenCode's filter.
  Its full root-level `molecule test` passed all lifecycle phases, and
  production-profile Ansible lint passed without warnings.
- Verified the test identity is denied VM creation in `webapp-vms`, Secret
  reads in the test namespace, and cluster-wide node access.
- Removed this session's earlier verification sandboxes and temporary build
  PVCs. A transient node DiskPressure condition cleared through kubelet garbage
  collection; no node configuration or taints were changed.

The existing seeded nginx collection has no Molecule scenario; the changed
scenario is supplied by the new-collection golden path. Already-generated
collections and older running sandboxes must be updated or recreated.

## Review follow-up — declarative inventory

At the user's request, restored `inventory/hosts.yml` with the fixed hostname
`instance`, removed the consumer-side Python inventory, its six tests, and the
run-ID cleanup task. Updated the operational and generated-collection guidance
to require serialized runs across the shared namespace; an overlapping run can
modify or delete another run's VM. Tracking provisioner-managed run naming in
[molecule_provisioners issue #59](https://github.com/david-igou/ansible-collection-molecule_provisioners/issues/59).

Fresh local checks passed: Ansible loaded `instance` and its KubeVirt group
variables, Molecule syntax passed, production-profile Ansible lint reported no
failures or warnings, and the materialized collection built successfully. The
latest YAML inventory has not been retested against the live cluster.

## Multiple OS-image scenarios

Goal: support CentOS Stream 10 and RHEL 10 CDI boot images using declarative
inventories and the existing provisioner lifecycle.

The user confirmed separate OS-image scenarios. Both have fixed VM names;
distinct agents running the same scenario can still collide.

1. Keep `default` on CentOS Stream 10 and add `rhel10`, reusing the lifecycle
   playbooks while declaring its own inventory and expected distribution facts.
2. Make preflight errors name the selected DataSource and make guest verification
   read expected OS facts from inventory. Add only `rhel10` to DataSource read RBAC.
3. Document `molecule test -s rhel10`, `make test`, and how to add another image;
   retain the accepted collision risk and requirement to serialize shared runs.
4. Validate both effective inventories, scenario syntax, guest-check behavior,
   lint, collection packaging, and the Omnigent render. Inspect source image
   readiness read-only; no live VM provisioning is part of this follow-up.

Read-only checks found both DataSources ready with 30 GiB source snapshots.

Validation passed for both scenarios: Ansible inventory and group-variable
resolution, `molecule syntax --all`, production-profile lint with no warnings,
collection build, and Omnigent render with the two-name DataSource read grant.
An offline container harness exercised the actual shared guest assertion with
six matching/mismatched distribution and major-version cases; all behaved as
expected. No live end-to-end run was performed for these scenarios.
