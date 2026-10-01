# Workshop rebuild and reset validation

Validated 2026-09-30–2026-10-01 on workshop `cluster-xr2gn`, identity `admin`,
using the user-supplied kubeconfig. Started from published main
`e1525afec51adbb31ba4b00dbb4e141aea32cd59`; small repairs were applied locally
as failures were found, then collected in this follow-up branch.

Three complete GitOps teardown/bootstrap/demo/reset cycles completed. An extra
demo workflow from a completed reset also passed, proving refreshed credentials
work for the next run. The first and third cycles needed the repairs below.

| Cycle | Teardown | Bootstrap | AAP VM/nginx | Issue-to-PR + sandbox | Reset baseline |
| --- | --- | --- | --- | --- | --- |
| 1 | Passed after teardown recovery | Passed after image recovery | Passed | Passed | Matched after repairs |
| 2 | Passed | Passed | Passed | Passed | Matched |
| 2 post-reset workflow | Existing baseline | Existing baseline | Passed | Passed | Matched again |
| 3 | Passed | Passed after Forgejo startup fix | Passed | Passed | Matched |

Each workflow provisioned `automation-demo` and a RHEL 9 `webapp` through the
existing managed AAP templates, configured nginx, and passed HTTPS and the
in-cluster blackbox probe. AO/Developer Hub created the issue feature branch;
Omnigent completed the requested README change and opened the expected Forgejo
PR against main with `Closes #1`. Verification required exactly one changed
file and exactly one requested sentence. Both CentOS Stream 10 Molecule
scenarios (`default` and `nginx`), lint and collection build passed inside the
managed Sandbox. RHEL 10 remained commented out in the YAML inventory.

| Workflow | AAP configuration / generic VM / webapp / nginx jobs | AO execution |
| --- | --- | --- |
| 1 | 5 / 14 / 20 / 26 | 447037d9-d1da-4f8b-b550-ee96cc7dfa40 |
| 2 | 5 / 14 / 20 / 26 | 736b111e-a319-4b12-8727-eae5b1e021ed |
| 2 post-reset | Existing configuration / 58 / 64 / 70 | ebbf5d36-bfc8-411c-9a71-90f99e1cc770 |
| 3 | 5 / 14 / 20 / 26 | 033b6a4e-3c50-4c2d-9c1f-a9bc793fd301 |

Reset was tested with both application VMs and a deliberately unfinished
Molecule VM. Three complete corrected reset invocations passed (cycle 2,
the post-reset workflow, and cycle 3). Their deletion/configuration job IDs
were 32/38/47, 76/82/91, and 32/38/47 respectively.

The semantic baseline compared AAP project settings, template targets,
credential/EE associations, inventory source and host/group configuration;
Forgejo main-only branches, no open PRs and exact repository file blobs;
no developer sessions, Sandboxes or managed home claims; no VM, VMI,
DataVolume or PVC in the three demo VM namespaces; and every GitOps app
Synced/Healthy. Generated IDs, timestamps and retained operational job/AO
execution history were excluded from configuration equality.

## Repairs and recovery

- Original reset returned success while leaving all three VMs. Reset now uses
  the seeded AAP deletion templates, foreground-deletes labelled Molecule VMs,
  verifies the VM namespaces are empty, and refreshes AAP after Forgejo reseeding.
- AAP dispatch rejected a duplicate credential association on rerun. Existing
  association is now checked before attachment. Cycle 1 reached its matching
  baseline after rerunning configuration with that repair.
- Cycle 3 hit HTTP 503 immediately after Forgejo Deployment readiness. Seeding
  now waits for the public version API before token checks or repository writes;
  the resumed bootstrap passed. A regression reproduces 503 followed by 200.
- Cycle 1 had a terminal Failed/Evicted CentOS importer after DiskPressure.
  Deleting only that failed importer let CDI retry. Bootstrap now gates actual
  guest-image readiness. Pressure recurred in cycles 2/3 and cleared naturally.
- Cycle 1 recovered an orphan default Argo CD finalizer after its operator was
  removed. Corrected teardown ordering completed cycles 2/3 without recovery.
- The extra workflow initially ran lint before dependencies were installed.
  Running Molecule first exercised automatic dependency installation in a fresh
  home directory; both scenarios and subsequent lint/build passed.

Workshop base OpenShift/storage/registry inputs and the externally supplied
Keycloak database, TLS and realm state were retained. This tests the current
repository's bootstrap boundary. Ownership/bootstrap of those Keycloak inputs
is tracked in [#17](https://github.com/aiops-ansible-software-factory-demojam/openshift-gitops/issues/17);
workshop capacity and evicted CDI import recovery are tracked in
[#18](https://github.com/aiops-ansible-software-factory-demojam/openshift-gitops/issues/18).

## Subsequent command/preflight validation

After the three cycles, #13/#12 were implemented. The read-only live preflight
reported zero required failures; both installed readiness gates passed.
Twenty credential-free/synthetic regression tests passed, including kubeconfig
precedence/lists/spaces, malformed ZIP/JSON/RHEL material, absent installed-later
APIs, metadata-only Secret requests, bootstrap stopping before mutation, safe
Make help and issue validation/hydration sequencing. Shell syntax, ShellCheck
and diff whitespace checks passed; the documented `make render` succeeded.
The shared parser preserved the existing runtime selection on the real manifest
without printing material, and the final configuration baseline still matched.
Help/quickstart cover existing commands and
preflight; #14's local validation workflows remain deferred.
