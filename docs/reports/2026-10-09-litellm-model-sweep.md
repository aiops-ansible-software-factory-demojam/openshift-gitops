# LiteLLM model sweep — started October 9, 2026

Status: 4 of 6 model attempts logged. The remaining models are pending. Each listed model gets one fresh reset/bootstrap and demo attempt through the [run-demojam skill](../../.agents/skills/run-demojam/SKILL.md). AAP is retained; cluster commands use `~/.kube/config`.

No operator code review, coaching, candidate edit, runner correction, test retry, manual dispatch, compaction, flow replay or runtime repair is allowed. The automatic fault-to-eligible-PR stage has a 30-minute cutoff. A clean published head must independently pass scoped lint, package build and every Molecule lifecycle before a guarded merge. Recovery gets one nginx job, followed by read-only Enforcing, HTTP, artifact and normal alert-resolution checks. Failed attempts remain failures; the next model begins with its normal authorized reset.

Both authenticated model catalogues returned HTTP 200, and every listed model accepted one authenticated chat completion. The access probe requested `MODEL_READY` with a 256-token cap. DeepSeek reached the cap without a visible answer; it remains in the queue. This probe is not a tool-compatibility test or a decoding benchmark. Qwen 38 uses the existing bootstrap thinking-disabled setting; other models keep the existing provider defaults. The automatic remediation task and bootstrap implementation are unchanged across the sweep.

## Model results

| Credential | Requested model | Provider returned model | Outcome | Reset | Bootstrap | Fault → PR created | Fault → eligible idle PR | Fault → outcome/proof | Reset → outcome/proof |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| `litellm.txt` | `qwen36-35b-a3b` | `qwen-3.6-36b-a3b-test` | failed · ao-smoke | 12m12.052s | 10m13.122s | — | — | — | 23m23.827s |
| `litellm.txt` | `qwen38-27b` | `qwen38-27b` | cutoff · automatic-agent-stage | 10m50.569s | 10m41.704s | — | — | 30m0.003s | 52m27.459s |
| `litellm2.txt` | `deepseek-r1-distill-qwen-14b` | `deepseek-r1-distill-qwen-14b` | cutoff · automatic-agent-stage | 9m20.165s | 14m58.232s | — | — | 30m0.003s | 55m12.794s |
| `litellm2.txt` | `gpt-oss-120b` | `openai/gpt-oss-120b-maas` | cutoff · automatic-agent-stage | 9m46.215s | 13m42.555s | — | — | 30m0.461s | 54m12.469s |
| `litellm2.txt` | `minimax-m2` | `minimaxai/minimax-m2-maas` | Pending | — | — | — | — | — | — |
| `litellm2.txt` | `qwen3-235b` | `qwen/qwen3-235b-a22b-instruct-2507-maas` | Pending | — | — | — | — | — | — |

Successful runs end at completed live proof. Failed runs end when the failure or cutoff is recorded; later read-only evidence collection and publication are outside that attempt clock. Whole-run times include API calls, polling and operator bookkeeping. The automated incident clock begins when the fault launch command starts, including AAP refresh overhead.

## 1. qwen36-35b-a3b

Outcome: **failed · ao-smoke**. [JSON evidence](evidence/2026-10-09/litellm-sweep-01-litellm-qwen36-35b-a3b.json) · [Submitted prompts](2026-10-09-sweep-01-litellm-qwen36-35b-a3b-prompts.md).

Sources: GitOps `54da639`, unfixed collection `c78d4c8`, AAP/EDA `c557ad5`. Bootstrap script SHA-256: `4bbbe525b94d028623bc28aa153faf429d47ebcf5651f64646c70c753576ab8b`. Only model/credential selection and report files change between attempts.

Model/credential and retained AAP identities verified: `demo/qwen36-35b-a3b`, `@ai-sdk/openai-compatible`.

Workflow `llm-question` failed at `ask_model` on 10-09 22:55:56.549 UTC. The failure time is separate from the later observation cutoff or command return.

Observed 0 outage issue(s), 0 Omnigent session(s), 0 delivered user message(s), and 0 PR(s). Operator follow-up messages: 0. The seeded README exercise issue is excluded from the incident count.

| Operator command | Start UTC | Finish UTC | Elapsed | Exit |
|---|---|---|---:|---:|
| `reset` | 10-09 22:32:39.258 | 10-09 22:44:51.310 | 12m12.052s | 0 |
| `reset-baseline-check` | 10-09 22:44:53.194 | 10-09 22:44:56.335 | 3.141s | 0 |
| `bootstrap` | 10-09 22:44:56.356 | 10-09 22:55:09.478 | 10m13.122s | 0 |
| `model-verification` | 10-09 22:55:09.500 | 10-09 22:55:10.689 | 1.189s | 0 |
| `baseline-check` | 10-09 22:55:10.715 | 10-09 22:55:36.594 | 25.880s | 0 |
| `ao-smoke` | 10-09 22:55:36.621 | 10-09 22:56:03.080 | 26.459s | 2 |

| AAP job | Name | Actual start UTC | Actual finish UTC | Job time | Status |
|---:|---|---|---|---:|---|
| 370 | `webapp_vm` | 10-09 22:35:06.893 | 10-09 22:35:25.145 | 18.252s | successful |
| 376 | `openshift_virtualization_machine` | 10-09 22:37:01.177 | 10-09 22:37:09.413 | 8.236s | successful |
| 383 | `aap_configure_all` | 10-09 22:42:33.381 | 10-09 22:43:56.933 | 1m23.552s | successful |
| 394 | `aap_configure_all` | 10-09 22:47:54.898 | 10-09 22:49:13.659 | 1m18.761s | successful |
| 404 | `webapp_vm` | 10-09 22:50:37.256 | 10-09 22:51:23.157 | 45.901s | successful |
| 410 | `webapp_selinux_permissive` | 10-09 22:52:11.003 | 10-09 22:52:18.094 | 7.091s | successful |
| 416 | `webapp_nginx` | 10-09 22:52:56.592 | 10-09 22:54:08.051 | 1m11.459s | successful |

| AO workflow/activity | Start UTC | Finish UTC | Duration | Status |
|---|---|---|---:|---|
| llm-question | 10-09 22:55:41.557 | 10-09 22:55:56.571 | 15.015s | failed |
| `start` | 10-09 22:55:41.945 | 10-09 22:55:41.952 | 0.006s | completed |
| `ask_model` | 10-09 22:55:42.047 | 10-09 22:55:56.549 | 14.502s | failed |

Activity error: AgentOrchestratorError: An unexpected error occurred during LLM streaming. Please try again.

## 2. qwen38-27b

Outcome: **cutoff · automatic-agent-stage**. [JSON evidence](evidence/2026-10-09/litellm-sweep-02-litellm-qwen38-27b.json) · [Submitted prompts](2026-10-09-sweep-02-litellm-qwen38-27b-prompts.md).

Sources: GitOps `0328687`, unfixed collection `c78d4c8`, AAP/EDA `c557ad5`. Bootstrap script SHA-256: `4bbbe525b94d028623bc28aa153faf429d47ebcf5651f64646c70c753576ab8b`. Only model/credential selection and report files change between attempts.

Model/credential and retained AAP identities verified: `demo/qwen38-27b`, `@ai-sdk/openai-compatible`.

Observed 1 outage issue(s), 1 Omnigent session(s), 1 delivered user message(s), and 0 PR(s). Operator follow-up messages: 0. The seeded README exercise issue is excluded from the incident count.

Outage issue #2: `[WebappDown] Demo webapp is unavailable`, created 10-09 23:23:02.000, state `open`.

No eligible idle PR was available by the 30-minute deadline. No abort, prompt or repair was sent. The next authorized reset removes the unfinished run before starting a different model.

| Operator command | Start UTC | Finish UTC | Elapsed | Exit |
|---|---|---|---:|---:|
| `reset` | 10-09 22:57:29.347 | 10-09 23:08:19.917 | 10m50.569s | 0 |
| `reset-baseline-check` | 10-09 23:08:19.938 | 10-09 23:08:23.025 | 3.088s | 0 |
| `bootstrap` | 10-09 23:08:23.049 | 10-09 23:19:04.753 | 10m41.704s | 0 |
| `model-verification` | 10-09 23:19:04.775 | 10-09 23:19:05.669 | 0.895s | 0 |
| `baseline-check` | 10-09 23:19:05.688 | 10-09 23:19:33.456 | 27.767s | 0 |
| `ao-smoke` | 10-09 23:19:33.477 | 10-09 23:19:54.777 | 21.300s | 0 |
| `break` | 10-09 23:19:56.803 | 10-09 23:20:47.047 | 50.245s | 0 |
| `fault-probe-check` | 10-09 23:20:47.068 | 10-09 23:20:47.719 | 0.650s | 0 |
| `fault-mode-check` | 10-09 23:20:47.741 | 10-09 23:20:55.173 | 7.432s | 0 |

| AAP job | Name | Actual start UTC | Actual finish UTC | Job time | Status |
|---:|---|---|---|---:|---|
| 423 | `webapp_vm` | 10-09 22:58:29.331 | 10-09 22:58:45.161 | 15.830s | successful |
| 429 | `openshift_virtualization_machine` | 10-09 22:59:23.899 | 10-09 22:59:29.931 | 6.032s | successful |
| 436 | `aap_configure_all` | 10-09 23:05:33.399 | 10-09 23:07:26.722 | 1m53.322s | successful |
| 447 | `aap_configure_all` | 10-09 23:11:47.494 | 10-09 23:13:11.268 | 1m23.774s | successful |
| 457 | `webapp_vm` | 10-09 23:14:38.108 | 10-09 23:15:24.280 | 46.171s | successful |
| 463 | `webapp_selinux_permissive` | 10-09 23:16:17.731 | 10-09 23:16:24.557 | 6.826s | successful |
| 469 | `webapp_nginx` | 10-09 23:17:08.242 | 10-09 23:18:19.210 | 1m10.968s | successful |
| 476 | `webapp_selinux_enable` | 10-09 23:20:35.975 | 10-09 23:20:41.803 | 5.827s | successful |
| 478 | `call_ao_webhook` | 10-09 23:22:23.479 | 10-09 23:22:30.496 | 7.017s | successful |
| 479 | `pull_audit_logs` | 10-09 23:22:31.153 | 10-09 23:22:36.965 | 5.812s | successful |
| 480 | `webapp_alert_issue` | 10-09 23:22:57.271 | 10-09 23:23:03.051 | 5.780s | successful |
| 481 | `call_ao_webhook` | 10-09 23:23:03.830 | 10-09 23:23:10.395 | 6.565s | successful |

| AO workflow/activity | Start UTC | Finish UTC | Duration | Status |
|---|---|---|---:|---|
| llm-question | 10-09 23:19:38.523 | 10-09 23:19:49.722 | 11.199s | completed |
| `start` | 10-09 23:19:39.387 | 10-09 23:19:39.396 | 0.009s | completed |
| `ask_model` | 10-09 23:19:39.516 | 10-09 23:19:49.703 | 10.186s | completed |
| Check Audit logs, Determine RCA, Create Issue | 10-09 23:22:29.879 | 10-09 23:23:07.824 | 37.945s | completed |
| `alertmanagereda` | 10-09 23:22:30.279 | 10-09 23:22:30.288 | 0.009s | completed |
| `auditlogs` | 10-09 23:22:30.439 | 10-09 23:22:41.736 | 11.297s | completed |
| `airca` | 10-09 23:22:41.845 | 10-09 23:22:56.308 | 14.462s | completed |
| `createissue` | 10-09 23:22:56.458 | 10-09 23:23:07.797 | 11.339s | completed |
| omnigent-remediation | 10-09 23:23:09.814 | 10-09 23:23:46.104 | 36.290s | completed |
| `forgejo_issue` | 10-09 23:23:09.982 | 10-09 23:23:10.115 | 0.133s | completed |
| `prepare_feature` | 10-09 23:23:10.161 | 10-09 23:23:13.330 | 3.169s | completed |
| `authenticate_omnigent` | 10-09 23:23:13.408 | 10-09 23:23:13.441 | 0.033s | completed |
| `create_session` | 10-09 23:23:13.470 | 10-09 23:23:14.251 | 0.781s | completed |
| `share_session_0` | 10-09 23:23:14.280 | 10-09 23:23:14.421 | 0.141s | completed |
| `send_task` | 10-09 23:23:14.453 | 10-09 23:23:46.076 | 31.623s | completed |

| Agent validation command | Start UTC | Duration | Tool exit | Completed phases | Failed phases |
|---|---|---:|---:|---|---|
| `collection_build` | 10-09 23:30:42.959 | 46.199s | 0 | — | — |
| `scoped_lint` | 10-09 23:32:24.670 | 6.991s | 0 | — | — |
| `scoped_lint` | 10-09 23:35:58.783 | 7.309s | 0 | — | — |
| `collection_build` | 10-09 23:36:12.852 | 7.053s | 0 | — | — |
| `molecule` | 10-09 23:36:41.529 | 1m18.578s | 0 | — | — |
| `molecule` | 10-09 23:38:28.542 | 1m22.639s | 0 | — | — |
| `molecule` | 10-09 23:42:36.994 | 1m29.525s | 0 | — | — |
| `scoped_lint` | 10-09 23:44:41.682 | 1m57.455s | 0 | — | — |
| `molecule` | 10-09 23:47:00.650 | 2m10.954s | 0 | — | — |
| `scoped_lint` | 10-09 23:49:26.420 | 13.280s | 0 | — | — |

Native counters: 93 assistant records, 136 tools, 0 child sessions, 4,095,663 input tokens, 16,291 output tokens, 0 reasoning tokens, 0 cache-read and 0 cache-write tokens. Quota errors recorded: 2. These are cumulative provider/harness counters, not unique context, billing or measured decoding tokens/s. Request timestamps, finishes, error names and usage counters are retained in JSON; assistant text and reasoning are excluded.

## 3. deepseek-r1-distill-qwen-14b

Outcome: **cutoff · automatic-agent-stage**. [JSON evidence](evidence/2026-10-09/litellm-sweep-03-litellm2-deepseek-r1-distill-qwen-14b.json) · [Submitted prompts](2026-10-09-sweep-03-litellm2-deepseek-r1-distill-qwen-14b-prompts.md).

Sources: GitOps `779b3a5`, unfixed collection `c78d4c8`, AAP/EDA `c557ad5`. Bootstrap script SHA-256: `4bbbe525b94d028623bc28aa153faf429d47ebcf5651f64646c70c753576ab8b`. Only model/credential selection and report files change between attempts.

Model/credential and retained AAP identities verified: `demo/deepseek-r1-distill-qwen-14b`, `@ai-sdk/openai-compatible`.

Workflow `Check Audit logs, Determine RCA, Create Issue` failed at `airca` on 10-10 00:22:56.771 UTC, 5m55.194s after the fault launch. The failure time is separate from the later observation cutoff or command return.

Observed 0 outage issue(s), 0 Omnigent session(s), 0 delivered user message(s), and 0 PR(s). Operator follow-up messages: 0. The seeded README exercise issue is excluded from the incident count.

No eligible idle PR was available by the 30-minute deadline. No abort, prompt or repair was sent. The next authorized reset removes the unfinished run before starting a different model.

| Operator command | Start UTC | Finish UTC | Elapsed | Exit |
|---|---|---|---:|---:|
| `reset` | 10-09 23:51:48.786 | 10-10 00:01:08.952 | 9m20.165s | 0 |
| `reset-baseline-check` | 10-10 00:01:08.972 | 10-10 00:01:11.999 | 3.027s | 0 |
| `bootstrap` | 10-10 00:01:12.021 | 10-10 00:16:10.253 | 14m58.232s | 0 |
| `model-verification` | 10-10 00:16:10.276 | 10-10 00:16:11.176 | 0.901s | 0 |
| `baseline-check` | 10-10 00:16:11.200 | 10-10 00:16:38.408 | 27.208s | 0 |
| `ao-smoke` | 10-10 00:16:38.434 | 10-10 00:16:59.555 | 21.121s | 0 |
| `break` | 10-10 00:17:01.577 | 10-10 00:18:40.081 | 1m38.503s | 0 |
| `fault-probe-check` | 10-10 00:18:40.104 | 10-10 00:18:40.749 | 0.645s | 0 |
| `fault-mode-check` | 10-10 00:18:40.772 | 10-10 00:18:49.566 | 8.794s | 0 |

| AAP job | Name | Actual start UTC | Actual finish UTC | Job time | Status |
|---:|---|---|---|---:|---|
| 487 | `webapp_vm` | 10-09 23:52:50.132 | 10-09 23:53:05.931 | 15.800s | successful |
| 493 | `openshift_virtualization_machine` | 10-09 23:53:38.704 | 10-09 23:53:44.862 | 6.157s | successful |
| 500 | `aap_configure_all` | 10-09 23:58:48.216 | 10-10 00:00:06.770 | 1m18.553s | successful |
| 511 | `aap_configure_all` | 10-10 00:06:13.877 | 10-10 00:08:07.276 | 1m53.399s | successful |
| 521 | `webapp_vm` | 10-10 00:10:01.106 | 10-10 00:10:41.932 | 40.826s | successful |
| 527 | `webapp_selinux_permissive` | 10-10 00:12:18.774 | 10-10 00:12:25.593 | 6.819s | successful |
| 533 | `webapp_nginx` | 10-10 00:14:14.533 | 10-10 00:15:25.480 | 1m10.947s | successful |
| 540 | `webapp_selinux_enable` | 10-10 00:18:28.984 | 10-10 00:18:35.015 | 6.031s | successful |
| 542 | `call_ao_webhook` | 10-10 00:20:23.575 | 10-10 00:20:30.109 | 6.533s | successful |
| 543 | `pull_audit_logs` | 10-10 00:20:30.869 | 10-10 00:20:36.457 | 5.589s | successful |

| AO workflow/activity | Start UTC | Finish UTC | Duration | Status |
|---|---|---|---:|---|
| llm-question | 10-10 00:16:43.184 | 10-10 00:16:55.991 | 12.807s | completed |
| `start` | 10-10 00:16:43.631 | 10-10 00:16:43.637 | 0.006s | completed |
| `ask_model` | 10-10 00:16:43.759 | 10-10 00:16:55.974 | 12.215s | completed |
| Check Audit logs, Determine RCA, Create Issue | 10-10 00:20:29.550 | 10-10 00:22:56.792 | 2m27.242s | failed |
| `createissue` | — | 10-10 00:22:58.157 | — | skipped |
| `alertmanagereda` | 10-10 00:20:30.008 | 10-10 00:20:30.015 | 0.007s | completed |
| `auditlogs` | 10-10 00:20:30.155 | 10-10 00:20:41.409 | 11.254s | completed |
| `airca` | 10-10 00:20:41.516 | 10-10 00:22:56.771 | 2m15.255s | failed |

Activity error: AgentTimeoutError: The AI Agent did not respond in time. Try again, increase the node timeout, or simplify the prompt. If the agent may still be running, check execution details before re-running.

## 4. gpt-oss-120b

Outcome: **cutoff · automatic-agent-stage**. [JSON evidence](evidence/2026-10-09/litellm-sweep-04-litellm2-gpt-oss-120b.json) · [Submitted prompts](2026-10-09-sweep-04-litellm2-gpt-oss-120b-prompts.md).

Sources: GitOps `4b4d27b`, unfixed collection `c78d4c8`, AAP/EDA `c557ad5`. Bootstrap script SHA-256: `4bbbe525b94d028623bc28aa153faf429d47ebcf5651f64646c70c753576ab8b`. Only model/credential selection and report files change between attempts.

Model/credential and retained AAP identities verified: `demo/gpt-oss-120b`, `@ai-sdk/openai-compatible`.

Observed 1 outage issue(s), 1 Omnigent session(s), 1 delivered user message(s), and 0 PR(s). Operator follow-up messages: 0. The seeded README exercise issue is excluded from the incident count.

Outage issue #2: `[WebappDown] Demo webapp is unavailable`, created 10-10 01:16:21.000, state `open`.

No eligible idle PR was available by the 30-minute deadline. No abort, prompt or repair was sent. The next authorized reset removes the unfinished run before starting a different model.

| Operator command | Start UTC | Finish UTC | Elapsed | Exit |
|---|---|---|---:|---:|
| `reset` | 10-10 00:49:02.514 | 10-10 00:58:48.729 | 9m46.215s | 0 |
| `reset-baseline-check` | 10-10 00:58:48.752 | 10-10 00:58:51.859 | 3.107s | 0 |
| `bootstrap` | 10-10 00:58:51.881 | 10-10 01:12:34.436 | 13m42.555s | 0 |
| `model-verification` | 10-10 01:12:34.459 | 10-10 01:12:35.553 | 1.094s | 0 |
| `baseline-check` | 10-10 01:12:35.573 | 10-10 01:13:02.035 | 26.463s | 0 |
| `ao-smoke` | 10-10 01:13:02.055 | 10-10 01:13:12.501 | 10.445s | 0 |
| `break` | 10-10 01:13:14.523 | 10-10 01:14:20.458 | 1m5.936s | 0 |
| `fault-probe-check` | 10-10 01:14:20.486 | 10-10 01:14:21.137 | 0.650s | 0 |
| `fault-mode-check` | 10-10 01:14:21.161 | 10-10 01:14:30.027 | 8.866s | 0 |

| AAP job | Name | Actual start UTC | Actual finish UTC | Job time | Status |
|---:|---|---|---|---:|---|
| 549 | `webapp_vm` | 10-10 00:50:18.589 | 10-10 00:50:34.392 | 15.803s | successful |
| 555 | `openshift_virtualization_machine` | 10-10 00:51:25.071 | 10-10 00:51:30.850 | 5.779s | successful |
| 562 | `aap_configure_all` | 10-10 00:56:37.229 | 10-10 00:57:55.766 | 1m18.536s | successful |
| 573 | `aap_configure_all` | 10-10 01:03:42.985 | 10-10 01:06:01.411 | 2m18.426s | successful |
| 583 | `webapp_vm` | 10-10 01:07:41.199 | 10-10 01:08:27.115 | 45.917s | successful |
| 589 | `webapp_selinux_permissive` | 10-10 01:09:46.973 | 10-10 01:09:53.244 | 6.271s | successful |
| 595 | `webapp_nginx` | 10-10 01:10:48.098 | 10-10 01:11:59.604 | 1m11.505s | successful |
| 602 | `webapp_selinux_enable` | 10-10 01:14:09.312 | 10-10 01:14:15.074 | 5.761s | successful |
| 604 | `call_ao_webhook` | 10-10 01:15:53.443 | 10-10 01:15:59.270 | 5.827s | successful |
| 605 | `pull_audit_logs` | 10-10 01:15:59.710 | 10-10 01:16:07.251 | 7.541s | successful |
| 606 | `webapp_alert_issue` | 10-10 01:16:14.857 | 10-10 01:16:21.649 | 6.793s | successful |
| 607 | `call_ao_webhook` | 10-10 01:16:22.639 | 10-10 01:16:28.681 | 6.042s | successful |

| AO workflow/activity | Start UTC | Finish UTC | Duration | Status |
|---|---|---|---:|---|
| llm-question | 10-10 01:13:06.825 | 10-10 01:13:09.372 | 2.547s | completed |
| `start` | 10-10 01:13:07.031 | 10-10 01:13:07.037 | 0.006s | completed |
| `ask_model` | 10-10 01:13:07.147 | 10-10 01:13:09.353 | 2.206s | completed |
| Check Audit logs, Determine RCA, Create Issue | 10-10 01:15:58.766 | 10-10 01:16:25.411 | 26.645s | completed |
| `alertmanagereda` | 10-10 01:15:58.912 | 10-10 01:15:58.921 | 0.009s | completed |
| `auditlogs` | 10-10 01:15:59.081 | 10-10 01:16:10.310 | 11.228s | completed |
| `airca` | 10-10 01:16:10.430 | 10-10 01:16:13.942 | 3.512s | completed |
| `createissue` | 10-10 01:16:14.099 | 10-10 01:16:25.387 | 11.287s | completed |
| omnigent-remediation | 10-10 01:16:28.141 | 10-10 01:17:14.699 | 46.557s | completed |
| `forgejo_issue` | 10-10 01:16:28.286 | 10-10 01:16:28.293 | 0.007s | completed |
| `prepare_feature` | 10-10 01:16:28.319 | 10-10 01:16:31.477 | 3.158s | completed |
| `authenticate_omnigent` | 10-10 01:16:31.575 | 10-10 01:16:31.608 | 0.033s | completed |
| `create_session` | 10-10 01:16:31.634 | 10-10 01:16:32.188 | 0.554s | completed |
| `share_session_0` | 10-10 01:16:32.214 | 10-10 01:16:32.329 | 0.115s | completed |
| `send_task` | 10-10 01:16:32.387 | 10-10 01:17:14.677 | 42.290s | completed |

Native counters: 1 assistant records, 0 tools, 0 child sessions, 3,321 input tokens, 0 output tokens, 137 reasoning tokens, 0 cache-read and 0 cache-write tokens. Quota errors recorded: 0. These are cumulative provider/harness counters, not unique context, billing or measured decoding tokens/s. Request timestamps, finishes, error names and usage counters are retained in JSON; assistant text and reasoning are excluded.

## Reading these results

These attempts test the existing demo, provider transport, automatic agent handoff, validation gate and live recovery together. A provider/readiness failure, no PR, failed immutable-head check or failed recovery is a distinct outcome. They are not repaired or silently excluded. The runs share a cluster and execute serially, use different provider routes, and retain platform/image caches; this is not a controlled model-quality or repeatability benchmark.

Public artifacts exclude credentials, provider/live hostnames, private addresses, runtime IDs and raw native reasoning. Exact known-credential, JSON, local-link and whitespace checks run before publication. Raw logs remain ignored and private.
