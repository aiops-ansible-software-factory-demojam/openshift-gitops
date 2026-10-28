# Current implementation and validation state

Updated 2026-10-28. This replaces the former instruction to use
`feature/stable-demo-rehearsal`. The conservative implementation was merged into
`main`; subsequent review and portability fixes remain in one ready PR per repository.
A Forgejo incident PR and a GitHub implementation PR have different purposes:
merging the demo fix does not merge these source PRs.

## Sources for the latest clean run

| Repository | Published ref | Tested source commit | Implementation PR |
| --- | --- | --- | --- |
| openshift-gitops | `fix/portable-collection-artifacts` | `685b62def393d9a6399483da915b14967001a890` | [#49](https://github.com/aiops-ansible-software-factory-demojam/openshift-gitops/pull/49) |
| demojam-ansible | `fix/ansible-review-contracts` | `d07b9171946df7a4cbf23b40350712574ac77a3b` | [#10](https://github.com/aiops-ansible-software-factory-demojam/demojam-ansible/pull/10) |
| demo.webapp | `fix/portable-collection-artifacts` | `2faf72ce8df18c27a6f48c003f137d9f24c720a1` | [#8](https://github.com/aiops-ansible-software-factory-demojam/ansible-collection-demo.webapp/pull/8) |
| demo.pythonapp | `fix/ansible-review-contracts` | `b01968d7b2c898af8281d316d90b480426fdbaec` | [#4](https://github.com/aiops-ansible-software-factory-demojam/ansible-collection-demo.pythonapp/pull/4) |

These are the executable source revisions tested before this documentation update.
Use the published refs above while those fixes are unmerged; selecting `main`
will not include open PR changes. Release examples and `seed.json` retain their
historical pinned defaults, so explicitly override every companion source ref.
The template source in this rehearsal was `main`. After implementation PRs merge,
select their merged refs together and perform a new rehearsal before claiming it
has been tested. Private credentials stay in the existing ignored `.env`.

## Observed result

The fresh AWS dual-application rehearsal on 2026-10-28 completed successfully.
Both AO and Omnigent used LiteLLM/MaaS `claude-haiku-4-5` with the chat protocol.
Reset took 10.2 minutes; bootstrap took 20.5 minutes; reset through final application
verification and incident closure took 66.8 minutes, including operator review.
These are observed timings, not deadlines or service guarantees.

- nginx: real 403 outage, alert/RCA/issue handoff, agent PR, independent build,
  install, production lint, five unit tests and fresh RHEL 9/10 Molecule tests;
  reviewed merge and one AAP recovery deployment; HTTP 200, SELinux Enforcing,
  and no active outage alert.
- Python: dependency observation, pinned Lightwell discovery, `app_patch` routing,
  agent release-manifest PR, trusted independent RHEL 9/10 acceptance, required
  status, human merge, native production approval, source/artifact-bound deployment,
  live version/checksum verification, normal/security regression checks and closure.
  The actual candidate changed the release manifest; existing automation and
  regression suites were reused, rather than claimed as newly agent-authored.

Two earlier attempts remain recorded as failures. The first completed Python but
rejected nginx's absolute source symlinks. Cache exclusions, packaging fixtures and
a pre-publication committed-tree guard address that fault. The next attempt stopped
on a Keycloak connect timeout; bounded read/pre-connection retries address it without
replaying uncertain writes. The third complete reset/test attempt passed both paths.
Runtime URLs, IDs, private receipts and detailed logs stay in ignored
`.rendered/rehearsals/`; no credentials or customer hostnames belong in diagrams.

## Current behavior and boundaries

- Separate `webapps` and `pythonapps` production groups and collection vars files.
- Lightwell discovery/assessment/release policy uses standard Ansible modules,
  including `uri`; public input contracts validate each role entry point.
- Controller evidence reads share a protected GET task while retaining source,
  template, project, approval and artifact checks.
- AAP reuses `invoice_promote` and its JTs with an immutable release contract;
  it does not generate resources per release.
- The CVE router supports `app_patch`, `contain`, `manual_review`, and `log_only`.
  Only the patch path was exercised live in the latest dual-app run. Alternative
  routing and containment guards have isolated fixture coverage, not a claimed
  live containment deployment. Containment remains vulnerable and causes an outage.
- New Molecule provisioning commands destroy owned guests before creating fresh
  ones. Idempotence is a second converge within that same test lifecycle.
  Interrupted cleanup preserves ownership records; do not delete state to hide it.
- Generated `collections/ansible_collections/` caches are ignored and excluded
  from artifacts. The PR helper rejects tracked caches and escaping symlinks;
  internal relative links and `collections/requirements.yml` remain valid.
- Native nginx promotion, a separate CI repair controller, agent callbacks and
  automatic repair after failed independent CI remain deferred. No Forgejo Actions
  runner is installed. nginx recovery uses the operator-controlled AAP wrapper;
  Python independent validation fails closed and cannot approve production.

Both incident triggers must run after the same reset/bootstrap. Failed attempts
must remain distinguishable from the clean run. The reset deletes disposable
Forgejo work and guests but preserves AAP and its history; bootstrap is required
again before incidents. No GitHub implementation PR is merged as a side effect.

See the [operator runbook](invoice-lightwell-demo.md),
[workflow definitions](../cluster/automation-orchestrator/workflows/README.md),
and [Draw.io architecture and workflows](diagrams/README.md).
