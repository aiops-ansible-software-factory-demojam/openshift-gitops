# LiteLLM model sweep — October 9, 2026

Status: in progress. Every model listed by both supplied credentials will get one fresh reset/bootstrap and demo attempt through the [run-demojam skill](../../.agents/skills/run-demojam/SKILL.md). AAP is retained. All local cluster commands use `~/.kube/config`.

The operator will not review code, coach or resume the agent, edit candidates, replay the flow, repair runtime resources, correct a test runner during a model run, or retry failed candidate checks. The automatic fault-to-eligible-PR stage has a 30-minute cutoff. A published head must independently pass lint, collection build and every Molecule lifecycle before a guarded merge. Recovery gets one nginx job and read-only Enforcing/HTTP/alert verification.

## Available models

Both authenticated model catalogues returned HTTP 200. Each listed model also accepted one authenticated chat completion. `MODEL_READY` is an access probe, not a tool-compatibility or decoding benchmark. DeepSeek exhausted the probe’s 256-token output cap without a visible ready answer; it remains in the demo queue. Generated probe reasoning/text is not published.

| Credential file | Requested model | Returned model | Access | Demo outcome |
|---|---|---|---|---|
| `litellm.txt` | `qwen36-35b-a3b` | `qwen-3.6-36b-a3b-test` | HTTP 200 | Pending |
| `litellm.txt` | `qwen38-27b` | `qwen38-27b` | HTTP 200 | Pending |
| `litellm2.txt` | `deepseek-r1-distill-qwen-14b` | `deepseek-r1-distill-qwen-14b` | HTTP 200 | Pending |
| `litellm2.txt` | `gpt-oss-120b` | `openai/gpt-oss-120b-maas` | HTTP 200 | Pending |
| `litellm2.txt` | `minimax-m2` | `minimaxai/minimax-m2-maas` | HTTP 200 | Pending |
| `litellm2.txt` | `qwen3-235b` | `qwen/qwen3-235b-a22b-instruct-2507-maas` | HTTP 200 | Pending |

## Run log

Runs execute serially on the shared cluster. Per-model outcomes, job IDs, stage clocks, prompts and token usage will be appended before each following reset. Provider failures, bootstrap failures, missing PRs, test failures and recovery failures count as failed attempts; none will be repaired into a pass.

Credentials, endpoint hostnames, runtime IDs and native assistant reasoning are excluded from public artifacts. Raw data remains ignored and private.
