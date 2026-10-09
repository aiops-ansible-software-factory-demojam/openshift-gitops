# Model repeats — October 9, 2026

The latest MiniMax run reached a tested PR without human follow-up, was merged on test success without code review, and passed live Enforcing/HTTP recovery checks. Recovery still needed two human jobs: nginx deployment followed by SELinux enforcement.

A subsequent [SELinux setup change](2026-10-09-webapp-selinux-setup.md) moved the caller's Permissive step into a separate playbook after provisioning. Its live regression used the existing merged fix: one nginx deployment retained Enforcing and returned HTTP 200. The incident timings below retain the original two-job recovery; this check did not repeat the agent incident.

| Run | Fault launch to PR | Full incident to live proof | Reset and bootstrap | Result |
|---|---:|---:|---:|---|
| [Qwen 27B](2026-10-09-qwen-repeat.md) | 1h20m35s to first PR | 1h40m18s | 27m15s, including the observation gap | Assisted recovery; eight distinct follow-ups, compaction and an external cluster shutdown. Final reviewed fix merged and deployed. |
| [First MiniMax](2026-10-09-minimax-m2-repeat.md) | 19m44s to first PR | No recovery | 24m59s | First PR returned for revision. Revised PR arrived 34 seconds after the 30-minute cutoff and failed production compatibility checks. Neither candidate merged. |
| [MiniMax with merge on test success](2026-10-09-minimax-m2-tests-only-repeat.md) | 21m55s | 36m54s | 20m22s | Zero follow-up prompts and no code review. Independent tests passed; human merge and two recovery jobs produced live Enforcing/HTTP 200. Reset through full proof: 58m24s. |
| Qwen 235B | Not run | Not run | Reset began before the model switch | Provider access and streaming checks passed. The operator replaced its planned incident with the second MiniMax run. |

Reset and bootstrap figures retain AAP and installed platform services. They are not cold installations. The incident clock starts with the fault launch and includes operator testing, merge, recovery and verification. The latest run's 30-minute allowance applied to the automatic incident and agent-to-PR stage; its PR arrived within that allowance.

The two MiniMax results used different operator gates. The first included code review and one corrective message; the second merged only after tests passed. Qwen used a different credential/provider configuration and needed substantial assistance. These are run records, not a controlled model comparison or a repeatability estimate. The earlier [Haiku report](2026-10-09-haiku-bootstrap.md) is retained separately.

Direct short streaming samples measured approximately 26.01 generated tokens/s for Qwen 27B, 192.88 for MiniMax, and 143.13 for Qwen 235B. MiniMax's count includes inline reasoning. Those samples do not measure native session throughput, and the MiniMax samples were reused for the second run rather than repeated.

The latest run supports three practical changes: make Enforcing recovery and verification one human launch; preserve actual validation status and its tested commit; and fetch the exact merged collection once for recovery. Six collection fetches consumed 143.303 seconds while the two recovery jobs themselves consumed 41.673 seconds. The full reports retain prompts, failures, operator actions, runtime checks and redacted evidence.
