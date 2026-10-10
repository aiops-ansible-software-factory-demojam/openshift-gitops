# Model repeats — October 9, 2026

The latest Haiku run reached a PR without human follow-up, was merged on independent test success without code review, and recovered with SELinux Enforcing through one nginx job. The operator corrected an isolated test-runner layout error before the passing gate; no candidate change or corrective model prompt was needed.

The preceding MiniMax run needed two recovery jobs: nginx deployment followed by SELinux enforcement. A [SELinux setup change](2026-10-09-webapp-selinux-setup.md) then moved the caller's Permissive step into a separate playbook after provisioning. Its live regression used the existing merged fix. The new Haiku run tested that change through a fresh reset, full bootstrap and automatic agent incident.

| Run | Fault launch to PR | Full incident to live proof | Reset and bootstrap | Result |
|---|---:|---:|---:|---|
| [Qwen 27B](2026-10-09-qwen-repeat.md) | 1h20m35s to first PR | 1h40m18s | 27m15s, including the observation gap | Assisted recovery; eight distinct follow-ups, compaction and an external cluster shutdown. Final reviewed fix merged and deployed. |
| [First MiniMax](2026-10-09-minimax-m2-repeat.md) | 19m44s to first PR | No recovery | 24m59s | First PR returned for revision. Revised PR arrived 34 seconds after the 30-minute cutoff and failed production compatibility checks. Neither candidate merged. |
| [MiniMax with merge on test success](2026-10-09-minimax-m2-tests-only-repeat.md) | 21m55s | 36m54s | 20m22s | Zero follow-up prompts and no code review. Independent tests passed; human merge and two recovery jobs produced live Enforcing/HTTP 200. Reset through full proof: 58m24s. |
| [Haiku with one-job recovery](2026-10-09-haiku-no-intervention.md) | 7m56s | 18m15s | 26m21s | Zero follow-up prompts and no code review. Independent runner corrected; unchanged published head passed tests. Merge and one nginx job produced Enforcing/HTTP 200. Reset through full proof: 45m55s. |
| Qwen 235B | Not run | Not run | Reset began before the model switch | Provider access and streaming checks passed. The operator replaced its planned incident with the second MiniMax run. |

Reset and bootstrap figures retain AAP and installed platform services. They are not cold installations. The incident clock starts with the fault launch and includes operator testing, merge, recovery and verification. The latest run's 30-minute allowance applied to the automatic incident and agent-to-PR stage; its PR arrived within that allowance.

The two MiniMax results used different operator gates. The first included code review and one corrective message; the second merged only after tests passed, as did the latest Haiku run. Qwen used a different credential/provider configuration and needed substantial assistance. These are run records, not a controlled model comparison or a repeatability estimate. The earlier [Haiku report](2026-10-09-haiku-bootstrap.md) is retained separately.

Direct short streaming samples measured approximately 26.01 generated tokens/s for Qwen 27B, 192.88 for MiniMax, and 143.13 for Qwen 235B. MiniMax's count includes inline reasoning. Those samples do not measure native session throughput, and the MiniMax samples were reused for the second run rather than repeated.

One-job Enforcing recovery is now demonstrated in the latest Haiku run. Its remaining measured recovery overhead includes three collection fetches taking 118.648 seconds, compared with 24.502 seconds for the application job. Preserve actual validation statuses and the tested commit, keep isolated test source/install paths separate, and consider fetching the exact merged collection once for recovery. The full reports retain prompts, failures, operator actions, runtime checks and redacted evidence.
