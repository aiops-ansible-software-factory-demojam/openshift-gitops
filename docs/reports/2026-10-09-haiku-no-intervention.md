# Haiku end-to-end run with a test-gated merge — October 9, 2026

Haiku completed the automatic outage-to-PR path with one task and no operator follow-up. The operator merged the published commit only after independent lint, collection build and the complete Molecule lifecycle passed. **One nginx recovery job then restored HTTP service with SELinux still Enforcing.** No second enforcement job was needed.

PR creation took **7m56.423s** from the fault launch. Fault launch through completed live verification took **18m15.402s**. Reset through completed verification took **45m55.313s**.

The automatic agent flow was unassisted. The operator did correct an independent test-runner layout error and two read-only observation assumptions. This was not an operator-error-free rehearsal. No candidate edit, code review, corrective prompt, manual dispatch, compaction, flow replay or guest/cluster repair occurred. The failed operator test attempt is retained and described below.

The [prompt appendix](2026-10-09-haiku-no-intervention-prompts.md) preserves the submitted messages with redactions. The [JSON evidence](evidence/2026-10-09/haiku-no-intervention.json) contains clocks, job IDs, test results, model usage and corrections. The new [run-demojam skill](../../.agents/skills/run-demojam/SKILL.md) gives future operators the same sequence and merge gate.

## Setup and scope

All cluster commands used `~/.kube/config`. The model was OpenCode Go `claude-haiku-5-5` using the Anthropic protocol. A real provider completion succeeded before reset. Post-bootstrap checks confirmed the selected model, SDK and credential; native request records also identify Haiku.

The operator ran `bootstrap.sh demo-reset --confirm-demo-reset`, then full `bootstrap.sh`, once each. The reset removed disposable repositories/data, sessions, demo/test VMs and disks, reseeded the unfixed collection, and preserved the AAP instance and PVC identities. Installed OpenShift services and the cached sandbox image were reused. This was a warm reset and bootstrap, not a new cluster installation.

The published sources on `feature/forgejo-eda-remediation` were GitOps `d46b21a`, collection `c78d4c8`, and AAP/EDA content `c557ad5`. Reset had started from GitOps `3a2901e`; the intervening commits added operator documentation, not bootstrap behavior. The skill was refined after the isolated runner error during this test. No bootstrap implementation or automatic remediation prompt changed during the incident.

Bootstrap provisioned the VM, ran the separate `webapp_selinux_permissive` job, then installed nginx. Independent baseline checks found RHEL 9.8, SELinux Permissive, `/web` and its index labeled `default_t`, HTTP 200, probe success, no outage alerts, 15 synchronized healthy applications, two running EDA activations, and no incident session or old PR. The nginx deployment playbook preserved the existing SELinux mode.

## Overall timing

All clocks are UTC. The 30-minute allowance covered fault launch to an eligible agent PR. Operator validation, merge and recovery were timed separately.

| Stage | Start | Finish | Duration |
|---|---|---|---:|
| Demo reset | 21:28:53.665 | 21:43:52.315 | 14m58.650s |
| Full bootstrap | 21:43:55.961 | 21:55:14.581 | 11m18.620s |
| AO readiness command | 21:55:41.731 | 21:56:02.945 | 21.214s |
| Fault launch command | 21:56:33.576 | 21:57:39.744 | 1m06.168s |
| Automatic RCA workflow | 21:59:29.105 | 22:00:08.232 | 39.127s |
| Forgejo-to-agent workflow | 22:00:10.069 | 22:00:34.498 | 24.429s |
| Fault launch to completed handoff | 21:56:33.576 | 22:00:34.498 | 4m00.922s |
| Completed handoff to PR creation | 22:00:34.498 | 22:04:30.000 | 3m55.502s |
| Fault launch to PR creation | 21:56:33.576 | 22:04:30.000 | 7m56.423s |
| Independent validation, corrected runner | 22:08:15.687 | 22:09:56.508 | 1m40.821s |
| Guarded merge command | 22:10:15.863 | 22:10:17.527 | 01.663s |
| One recovery launch command | 22:10:20.379 | 22:13:21.761 | 3m01.383s |
| Read-only Enforcing/HTTP verification | 22:13:48.193 | 22:14:10.637 | 22.444s |
| Fault launch to full live proof | 21:56:33.576 | 22:14:48.978 | 18m15.402s |
| Reset start to full live proof | 21:28:53.665 | 22:14:48.978 | 45m55.313s |

The end-to-end finish uses completed collection of all live assertions at **22:14:48.978**, rather than the final collector's start at 22:14:29.060. Whole-run timings include API calls, polling, diagnosis and observation gaps. Reset and bootstrap were separated by 3.646s. Backstage became ready 140s after its replacement pod was created; plugin initialization took 72s and RAG initialization 11s, overlapping other reset work.

## AAP jobs and automatic handoff

The fault job switched the guest to Enforcing. A read-only guest command confirmed that state, and a separate probe returned HTTP 403. The app was still HTTP 403 immediately before merge, so the sandbox test had not repaired the application VM.

Thanos Ruler recorded the alert's pending start at **21:58:12.675**. The corrected observer first saw it firing at **21:59:34.563**. That is an observation time, not the exact firing transition: the original connection had targeted a server that did not evaluate this rule.

Issue #2 was created at **22:00:03** with RCA. Its Forgejo webhook reached the new EDA listener, which launched AO's remediation workflow. AO prepared the branch, created/shared an Omnigent session and sent the task. Handoff completed at **22:00:34.498**. It did not wait for the fix to finish.

| AAP job | Purpose | Actual start | Actual finish | Job duration |
|---:|---|---|---|---:|
| 298 | `webapp_vm` | 21:32:38.156 | 21:32:56.678 | 18.522s |
| 304 | `openshift_virtualization_machine` | 21:35:50.085 | 21:35:57.998 | 7.913s |
| 311 | `aap_configure_all` | 21:41:35.451 | 21:42:59.774 | 84.323s |
| 322 | `aap_configure_all` | 21:47:05.619 | 21:48:49.283 | 103.664s |
| 332 | `webapp_vm` | 21:50:10.360 | 21:51:01.223 | 50.863s |
| 338 | `webapp_selinux_permissive` | 21:51:57.274 | 21:52:05.340 | 8.066s |
| 344 | `webapp_nginx` | 21:53:03.068 | 21:54:17.390 | 74.322s |
| 351 | `webapp_selinux_enable` | 21:57:28.663 | 21:57:34.717 | 6.055s |
| 353 | `call_ao_webhook` | 21:59:23.520 | 21:59:29.542 | 6.023s |
| 354 | `pull_audit_logs` | 21:59:30.084 | 21:59:35.595 | 5.511s |
| 355 | `webapp_alert_issue` | 21:59:57.271 | 22:00:04.342 | 7.072s |
| 356 | `call_ao_webhook` | 22:00:04.783 | 22:00:10.564 | 5.781s |
| 362 | `webapp_nginx` | 22:12:54.346 | 22:13:18.848 | 24.502s |

Jobs 298 and 304 were reset VM cleanup; 311 configured AAP after reseeding. Jobs 322, 332, 338 and 344 were full bootstrap. Job 351 was the single fault launch. Jobs 353–356 were the automatic incident path. **Job 362 was the only application recovery job after merge.** Read-only ad hoc commands 345, 352, 363 and 364 checked guest state; they did not change it.

| Workflow | Activity | Start | Duration |
|---|---|---|---:|
| RCA | `alertmanagereda` | 21:59:29.312 | 0.008s |
| RCA | `auditlogs` | 21:59:29.472 | 11.030s |
| RCA | `airca` | 21:59:40.615 | 15.610s |
| RCA | `createissue` | 21:59:56.506 | 11.704s |
| Remediation | `forgejo_issue` | 22:00:10.223 | 0.010s |
| Remediation | `prepare_feature` | 22:00:10.257 | 3.153s |
| Remediation | `authenticate_omnigent` | 22:00:13.489 | 0.031s |
| Remediation | `create_session` | 22:00:13.541 | 0.700s |
| Remediation | `share_session_0` | 22:00:14.269 | 0.130s |
| Remediation | `send_task` | 22:00:14.425 | 20.052s |

## Agent and independent validation

One session received one automatic task. The existing task included the RCA and collection/test instructions; it was not changed for this run. Haiku ran lint and built the collection successfully. Its first Molecule launch tried to redirect output into `/tmp/opencode/molecule-run1.log` and failed with permission denied before Molecule executed. Haiku changed its own log destination and completed the full test in 111.241s without operator feedback.

| Actor | Check | Start | Duration | Result |
|---|---|---|---:|---|
| Agent | `scoped_lint` | 22:02:09.243 | 5.983s | Passed |
| Agent | `collection_build` | 22:02:16.633 | 0.477s | Passed |
| Agent | `molecule` | 22:02:19.321 | 0.060s | Log redirection failed before Molecule ran |
| Agent | `molecule` | 22:02:20.790 | 111.241s | Passed |
| Independent | `scoped_lint` | 22:08:16.300 | 4.533s | Passed |
| Independent | `collection_build` | 22:08:20.833 | 0.515s | Passed |
| Independent | `all_molecule` | 22:08:21.348 | 95.110s | Passed |

The successful native lifecycle finished at **22:04:12.031**. PR #3 was published 17.969s later at `adaadce319ecee36d48a373398f81926ba8a300c`. The session became idle with no pending request or tool before independent testing.

The first independent attempt used a temporary `git archive` export at the first collection installation path. Lint and build reported success, but Molecule's dependency self-install deleted that source directory and then failed to read it. No scenario lifecycle completed. The final hash capture also raised a missing-file error, so that attempt did not produce a complete exit-status record and did not authorize a merge. Its observed window was 22:05:22.410–22:05:31.052; those are file-record/return observations, not exact per-check clocks.

The operator corrected only the runner's layout: the immutable source export and temporary collection installation root were separated. The commit, test files and dependencies were unchanged. The interval from the first runner exception to corrected validation start was **2m44.635s**, including diagnosis and the skill update. That failed attempt is explicitly retained in the evidence.

The corrected gate captured each real command status separately. All three were zero; `make molecule` completed dependency, syntax, create, prepare, converge, idempotence, verify and destroy. All 40 tracked file hashes and the published export remained unchanged. This evidence authorized the merge; no proposed source or diff was reviewed.

## Merge and live recovery

The operator sent one squash-merge request guarded by the tested head and unchanged base. Forgejo confirmed main at `8431df4cb7043c53f98ce75f8111565f5ebd1630`, PR #3 merged, issue #2 closed, and the source branch deleted.

The operator then launched `bootstrap.sh webapp nginx` once. The command took 181.383s; the actual nginx job took 24.502s. The separate post-provisioning Permissive playbook was not rerun. No post-deployment SELinux-enable job was launched.

Read-only verification found SELinux Enforcing, nginx running in `httpd_t`, no permissive httpd domain, `httpd_sys_content_t` on both served paths, a persistent `/web(/.*)?` file-context entry, and no changes requested by a dry-run relabel. AAP's cached role/runtime artifact matched all 14 expected file hashes from the tested commit. The HTTPS route redirected unauthenticated users to the demo identity provider, and the internal blackbox probe returned HTTP 200 with success one.

Final checks found zero `WebappDown` alerts, including silenced/inhibited/unprocessed alerts, all 15 applications synchronized and healthy, both EDA activations running, and one idle session. Alert handling remained normal throughout the incident and recovery; no maintenance silence was applied after bootstrap.

## Corrections, usage and next improvements

Four operator issues are disclosed:

1. Before reset, the provider preflight used urllib's default User-Agent and received an edge HTTP 403. The existing demo client User-Agent and session header produced a successful completion. Credentials and application code were unchanged.
2. The read-only alert observer initially connected to Prometheus instead of Thanos Ruler. Reconnecting corrected timing observation without changing the alert flow. The exact first firing transition was not captured.
3. A read-only dependency-location check incorrectly expected the provisioner under the home collection path. It was already preloaded under the system path included in the native search path; no installation was made.
4. The isolated test runner placed source and install paths together. Separating them allowed the unchanged published head to pass. This is an operator test-harness correction, not a clean first-attempt independent pass.

The skill now requires separate source/install paths, a clean published head, actual command statuses, the complete lifecycle, a guarded merge and one recovery launch. Candidate assertion/lint/build failures stop the merge. An operator runner failure before scenario execution may be corrected only outside the candidate, preserving tests and dependencies, with the failed attempt disclosed. Coaching, candidate edits, code review and runtime repairs remain prohibited.

Native usage recorded 24 assistant responses and 28 tool calls, with 50 uncached input tokens, 64,685 cache-write input tokens, 1,031,580 cache-read input tokens and 10,167 output tokens. No quota errors or child sessions were recorded. These are provider-reported cumulative counters, not unique context or billing. No separate streaming benchmark was run; this rehearsal does not establish provider decoding tokens/s.

The largest measured recovery cost was refresh work: three collection fetches consumed **118.648s**, compared with **24.502s** for the actual application job. Refreshing the exact merged collection once and reusing its verified revision across inventory/job launches could remove duplicate work. Any reuse must check the collection revision, because its source can change without changing the caller's AAP project revision. The observed cost is a target, not a guaranteed saving.

The runner layout correction is already incorporated in the skill. A repeat using that layout should avoid this run's 2m44.635s diagnosis gap. Documenting a writable log location could also avoid Haiku's failed launch without prescribing its root-cause fix. The corrected independent functional test still took 95.110s; faster model responses alone cannot remove VM test and AAP refresh time.

This run demonstrates the intended automatic handoff, test-gated operator merge and one-job Enforcing recovery. It does not establish a repeatability rate, and the operator test runner needed one correction.

## Publication checks

The report and prompt appendix omit credentials, live hostnames, runtime IDs and native assistant reasoning. Raw logs, source exports and environment backups remain ignored and private. JSON, local links, skill metadata and known-credential patterns were checked before publication. The exact known-credential history scan found no matches; no history rewrite was needed. Its scope is supplied/current keys and retained operator/Forgejo credentials in locally reachable Git blobs, not exhaustive detection of unknown historical secrets.
