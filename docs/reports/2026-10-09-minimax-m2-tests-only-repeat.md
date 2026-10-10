# MiniMax repeat with merge on test success — October 9, 2026

MiniMax submitted PR #3 without a human follow-up. The operator merged its published commit after independent lint, build and the full Molecule lifecycle passed, without reviewing the code. The merged fix then passed live RHEL checks with SELinux Enforcing, persistent file contexts, HTTP 200 and no outage alerts.

Recovery required **two human jobs**. The nginx job applied the correct persistent policy and labels but left SELinux Permissive. The operator ran the existing SELinux-enable job before claiming recovery. The automatic incident-to-PR path worked; recovery through one human job remains unverified.

The complete incident took **36m53.859s**, including independent testing, the operator's test-runner correction, a cluster API transient and the extra enforcement job. Reset through final verification took **58m23.854s**. The agent published its PR after **21m54.654s**, within the 30-minute incident-agent allowance. That allowance covered the automatic incident and agent-to-PR work; human testing, merge and recovery were timed separately.

The [prompt appendix](2026-10-09-minimax-m2-tests-only-prompts.md) preserves the automatic task and readiness/benchmark prompts. The [JSON evidence](evidence/2026-10-09/minimax-m2-tests-only-repeat.json) records clocks, validation results, interventions and reported usage. All times below are UTC.

## Scope and model selection

This run followed the [first MiniMax repeat](2026-10-09-minimax-m2-repeat.md), whose PR had been returned for revision. While the next reset was running, the operator changed the instruction: do not review code, merge if tests pass, and repeat with MiniMax. The planned Qwen 235B incident was replaced. Qwen 235B passed provider and streaming checks but did not run a demo.

The already-running reset had loaded Qwen 235B configuration. No incident or session ran with it. MiniMax was selected before the complete bootstrap, and checks confirmed `demo/minimax-m2`, the expected native SDK, and a credential matching `/workspace/scratch/litellm2.txt`. Native request records also identify `minimax-m2`.

All cluster commands used `~/.kube/config`. `bootstrap.sh demo-reset --confirm-demo-reset` removed the old session, application and test VMs, disks and Forgejo data, then reseeded the unfixed repository. The AAP instance and PVC identities were retained and checked. The complete `bootstrap.sh` then provisioned the demo. This was a warm reset and bootstrap, not a new OpenShift installation.

Sources were GitOps `3a7d72b`, collection `c78d4c8`, and AAP/EDA content `dff2e17`, on `feature/forgejo-eda-remediation`. The preloaded sandbox image was reused. No tracked implementation or bootstrap logic changed for this run. The unfixed collection baseline remained on the GitHub feature branch; the generated fix was merged in Forgejo.

Before the fault, independent checks found RHEL 9.8 Permissive, `/web` and its index labeled `default_t`, HTTP 200, probe success, zero outage alerts, 15 synchronized healthy applications, two running EDA activations and no session. AO answered its readiness prompt successfully.

## Overall timing

| Stage | Start | Finish | Duration |
|---|---|---|---:|
| Demo reset | 19:41:13.351 | 19:51:19.587 | 10m06.236s |
| Reset-to-bootstrap observation gap | 19:51:19.587 | 19:51:31.566 | 11.979s |
| Complete bootstrap | 19:51:31.566 | 20:01:35.300 | 10m03.734s |
| Reset start to bootstrap finish | 19:41:13.351 | 20:01:35.300 | 20m21.949s |
| AO readiness command | 20:02:21.097 | 20:02:31.467 | 10.370s |
| Fault launch command | 20:02:43.346 | 20:04:55.620 | 2m12.274s |
| Actual fault job | 20:04:44.569 | 20:04:50.400 | 5.830s |
| Automatic RCA workflow | 20:06:29.033 | 20:07:09.861 | 40.828s |
| Forgejo-to-agent AO workflow | 20:07:12.633 | 20:07:42.842 | 30.209s |
| Fault launch to completed handoff | 20:02:43.346 | 20:07:42.842 | 4m59.495s |
| Handoff to PR creation | 20:07:42.842 | 20:24:38 | 16m55.158s |
| Fault launch to PR creation | 20:02:43.346 | 20:24:38 | 21m54.654s |
| Human merge | — | 20:31:13 | 28m29.654s after fault launch |
| First human recovery command | 20:31:14.311 | 20:34:16.200 | 3m01.889s |
| Second human enforcement command | 20:37:10.971 | 20:38:29.716 | 1m18.745s |
| Final guest verification | — | 20:39:14.387 | Enforcing and durability checks passed |
| Full live verification complete | — | 20:39:37.206 | 36m53.859s after fault launch |
| Reset start to full live verification | 19:41:13.351 | 20:39:37.206 | 58m23.854s |

The final snapshot distinguishes collection start from completion. Its queries started at 20:39:17; all results and assertions were complete by 20:39:37. This report uses completion for the end-to-end clock. Whole-run durations include polling, operator commands and observation gaps.

Reset's application VM deletion job took 15.858 seconds, other VM cleanup 6.319 seconds, and AAP configuration 88.601 seconds. Backstage took 141 seconds to become ready, including plugin initialization of 73 seconds and RAG initialization of 12 seconds. These operations overlap other reset work.

During full bootstrap, AAP configuration took 104.358 seconds, VM creation 36.156 seconds, and nginx installation 72.508 seconds. Individual project and inventory refreshes are retained in the evidence. The cached image avoided another image build.

## Automatic incident path

The operator launched `bootstrap.sh aap launch webapp_selinux_enable` once. An independent probe confirmed HTTP 403. The alert's recorded pending start was **20:05:12.675**; it was first observed firing at **20:06:13.114**. Pending start comes from Prometheus; firing time is an observation with polling uncertainty.

The alert-to-AO AAP job took 6.066 seconds. RCA's audit activity took 11.361 seconds, its model activity 17.623 seconds, and issue creation 11.112 seconds. The issue-creation AAP job within that activity took 5.854 seconds. Issue #2 then triggered the Forgejo webhook and a 6.254-second AAP job calling the remediation workflow.

The remediation workflow spent 3.160 seconds preparing the feature, 0.033 seconds authenticating, 0.389 seconds creating the session, 0.126 seconds sharing it, and 26.134 seconds sending the task. A completed workflow records the handoff, not a finished fix.

One session received one automatic task. No operator created an incident, replayed a webhook, dispatched a session manually, resumed or compacted the agent, or sent a corrective prompt. No child session was recorded.

## Agent validation and publication

The operator monitored command results and test output without reading the proposed source. MiniMax corrected its initial role-variable lint error itself. It then ran three full Molecule attempts.

| Check | Start | Duration | Result |
|---|---|---:|---|
| Scoped lint 1 | 20:11:57.906 | 4.488s | Failed: role variable prefix rule. |
| Scoped lint 2 | 20:12:10.200 | 4.302s | Passed. |
| Collection build | 20:12:25.405 | 0.525s | Passed. |
| Molecule 1 | 20:12:27.547 | 103.959s | Verify failed: document-root context assertion. Converge, idempotence and destroy passed. |
| Molecule 2 | 20:14:24.605 | 98.797s | Verify failed again. A later shell command masked the failure with status zero. Destroy passed. |
| Molecule 3 | 20:21:24.799 | 111.540s | Full lifecycle passed, including verification, idempotence and destroy. Included an initial destroy before the test. |

The second run's zero shell status did not count as a pass. Its output explicitly recorded failed verification. The third run completed all required phases.

The final native test finished at **20:23:16.339**. MiniMax published PR #3 at **20:24:38**, another **1m21.661s** later, at head `1d37411b86586fbfb435a913a9bb77d10ff5a9e6`. The session became idle without an abort. Its published source was archived privately without displaying or reviewing it.

Independent validation matched the clean native workspace to that published head and hashed all 39 tracked files before and after the checks. Scoped lint passed in 5.279 seconds, collection build in 0.415 seconds, and `make molecule` in **108.677 seconds**. The complete lifecycle passed and the tracked files stayed unchanged. These results, rather than a code review, authorized the merge.

The first independent attempt had been launched without the native session's sandbox kubeconfig. Its Molecule command failed in 6.740 seconds before meaningful functional testing. The operator corrected the runner to inherit the same mounted test kubeconfig and collection search path, then repeated the checks on the unchanged commit. This was a runner correction; no feedback or code change was requested from MiniMax. Both attempts are in the evidence.

## Merge, deployment and live result

The pre-merge application probe was still HTTP 403. The operator applied the existing alert maintenance control, then sent one squash-merge request guarded by the tested head and unchanged base. Forgejo main became `4991428dc897baa0cc77694de4f937d2f38b0547`; issue #2 closed and the source branch was deleted.

The operator launched `bootstrap.sh webapp nginx`. Its command took 181.889 seconds, while the actual nginx job took **33.597 seconds**. The remaining command time includes project and inventory refreshes, scheduling and polling.

The first live guest check completed at **20:36:35**. Both served paths had `httpd_sys_content_t`; `/web(/.*)?` had a persistent local policy entry; a dry-run `restorecon` required no label changes; nginx ran in `httpd_t`; that domain was not permissive. **The guest itself was still Permissive.** The successful nginx job therefore did not establish final Enforcing recovery.

AAP's cached artifact check matched all 13 nginx role/runtime files to the tested head. This was a hash comparison, not a code review.

The operator then launched the existing `webapp_selinux_enable` job. The command took 78.745 seconds; its actual job took **8.076 seconds**. The final independent guest check completed at 20:39:14 and passed every assertion with SELinux Enforcing. Normal alert handling was restored through the existing bootstrap function.

Final platform checks found HTTP 200, probe success one, zero `WebappDown` alerts including silenced and inhibited alerts, all 15 applications synchronized and healthy, two running EDA activations and one session. The alert result was not inferred from a silence or a passing job.

Six collection fetches across the two human recovery launches consumed **143.303 seconds** of command time. The actual nginx and enforcement jobs together took **41.673 seconds**. Project/inventory refreshes can overlap; these figures should not be added indiscriminately to the command totals.

## Interventions and issues

The intended human merge and recovery launches ran through the existing tools. No operator changed candidate code, patched the cluster or repaired the guest directly. The extra enforcement job was necessary to complete the live security-state check and is an additional operator action beyond the intended one-job flow.

Two observation problems were corrected. The local Thanos port-forward had stopped; reconnecting it restored alert timing observations before firing. Prometheus still supplied the earlier pending start. The independent runner lacked the native test kubeconfig and failed before its lifecycle; correcting the runner allowed the unchanged candidate to pass.

A cluster API transient affected the first post-deployment guest and artifact checks. OpenShift Route requests failed delegated authorization because the internal Kubernetes API Service refused connections. Read-only retries subsequently succeeded. The API operator was Available and progressing with `NodeInstaller`, whose recorded transition was 20:34:30; the node remained Ready without resource pressure. This is a coincident observation, not an established cause. No cluster repair was made. Both original checks failed before returning guest results, so neither was counted as a live assertion failure.

Native usage reported 58 assistant records, 68 tool calls, 1,539,480 cumulative input tokens and 16,903 output tokens. The largest request input was 52,496 tokens. No quota errors or child sessions were recorded. These are repeated reported request counters, not unique tokens, billing or provider decoding measurements.

## Speed and remaining work

The earlier three direct streaming samples with the same supplied MiniMax credentials averaged approximately **192.88 generated tokens/s** during decoding. They were not rerun for this incident. MiniMax's inline reasoning contributes to that count. Short capped responses and native tool use are different workloads; that rate does not measure the agent's whole-session speed.

Qwen 235B's direct preflight samples averaged **143.13 generated tokens/s**, but its planned incident did not run after the operator switched back to MiniMax. The [Qwen 27B report](2026-10-09-qwen-repeat.md) measured approximately **26.01 generated tokens/s** on its separate short samples. Different providers, keys, tokenizers, reasoning behavior and test gates prevent a controlled model ranking.

Three improvements follow from observed costs and failures:

1. Make recovery one operator launch that applies the merged collection, ensures Enforcing and verifies live behavior. Here the second command added 78.745 seconds, plus the observation and decision gap. Test the recovery caller's starting state as part of the functional contract; a sandbox pass did not establish that final live mode.
2. Preserve actual command status and record the tested commit with complete lifecycle results. The second native command returned zero after failed verification. A test gate must distinguish that failure from a real pass, as the independent run did.
3. Refresh and fetch the exact merged collection once for recovery, then verify the loaded artifact. Six fetches took 143.303 seconds. Reuse requires a source-revision check because the collection can change while the AAP project revision stays the same. The measured overhead identifies a target, not a guaranteed saving.

This single run demonstrates the complete path with no corrective agent prompt and no code review. It does not establish a repeatability rate, and it still needed a second human recovery job.

## Redaction and verification

Public files omit credentials, live cluster addresses, runtime identifiers, provider reasoning and compaction summaries. The prompt appendix retains submitted instructions with those redactions. The source archive and raw logs remain ignored and private.

The known-credential check examined 1,844 locally reachable blobs across the three demo repositories and found no matches for the supplied keys and retained operator/Forgejo credentials. No history rewrite was needed. This is an exact known-credential check, not exhaustive detection of unknown historical secrets. Report JSON, clocks, local links and credential redaction were checked before publication.
