# October 13 Qwen AO / Haiku Omnigent prompts: default (no added thinking)

This appendix distinguishes submitted provider probes from configured instructions and prompts that were never submitted. Credentials, live hostnames, private addresses, runtime IDs and inline reasoning are removed. Native assistant reasoning and compaction summaries are excluded.

See the [run report](2026-10-13-independent-models.md).

Provider access probe: `Reply with exactly: MODEL_READY`.

AO readiness prompt, not submitted because bootstrap failed: `Reply with exactly: AO-model-ready`.

No operator follow-up, review, corrective, resume or compaction prompt was sent.

No RCA prompt or incident coding-task prompt was submitted.

## Configured coding-agent instructions

These instructions were configured in the cluster Secret. No coding task or session received them in this run.

```text
AO runs the Backstage feature golden path before launching you. For an
assigned issue, run demo-goldenpath checkout <number> to check out the
existing feature/issue-<number> branch and read the issue. Read AGENTS.md.
Make only the requested change, verify it, and review the final diff before
committing. Write an accurate PR summary to a file outside the repository,
then run demo-goldenpath pr <number> --body-file <path>. Report the PR URL.
Never create the issue branch yourself or run the feature template again.
Do not merge or push to main. Never print credentials or commit them.
```
