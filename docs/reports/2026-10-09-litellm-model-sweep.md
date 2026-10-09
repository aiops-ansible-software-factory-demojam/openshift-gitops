# LiteLLM model sweep — started October 9, 2026

Status: 1 of 6 model attempts logged. The remaining models are pending. Each listed model gets one fresh reset/bootstrap and demo attempt through the [run-demojam skill](../../.agents/skills/run-demojam/SKILL.md). AAP is retained; cluster commands use `~/.kube/config`.

No operator code review, coaching, candidate edit, runner correction, test retry, manual dispatch, compaction, flow replay or runtime repair is allowed. The automatic fault-to-eligible-PR stage has a 30-minute cutoff. A clean published head must independently pass scoped lint, package build and every Molecule lifecycle before a guarded merge. Recovery gets one nginx job, followed by read-only Enforcing, HTTP, artifact and normal alert-resolution checks. Failed attempts remain failures; the next model begins with its normal authorized reset.

Both authenticated model catalogues returned HTTP 200, and every listed model accepted one authenticated chat completion. The access probe requested `MODEL_READY` with a 256-token cap. DeepSeek reached the cap without a visible answer; it remains in the queue. This probe is not a tool-compatibility test or a decoding benchmark. Qwen 38 uses the existing bootstrap thinking-disabled setting; other models keep the existing provider defaults. The automatic remediation task and bootstrap implementation are unchanged across the sweep.

## Model results

| Credential | Requested model | Provider returned model | Outcome | Reset | Bootstrap | Fault → PR | Fault → outcome/proof | Reset → outcome/proof |
|---|---|---|---|---:|---:|---:|---:|---:|
| `litellm.txt` | `qwen36-35b-a3b` | `qwen-3.6-36b-a3b-test` | failed · ao-smoke | 12m12.052s | 10m13.122s | — | — | 23m23.827s |
| `litellm.txt` | `qwen38-27b` | `qwen38-27b` | Pending | — | — | — | — | — |
| `litellm2.txt` | `deepseek-r1-distill-qwen-14b` | `deepseek-r1-distill-qwen-14b` | Pending | — | — | — | — | — |
| `litellm2.txt` | `gpt-oss-120b` | `openai/gpt-oss-120b-maas` | Pending | — | — | — | — | — |
| `litellm2.txt` | `minimax-m2` | `minimaxai/minimax-m2-maas` | Pending | — | — | — | — | — |
| `litellm2.txt` | `qwen3-235b` | `qwen/qwen3-235b-a22b-instruct-2507-maas` | Pending | — | — | — | — | — |

Successful runs end at completed live proof. Failed runs end when the failure or cutoff is recorded; later read-only evidence collection and publication are outside that attempt clock. Whole-run times include API calls, polling and operator bookkeeping. The automated incident clock begins when the fault launch command starts, including AAP refresh overhead.

## 1. qwen36-35b-a3b

Outcome: **failed · ao-smoke**. [JSON evidence](evidence/2026-10-09/litellm-sweep-01-litellm-qwen36-35b-a3b.json) · [Submitted prompts](2026-10-09-sweep-01-litellm-qwen36-35b-a3b-prompts.md).

Sources: GitOps `54da639`, unfixed collection `c78d4c8`, AAP/EDA `c557ad5`. Bootstrap script SHA-256: `4bbbe525b94d028623bc28aa153faf429d47ebcf5651f64646c70c753576ab8b`. Only model/credential selection and report files change between attempts.

Model/credential and retained AAP identities verified: `demo/qwen36-35b-a3b`, `@ai-sdk/openai-compatible`.

Observed 0 Omnigent session(s), 0 delivered user message(s), and 0 PR(s). Operator follow-up messages: 0.

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

## Reading these results

These attempts test the existing demo, provider transport, automatic agent handoff, validation gate and live recovery together. A provider/readiness failure, no PR, failed immutable-head check or failed recovery is a distinct outcome. They are not repaired or silently excluded. The runs share a cluster and execute serially, use different provider routes, and retain platform/image caches; this is not a controlled model-quality or repeatability benchmark.

Public artifacts exclude credentials, provider/live hostnames, private addresses, runtime IDs and raw native reasoning. Exact known-credential, JSON, local-link and whitespace checks run before publication. Raw logs remain ignored and private.
