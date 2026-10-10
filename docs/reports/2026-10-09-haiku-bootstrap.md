# Haiku bootstrap and incident rehearsal — October 9, 2026

Bootstrap completed on the cluster in `~/.kube/config`, using the OpenCode Go subscription and `claude-haiku-5-5` for AO and Omnigent. The successful retry took **30m 55s**. From the first attempt through completion, including a transport correction and restart, setup took **38m 33s**.

The subsequent SELinux outage reached a tested Forgejo PR in **9m 17s**. Alerting, RCA, issue creation, the Forgejo webhook, EDA/AO, and the native agent handoff ran automatically. The session received one automatic task and no corrective human messages. At the end of that rehearsal, review had found an Ansible compatibility metadata mismatch, the PR remained open, and the application had been restored to the permissive demo baseline.

The later authorized merge test deployed the candidate to **RHEL 9.8** and verified **SELinux Enforcing, HTTP 200 and probe_success=1**. Merge to bootstrap's recovery verification took **9m 00.3s**; the additional persistent-label check completed after **9m 28.3s**. AAP emitted compatibility warnings because its Core 2.16.19 is older than the dependency's declared minimum. The SELinux behavior passed; supported version alignment remains unresolved.

This was one rehearsal and one subsequent merge test. They do not establish a repeatability rate. The older Qwen runs used different configuration and infrastructure; the time difference cannot be attributed to the model or dependency preloads alone.

## Configuration and source

The cluster was a fresh single-node OpenShift 4.22 installation with 32 CPUs, approximately 128 GiB RAM, a 99.4 GiB root filesystem, and external Ceph storage. Demo applications and AAP were installed by bootstrap. The interrupted attempt installed part of the stack, which the retry reused. This is not an uninterrupted cold-install benchmark.

GitOps ran at `b5638df73e53fef48205e21a2a538839e6f21057`; the collection source was `c78d4c8844477087e4499f1a342532bc2fb1f71b`, and the AAP/EDA source was `dff2e17460a4d5c584b2bb236068fd279257fb95`. All three used `feature/forgejo-eda-remediation`.

Today's private `.env` selected:

```bash
MODEL_PROVIDER=opencode-go
OPENCODE_GO_ENDPOINT=https://opencode.ai/zen/go/v1
OPENCODE_GO_MODEL=claude-haiku-5-5
OPENCODE_GO_PROTOCOL=anthropic
```

Bootstrap now supports the Anthropic transport through `@ai-sdk/anthropic` for OpenCode and an Anthropic backend in its pinned LiteLLM proxy for AO. The SDK takes the API base URL; the pinned proxy takes the full `/messages` URL. The [OpenCode Go documentation](https://opencode.ai/docs/go/) lists this model and transport. Credentials stayed in the ignored operator configuration and Kubernetes Secrets. The committed default remains Qwen.

## Bootstrap timing

The retry ran from **14:08:41 to 14:39:36 UTC**. Phase boundaries were observed passively within about one second. API job timings below are separate measurements and overlap these phases.

| Phase | Observed interval UTC | Approximate elapsed |
|---|---|---:|
| Inputs, GitOps checks, identity preparation | 14:08:41–14:09:15 | 34s |
| Application rollout, identity and Forgejo hydration | 14:09:15–14:20:31 | 11m 16s |
| Sandbox build and readiness checks | 14:20:31–14:24:43 | 4m 12s |
| AAP configuration and EDA readiness | 14:24:43–14:32:23 | 7m 40s |
| AO integration validation and workflow publication | 14:32:23–14:33:43 | 1m 20s |
| RHEL VM provisioning, including dependency refreshes | 14:33:43–14:35:56 | 2m 13s |
| Nginx installation, including dependency refreshes | 14:35:56–14:38:37 | 2m 40s |
| Webapp/probe checks and ending maintenance | 14:38:37–14:39:15 | 38s |
| Homepage accounts, rollout, widgets and OIDC checks | 14:39:15–14:39:36 | 21s |

The Tekton build itself took **3m 56s**, including **1m 45.5s** to install the pinned collections. AAP instance reconciliation took approximately **10m 36s**. The configuration job ran for **142.544s**, VM provisioning for **40.599s**, and nginx installation for **73.009s**. The first supported execution-environment image pull took **29.714s**.

A local OpenCode client built from the same image source answered the native smoke test in **3s**. AO's deployed question workflow answered in **21s**, including readiness, login and polling; its model activity took **11.083s**. These are request/activity latencies, not a Haiku output tok/s benchmark.

## Incident timing

The timer started immediately before `aap launch webapp_selinux_enable` at **14:39:54 UTC**. That command took **67s**, including project/inventory refreshes. The fault playbook itself ran for **6.334s**, and the independent probe returned HTTP 403 and `probe_success=0`.

| Milestone | UTC | Since break command |
|---|---|---:|
| Fault job finishes | 14:40:57.256 | 1m 03.3s |
| Alert begins pending | 14:41:12.675 | 1m 18.7s |
| Alert becomes firing | 14:42:12.675 | 2m 18.7s |
| EDA's AO webhook job is created | 14:43:28.334 | 3m 34.3s |
| RCA workflow starts | 14:43:35.939 | 3m 41.9s |
| Forgejo incident is created | 14:44:12 | 4m 18s |
| Remediation workflow starts | 14:44:20.805 | 4m 26.8s |
| AO completes native session handoff | 14:45:10.521 | 5m 16.5s |
| Agent starts the actual Molecule lifecycle | 14:47:07 | 7m 13s |
| Molecule log records completion | 14:48:43.247 | 8m 49.2s |
| Agent creates the tested PR | 14:49:11 | **9m 17s** |

The RCA workflow took **41.528s** overall; its model activity took **17.952s**. AAP audit collection ran for **5.882s**, issue creation for **6.382s**, and the Forgejo-triggered AO webhook job for **5.823s**. Backstage branch preparation took **3.173s**. Sending the task took **45.125s**, including sandbox startup/readiness. Handoff completion to PR creation was **4m 00.5s**.

The agent added a persistent `community.general.sefcontext` rule for the docroot, installed SELinux bindings/tools, refreshed facts, and ran `restorecon -R -v` with relabel-based change reporting. Its candidate is `2338a44a5c51f6086ef6ad2f46699ae003fd6448`.

Lint and collection build returned zero. `make molecule` ran the sole nginx scenario through dependency, syntax, create, prepare, converge, idempotence, verify and destroy, returning zero in approximately **96.2s**. Verification required Enforcing mode, `httpd_sys_content_t`, HTTP 200 and the nginx worker account. The second convergence reported `changed=0`; the test namespace was empty afterward. The live sandbox exposed all eight requested pinned collections through the configured search path.

## Interventions, recovery and review

- **Controlled bootstrap restart:** the first attempt started at 14:01:03 and was stopped after 379.04s, before demo jobs, to publish the verified proxy URL correction. The original pinned LiteLLM call returned 404 because it appended `/v1/messages` to a base URL already ending in `/v1`. The corrected full Messages URL passed a real provider call. No cluster objects were manually patched.
- **Automatic storage wait:** disk pressure appeared at 14:24:22 and cleared at 14:29:17. Bootstrap held the AAP launch until the node recovered. No manual image deletion or cleanup was needed.
- **Transient alert-ingestion failure:** Thanos Ruler's first send at 14:42:12 received HTTP 401 from Alertmanager. A later send succeeded automatically; the alert was active and unsilenced, and EDA continued. No credential edit or manual redelivery was performed. The cause of the first rejection was not established.
- **Agent recovery:** its first log redirection targeted root-owned `/tmp/opencode` and failed before Molecule started. It used `/tmp/omn-val` and completed one actual lifecycle. It also disabled hooks on its commit command, then checked that only sample hooks existed; no active check was bypassed.
- **Initial review blocker:** `galaxy.yml` adds `community.general >=13.5.0`, whose installed `meta/runtime.yml` requires Core >=2.18. The candidate's `meta/runtime.yml:2` and role README still advertised >=2.16. Tests used Core **2.21.4**, so they did not prove the advertised older compatibility. The merge test corrected those two declarations; it then exposed the older AAP runtime described below.

After initial review, `make webapp-nginx` and `make webapp-verify` restored and checked the original permissive baseline in **76s**. The candidate had not yet been merged or deployed. That healthy permissive baseline was not proof of the fix under Enforcing.

## Authorized merge and deployment test

The user then requested: “Test merging the PR and see if it resolves the issue.” The merge was performed through Forgejo; GitHub's integration PRs remain open. No new task or corrective message was sent to Omnigent.

Before merging, a human review edit raised `meta/runtime.yml` and the role README's Ansible minimum to 2.18 in `276b7beb7a76b5432f817718afb8ccf322f64d0f`. These were the only changes to the agent's tested candidate. Lint, collection build and a comparison with the installed dependency's minimum passed in **8.230s**. The earlier complete Molecule result remains evidence for the unchanged role; Molecule was not repeated for these two declarations.

The test first silenced WebappDown notifications and ran the existing fault job. AAP confirmed Enforcing and the independent probe returned **403/probe_success=0**. The verifier's nonzero exit was the expected reproduction result. The exact reviewed head was then guarded in the squash merge request. Forgejo merged PR #3 at **15:26:42 UTC** as `440af8c01fea2ff65314b7e13d753b15854db6c9`, closed issue #2, and removed the source branch.

| Phase | UTC | Elapsed |
|---|---|---:|
| Silence, fault-job refresh/launch, Enforcing check and expected failed HTTP check | 15:24:31.455–15:26:13.996 | 1m 42.541s |
| Corrected candidate lint/build/minimum check, overlapping reproduction | 15:25:13.715–15:25:21.944 | 8.230s |
| Guarded merge request and main/issue verification | 15:26:42.111–15:26:43.236 | 1.125s |
| Bootstrap nginx refresh and deployment | 15:26:43.257–15:30:10.975 | 3m 27.718s |
| Bootstrap enforcement refresh, independent mode/HTTP check and end of maintenance | 15:30:32.990–15:35:42.381 | 5m 09.391s |
| Additional independent persistent-label/domain check | 15:36:02.117–15:36:10.427 | 8.310s |

Reproduction through the final independent check took **11m 39.0s**. This includes review/tool gaps and a premature read-only check, rather than continuous unattended automation. The original incident-to-PR measurement ends at PR creation; the later merge test is a separate measurement after the human review wait.

Six project updates ran during deployment and re-enforcement. Their collection-fetch commands took **70.077s, 36.961s, 28.213s, 104.617s, 78.927s and 48.447s**, totaling **6m 07.244s**. The actual nginx job took **27.261s**, and the enforcement job took **8.439s**. Inventory and project update spans overlap; their durations must not be added to the fetch total. The [JSON evidence](evidence/2026-10-09/haiku-bootstrap.json) preserves every project/inventory/job interval.

All **14** cached nginx role and runtime metadata files matched the reviewed candidate by SHA-256. The deployment job recorded:

```text
Relabeled /web from unconfined_u:object_r:default_t:s0 to unconfined_u:object_r:httpd_sys_content_t:s0
Relabeled /web/index.html from system_u:object_r:default_t:s0 to system_u:object_r:httpd_sys_content_t:s0
```

The nginx playbook sets Permissive as a baseline pre-task, so its successful HTTP check alone was insufficient. The subsequent seeded enforcement job and independent checks established:

- `getenforce` returned **Enforcing** on RHEL 9.8.
- Nginx ran in `httpd_t`, with no `httpd_t` permissive exception; its worker ran as `nginx`.
- Both paths carried `httpd_sys_content_t`, and the local policy contained `/web(/.*)?` with that type.
- `restorecon -n -R -v /web` proposed no relabels.
- The origin probe returned **HTTP 200/probe_success=1**, and WebappDown had **zero active alerts**, including silenced alerts.
- All 15 Argo applications were Synced/Healthy, both EDA activations were running, and only the original Omnigent session existed.

One additional read-only guest check was queued too early. It ran at **15:35:00–15:35:05**, before the enforcement job finished at **15:35:25.998**, and correctly failed its Enforcing assertion. It was rerun successfully after completion. No guest files, contexts, cluster objects or credentials were manually patched; the two metadata edits, merge and seeded AAP launches were the human interventions.

The AAP job also warned that `demo.webapp` and `community.general` do not support its **Core 2.16.19** runtime. Raising the metadata minimum fixed the collection's declaration, not the execution environment. The runtime and dependency range need a supported alignment, and repository validation should check against AAP's actual version. The functional result does not establish general compatibility with Core 2.16.

The next delivery improvement is one human-launched recovery job that refreshes the merged artifact once, deploys it, and asserts Enforcing plus origin HTTP without the baseline's Permissive pre-task. Reusing that exact dependency cache for inventory updates would target the observed repeated fetches. A loaded-file digest check should remain part of validation so caching cannot silently deploy an older collection.

More node disk headroom should reduce the observed storage wait. A readiness check for authenticated alert ingestion could expose the transient 401 before a rehearsal. A generic validation check comparing production dependency requirements with the collection's declared Ansible minimum would catch the review blocker without prescribing the SELinux implementation.

The [timing evidence](evidence/2026-10-09/haiku-bootstrap.json) excludes runtime IDs, live hosts and credentials. The [prompt appendix](2026-10-09-haiku-prompts.md) preserves both smoke-test prompts and the session's single automatic task. Raw logs and session/tool records remain in ignored local artifacts.
