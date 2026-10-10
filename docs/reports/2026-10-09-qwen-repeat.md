# Qwen reset and repeat — October 9, 2026

The warm reset and full bootstrap passed. The real fault reached the automatic alert → RCA → Forgejo issue → webhook → EDA/AO → native Omnigent handoff in **3m 56.269s**. Qwen then produced a tested fix, which the operator reviewed, merged and deployed. Independent checks confirmed **Enforcing**, persistent file contexts, HTTP 200 and no remaining `WebappDown` alert.

This was an **assisted recovery**. The first unattended attempt made no edits and blocked on an internal helper's permissions. The run needed eight distinct human follow-up messages, native aborts and manual context compaction. The workshop cluster was also stopped externally and restarted. Break command to collected live recovery proof took **1h 40m 17.847s**, including that interruption and operator work. It is not an unattended demo time.

The [preceding Haiku report](2026-10-09-haiku-bootstrap.md) records a different successful merge and recovery test. This Qwen candidate also corrected the collection dependency mismatch with the production execution environment. Neither run establishes repeatability or a controlled model comparison.

## Scope and configuration

All cluster work used `~/.kube/config`. The installed platform and AAP were retained. `bash bootstrap/bootstrap.sh demo-reset --confirm-demo-reset` removed the previous session, disposable VMs and test disks, recreated Forgejo storage, and reseeded the unfixed collection. Both EDA activations were stopped and restored by reset. The AAP instance and its database PVC identities remained unchanged. This was a warm reset and bootstrap, not a new cluster installation or a teardown of every non-AAP platform service.

The complete bootstrap used `MODEL_PROVIDER=litellm`, `LITELLM_MODEL=qwen38-27b`, with thinking disabled for AO and native OpenCode. The credential matched the supplied local file, listed the model and completed a real request. Native and AO smoke checks also returned their expected responses. The reset initially loaded the previous Haiku configuration; Qwen was applied by full bootstrap before the real incident.

GitOps ran at `4a07026881d99c9a483e06cbbdb8028b6223b175`, collection source at `c78d4c8844477087e4499f1a342532bc2fb1f71b`, and AAP/EDA source at `dff2e17460a4d5c584b2bb236068fd279257fb95`, all on `feature/forgejo-eda-remediation`. The reseeded Forgejo main was `66a64d0d6a99e4bae7a6ff903075fdd98166de5b`, with no PR or production `community.general` dependency. No tracked bootstrap implementation was changed for this repeat.

Bootstrap reused the sandbox image built from `b5638df73e53fef48205e21a2a538839e6f21057`, digest `sha256:16be4778a2c05672b4e882273b2927c9f14a811dbfcb09a6595a166a0726dbf6`. The real native sandbox ran as an unprivileged UID and exposed all eight requested pinned collections. Its Ansible Core was **2.21.4**; AAP's supported execution environment actually ran **2.16.19**. Omnigent was **0.15.0**, OpenCode **1.18.32**, and the native SDK was `@ai-sdk/openai-compatible`.

The fresh RHEL 9.8 guest served HTTP 200 in the intended **Permissive/default_t** baseline. That established a working starting point, not an Enforcing fix. The incident task was unchanged before the run, except for the new incident/RCA payload. It already specifies SELinux package names, facts, label guidance and test commands; this is a guided implementation rehearsal, not an unguided investigation.

## Reset and bootstrap timing

Reset ran from **16:18:21.499 to 16:33:33.714 UTC**, taking **15m 12.214s**. Complete bootstrap ran from **16:34:22.654 to 16:45:36.683**, taking **11m 14.029s**. The gap was **48.940s**. Reset start to ready baseline was **27m 15.184s**, including that gap; the two commands themselves totaled **26m 26.243s**.

Reset's actual VM deletion job took **18.044s**, generic test-VM cleanup **8.005s**, and AAP configuration **113.638s**. The recreated Backstage pod took **140s** to become Ready, including approximately 73s in plugin initialization and 11s in RAG initialization. These measurements overlap the reset and must not be added to its total. The reset observer started late; its backfilled early markers are not treated as measured phase boundaries.

Bootstrap phase boundaries were observed within approximately one second. Job durations are separately measured API intervals and overlap the phase table.

| Bootstrap phase | Interval UTC | Elapsed |
|---|---|---:|
| Inputs and prerequisites | 16:34:22.767–16:34:28.769 | 6.002s |
| GitOps checks | 16:34:28.769–16:34:37.772 | 9.003s |
| Identity preparation | 16:34:37.772–16:34:59.780 | 22.008s |
| Application rollout | 16:34:59.780–16:35:01.781 | 2.001s |
| Identity readiness and Forgejo hydration | 16:35:01.781–16:36:05.804 | 1m 04.024s |
| Reuse sandbox image | 16:36:05.804–16:36:12.807 | 7.003s |
| AAP configuration and EDA readiness | 16:36:12.807–16:40:21.890 | 4m 09.083s |
| AO integration and workflow publication | 16:40:21.890–16:41:22.910 | 1m 01.020s |
| Provision RHEL VM, including refreshes | 16:41:22.910–16:42:47.944 | 1m 25.033s |
| Install nginx, including refreshes | 16:42:47.944–16:44:53.990 | 2m 06.047s |
| Webapp and monitoring checks | 16:44:53.990–16:45:21.001 | 27.010s |
| Homepage navigation, widgets and OIDC | 16:45:21.001–16:45:36.683 | 15.682s |

The actual configuration job took **78.522s**, VM job **40.944s**, and nginx job **69.250s**. At bootstrap completion, all **15** Argo applications were Synced/Healthy and both EDA activations were running. No DiskPressure intervention was needed during this warm bootstrap.

The native smoke check took **5.938s**. The deployed AO question workflow took **21.921s**, including login and polling; its model activity took **10.615s**. These are latencies, not output-rate measurements.

## Automatic incident timing

The timer began at **16:50:48.647 UTC**, immediately before `bash bootstrap/bootstrap.sh aap launch webapp_selinux_enable`. The command took **67.348s**, including refreshes. The actual fault job took **6.078s**, switched the guest to Enforcing, and finished at **16:51:50.850**. An independent origin probe returned **403/probe_success=0**. The initial Forgejo main remained unfixed.

| Milestone | UTC | Since break command |
|---|---|---:|
| Fault job completes | 16:51:50.850 | 1m 02.203s |
| Alert begins pending | 16:52:12.675 | 1m 24.028s |
| Alert becomes firing | 16:53:12.675 | 2m 24.028s |
| Alert-triggered AO webhook job is created | 16:53:23.236 | 2m 34.590s |
| RCA workflow is created | 16:53:29.820 | 2m 41.173s |
| Forgejo issue is created | 16:54:03 | 3m 14.353s |
| Forgejo-triggered AO webhook job is created | 16:54:04.308 | 3m 15.661s |
| Remediation workflow is created | 16:54:10.181 | 3m 21.535s |
| Native session handoff completes | 16:54:44.915 | **3m 56.269s** |
| Agent starts checkout | 16:54:58 | 4m 09.353s |

The alert has a one-minute pending period and a 15-second rule evaluation interval. Alertmanager's group wait was 10 seconds. This run's first observed send succeeded; there was no manual webhook delivery, issue creation or session creation.

| Automatic activity | Interval UTC | Elapsed |
|---|---|---:|
| Alert → AO AAP webhook job | 16:53:23.480–16:53:30.274 | 6.794s |
| Audit collection AAP job | 16:53:31.236–16:53:37.366 | 6.130s |
| RCA workflow overall | 16:53:29.820–16:54:08.653 | 38.833s |
| RCA audit activity | 16:53:30.479–16:53:41.721 | 11.242s |
| RCA model activity | 16:53:41.830–16:53:57.327 | 15.497s |
| RCA issue activity | 16:53:57.475–16:54:08.631 | 11.157s |
| Issue creation AAP job | 16:53:58.157–16:54:03.969 | 5.812s |
| Forgejo → AO AAP webhook job | 16:54:04.562–16:54:10.772 | 6.210s |
| Remediation workflow overall | 16:54:10.181–16:54:44.915 | 34.734s |
| Backstage feature preparation | 16:54:10.608–16:54:13.758 | 3.150s |
| Create native session | 16:54:13.876–16:54:14.866 | 0.991s |
| Send task and await handoff | 16:54:15.039–16:54:44.893 | 29.854s |

The issue webhook initiated the second workflow while the first workflow was completing its issue activity. These spans overlap; summing both workflow durations would misstate the wall time.

Qwen's RCA identified nginx's `httpd_t` access to a `default_t` document as the reason Enforcing caused the outage. It suggested relabeling and then adding a persistent file-context rule if needed. Bare `restorecon` cannot establish a custom mapping for a nonstandard `/web` root; the implementation still needed to prove persistent policy and labels through tests.

## What the native model did

Before the first human correction, the primary session made **98 tool calls and 74 assistant request records**, plus one internal research helper. It read roughly 28 files, queried module documentation and repeatedly inspected Ansible fact-collector internals. It made **no collection edits**, started **no full Molecule lifecycle**, and submitted **no PR**.

It recovered from an invalid direct `ansible-doc` tool call by using Bash. Two Galaxy installs used the unsupported `--output-path` option, with pipelines that masked the failures. It later forced reinstallation of dependencies that were already preloaded. Exploratory Python commands also failed on a nonexistent collector attribute and a syntax error. These were visible command failures; no human was needed to correct those individual calls.

At **17:05:10**, it invoked the native `task` tool to research the CentOS image's SELinux facts and installed packages. The child attempted a read-only DataSource query and a tool-availability query. Both remained blocked on permission requests. Inspection of the installed Omnigent forwarder showed that it filters events by the parent's exact native session ID before dispatching permission handlers; child requests therefore did not reach that handler. No child command completed and no permission check was bypassed.

An Omnigent interrupt at **17:09:57** returned without stopping the native-owned work. The operator aborted the child and parent through the supported native API at **17:11:21**, preserving their history. Handoff to abort took **16m 37.060s**; the child request was pending for approximately **6m 11.9s**. This was a failed unattended attempt before the later cluster shutdown.

Three human messages then constrained work to the existing session and flagged production dependency compatibility. The agent began editing at **17:12:15**, first changing `galaxy.yml`, then test requirements, nginx defaults and main tasks. A new `roles/nginx/tasks/selinux.yml` existed by the last source observation. The original session and checkout were retained; the operator did not write the candidate's Ansible content.

The first dependency declaration, `community.general >=8.0.0`, allowed incompatible newer versions. The replacement, `>=12.6.2,<12.7.0`, was also incompatible: that release line requires Core >=2.17, while **2.16.19 is older than 2.17**. The agent's own query returned that requirement but labeled it suitable for Core 2.16. A third message required semantic version/specifier checks and complete Galaxy pagination.

It eventually found `community.general 11.4.9` requiring >=2.16, then repeated release-history and collector queries. The same compatible release was rediscovered after compaction. Before the shutdown, the latest observed source still declared the incompatible 12.6 range. The selected minimums are directly checkable in the official Galaxy metadata for [general 11.4.9](https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/community/general/versions/11.4.9/), [posix 2.2.2](https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/ansible/posix/versions/2.2.2/) and [kubernetes.core 6.6.0](https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/kubernetes/core/versions/6.6.0/). Finding a compatible release was not evidence that the candidate had actually selected and tested it.

## Provider speed and context growth

Three serial direct streaming requests each supplied **67 input tokens** and generated **256 output tokens**, with temperature zero, thinking disabled and usage reporting enabled. They shared most of the prefix. Each ended at the token cap. Generated benchmark text was not retained.

| Sample | Whole request | First content | Approximate decode | Output / whole request |
|---|---:|---:|---:|---:|
| 1 | 10.247s | 0.425s | 26.007 tok/s | 24.984 tok/s |
| 2 | 10.376s | 0.556s | 26.010 tok/s | 24.673 tok/s |
| 3 | 10.189s | 0.365s | 26.002 tok/s | 25.124 tok/s |

Mean approximate decode rate was **26.006 tok/s**; mean whole-request output rate was **24.927 tok/s**. Decode uses `(completion_tokens - 1) / (last content time - first content time)`. These are short-context provider samples, not native-agent throughput or a controlled comparison with Haiku.

The native logs reported a user token limit of **400,000**, zero remaining tokens, and reset times approximately 60 seconds later. Eleven such errors were captured by **17:32:32**. Several short-output turns spanned 63–125 seconds; the longest recorded turn also waited on the helper. Turn spans include tool execution, queueing and backoff, so they cannot be interpreted as decode times or attributed entirely to throttling.

| Native usage snapshot | Reported input | Reported output | Largest request input | Quota errors observed |
|---|---:|---:|---:|---:|
| After first attempt, 17:11:56 | 2,712,261 | 7,297 | 52,884 | 4 |
| Before compaction, 17:25:55 | 5,911,106 | 16,604 | 74,572 | 9 |
| Before shutdown, 17:32:32 | 6,197,596 | 19,304 | 74,572 | 11 |
| Final captured, 18:32:03 | 11,502,200 | 39,304 | 99,014 | 15 |

These are cumulative reported usage across repeated requests, not unique context tokens or a billing estimate. Reported reasoning and cache counters were zero; the cache counters do not establish whether the provider internally reused prefixes. The final capture contains 231 records with reported usage. It includes work resumed after shutdown and work triggered by the duplicate review message. A historical pending Bash record remained after the abort; that database status does not prove a command was still executing.

The effective native custom model advertised **context=0/output=0**, with no explicit compaction setting. The operator interrupted the current request and asked the native client to summarize at **17:26:11**. The call returned at **17:29:33**, taking **3m 22.433s**, including further token-limit errors. A human message resumed the same session at **17:31:12**. A subsequent input was **21,700 tokens**, approximately **70.9% smaller** than the preceding maximum. This reduced observed request size; it did not complete the repair or prevent the model from repeating its release lookup.

## Interventions and interruption

| Action | UTC | Why it was needed |
|---|---|---|
| Reset initially used the old provider configuration | Before 16:34:22 | A read-only archival query failed before the operator edited `.env`; full bootstrap selected Qwen before the incident. The earlier complete Haiku transcript was retained. |
| Retry local native smoke check | 16:36:29, then 16:37:04 | Unsupported Podman tmpfs option failed before any model call; corrected command passed. |
| Poll completed baseline AAP command again | After 16:46:49 | The command was successful before events arrived. Polling recovered the same result; no second launch. |
| Ineffective Omnigent interrupt | 17:09:57 | Did not stop native-owned child work. |
| Abort child and parent through native API | 17:11:21 | Unforwarded child permission requests blocked the parent. |
| Corrective human message 1 | 17:11:57 | Continue alone, implement and validate; honor actual AAP Core 2.16.19. |
| Corrective human message 2 | 17:14:26 | An unbounded dependency range still allowed unsupported releases. |
| Corrective human message 3 | 17:19:02 | Selected general 12.6 despite its >=2.17 metadata; require proper version checks and pagination. |
| Abort current request and summarize native context | 17:26:11–17:29:33 | Repeated research grew input to 74.6k and hit token limits. |
| Human resume message | 17:31:12 | Continue the existing checkout after compaction and run actual validation. |
| Cluster API and routes became unreachable | After last successful 17:33:46 observation | User confirmed the workshop cluster had been stopped and was restarting. This is separate from the preceding agent failures. |

At **17:33:46**, Forgejo still had no generated PR and Omnigent had one top-level session. No completed full Molecule lifecycle had been captured. At **17:36:53**, Forgejo and Omnigent TCP connections timed out while Galaxy returned HTTP 200; a later check also showed API, ingress and host SSH ports timing out while GitHub and Galaxy connected.

The API port was reachable by **17:46:05**, its readiness check passed by **17:47:30**, and session reads succeeded at **17:49:01**. Omnigent initially restarted after OIDC discovery returned 503, then recovered without a configuration patch. The expired sandbox retained its home PVC. One further human message resumed the same session at **17:49:50**; handoff returned at **17:50:10**, and the checkout, uncommitted changes and native database survived. All 15 Argo applications were again Synced/Healthy and both EDA activations running by **17:50:40**. The guest restarted automatically from its retained disk. These observations measure recovery milestones, not the exact instant the external shutdown started or ended.

The restart message also supplied the already verified dependency matrix. By **17:50:40**, the candidate declared `community.general >=11.4.9,<12.0.0`. That corrects the observed release-line mismatch; the later independent check confirmed installed metadata and functional validation separately.

## Validation after restart

The earlier actual scoped lint at **17:18:38** failed with `LINT_EXIT=2`, reporting the nonexistent `ansible.posix.sefcontext`. Its trailing `echo` returned zero to the Bash tool. The later role used `community.general.sefcontext`; scoped lint passed at **17:54:28.611–17:54:37.169** in **8.558s**, overlapping the **0.700s** collection build at **17:54:31.812–17:54:32.512**. The explicit result markers were zero.

The first complete `make molecule` attempt ran at **17:54:42.482–17:56:25.932**, taking **1m 43.450s**. Convergence failed because facts were gathered only when package installation reported a change. The image already had those packages, so the role skipped gathering and failed `ansible_selinux is defined`. Molecule cleaned up and destroyed the VM. The actual marker was `EXIT=2`, despite another enclosing Bash zero caused by the final `echo`.

Without a new human message, the agent made fact gathering unconditional. Its second complete lifecycle ran at **17:56:42.967–17:58:43.010**, taking **2m 00.043s**, and returned `EXIT=0`. Dependency, syntax, create, prepare, converge, idempotence, verify and destroy passed. The second convergence reported **changed=0**; assertions checked Enforcing, `httpd_sys_content_t`, HTTP 200 and the nginx worker account.

Review of that passing candidate found two remaining blockers: the role did not ensure all required SELinux bindings/tools, and `restorecon -R` with `changed_when: false` hid actual relabels. Passing on an image with preinstalled packages did not establish fresh-host dependencies. At **18:00:06**, a human message returned these findings and required fresh lint/build/full Molecule results covering the corrected candidate. The operator did not patch the role. Two further review messages corrected an invented `restorecon` output prefix and a missing `policycoreutils-python-utils` dependency required by the selected general release. The operator did not edit the candidate.

All seven real `make molecule` lifecycles are below. Every invocation ran the only scenario, nginx. Successful runs completed dependency, syntax, create, prepare, converge, idempotence, verify and destroy. The second convergence reported no changes. Model commands sometimes ended with `echo`, so the actual result markers and phase output were checked separately from the enclosing Bash exit.

| Attempt | UTC interval | Elapsed | Result and reason |
|---|---|---:|---|
| 1 | 17:54:42.482–17:56:25.932 | 1m 43.450s | Failed convergence: conditional fact gathering; cleanup passed. |
| 2 | 17:56:42.967–17:58:43.010 | 2m 00.043s | Passed after the agent made gathering unconditional. |
| 3 | 18:00:02.205–18:01:55.808 | 1m 53.603s | Passed with namespaced facts. |
| 4 | 18:03:46.842–18:05:41.785 | 1m 54.943s | Passed after adding bindings and verbose relabel output; review still found the wrong output prefix. |
| 5 | 18:08:02.096–18:09:54.406 | 1m 52.310s | Passed with the observed `Relabeled` prefix. |
| 6 | 18:13:14.922–18:15:09.048 | 1m 54.126s | Passed with the final policy utilities dependency. This candidate was reviewed and merged. |
| 7 | 18:23:27.856–18:25:22.297 | 1m 54.441s | Repeated after duplicate delivery of the last review message, without a new operator request. |

The first PR appeared at **18:11:24**, **1h 20m 35.353s** after the break. It still needed the fresh-host dependency correction. The final candidate, `a8e7189612a4520c1b1edd46b138a634a8ebe58a`, was published to that existing PR at **18:18:40**. A bare `git push` failed with exit 128 because it lacked authentication. The model recovered using `demo-goldenpath pr`; the operator did not publish its code.

The operator's independent lint and build took **7.387s** and **0.533s**, returned actual exit zero, and matched all seven changed files against the immutable PR head. Both production and test declarations selected supported dependency ranges. Installed general **11.4.9**, posix **2.2.2** and kubernetes.core **6.6.0** each require Core >=2.16 and satisfy their declared ranges. Production uses Core **2.16.19**; the sandbox uses **2.21.4**.

## Human merge and live recovery

Alert maintenance was enabled at **18:21:26–18:21:28**, after the real alert, handoff and reviewed PR. The guarded squash merge succeeded at **18:21:58**, producing `76c320af6e16dbd3d335ac93c0316cb1a56efad9`. Forgejo main matched that merge, the incident closed, and the source branch was removed. The agent never merged its own PR.

The operator launched `bash bootstrap/bootstrap.sh webapp nginx` at **18:26:13.430**. It finished at **18:30:05.559**, taking **3m 52.128s** including project and inventory refreshes. The actual nginx job ran **18:29:26.574–18:30:02.944**, taking **36.370s**. Three project updates took **50.656s**, **57.313s** and **52.075s**; those updates overlap inventory work and must not be added again to the command total.

The playbook still sets Permissive before invoking the role. The fixed role then creates the persistent context rule, relabels both `/web` and `/web/index.html`, and ends in Enforcing. The live job correctly reported relabeling as a change. This repeat needed **one** human recovery launch. It proves the final state, while retaining a temporary Permissive interval during deployment.

The independent read-only guest check completed at **18:30:36.473**. It confirmed RHEL 9.8, Enforcing, both paths labeled `httpd_sys_content_t`, the local `/web(/.*)?` rule, no changes proposed by a dry-run relabel, nginx running in `httpd_t`, and no permissive exemption for that domain. All **14** packaged nginx/runtime files matched the reviewed head. The production cache contained the supported dependency versions, and the recovery job emitted no unsupported-collection warnings. `galaxy.yml` is excluded by collection packaging; dependency metadata was checked separately.

Alert maintenance was removed at **18:30:42.808**. At **18:31:06.494**, the origin probe returned **200/probe_success=1**, Alertmanager held **zero** matching alerts, including silenced/inhibited records, all **15** Argo applications were Synced/Healthy, both EDA activations were running, and one top-level Omnigent session remained. Break to that proof took **1h 40m 17.847s**; merge to proof **9m 08.494s**; reset start to proof **2h 12m 44.995s**. These include operator gaps. The earlier job-finish timestamp shows when deployment itself completed.

The last review message appeared a second time at **18:21:19**, with identical content despite one recorded API submission. It triggered another lint/build/Molecule run and attempted PR publication after the source branch was deleted. The cause of duplicate delivery was not established. The operator stopped that extra activity through the native API at **18:29:46–18:29:47**. An initial attempt used the runner endpoint and returned 404; the native endpoint accepted the abort. No new repair instructions were sent.

Other observer corrections were read-only: a nested quoting error was fixed, a command classifier stopped counting commit text containing `make molecule` as a test invocation, and a cache check excluded the packaged-out `galaxy.yml`. Two optional Core probes were rejected by AAP before execution; the probe with the required SSH credential succeeded. These corrections changed observation, not the deployed repair.

The [prompt appendix](2026-10-09-qwen-prompts.md) preserves the automatic task and RCA, three corrective messages, two resume messages, three review messages, smoke/benchmark prompts and visible helper input. It records duplicate delivery and excludes model reasoning and the internal compaction summary. The [JSON evidence](evidence/2026-10-09/qwen-repeat.json) preserves clocks, counters, validation attempts, merge guards and recovery checks. Raw transcripts and workload logs remain in ignored local artifacts.

## Improvements supported by this run

1. **Make the single-agent boundary effective in the native harness.** Disable the `task` capability for this demo until child-session permissions are forwarded correctly. Verify the synthesized native configuration, rather than assuming user configuration was imported. This would prevent the observed helper deadlock without weakening permissions or introducing test serialization. Correct interrupt handling should also be tested against native-owned work.

2. **Provide trustworthy runtime and dependency checks through the Makefile.** A `make doctor` target can show AAP and sandbox Core versions, resolved collection paths and installed runtime metadata. A generic dependency check should compare the candidate's requirements with the actual production Core using semantic specifiers, and constrain ranges to supported release lines. AGENTS.md should point to those checks. This would catch both dependency mistakes before a PR and replace repeated release-history research with a reproducible validation result, without prescribing a SELinux repair.

3. **Configure and verify native context budgeting.** Supply accurate provider model limits and verify how Omnigent passes them to OpenCode. Add a tested compaction policy or tool-output pruning before repeated 50–75k inputs exhaust the observed token window. Manual compaction reduced one later input to 21.7k, but its own call took over three minutes. Raising the provider limit alone would not fix the permission deadlock or unnecessary research.

4. **Make functional checks the implementation checkpoint.** The prompt already names the technical fix in considerable detail. Require the model to produce a minimal candidate and use scoped lint/build/`make molecule` failures to guide further investigation. Give it a concise environment report and documented module output once. This targets the repeated collector inspection and duplicate release queries without adding more instructions about the exact fix.

5. **Reduce recovery-job overhead and preserve Enforcing throughout.** The preceding Haiku test needed deployment plus a separate enforcement launch because nginx's playbook establishes a Permissive baseline. Qwen now finishes recovery with one human-launched job, but its playbook still begins in Permissive. Refresh the reviewed artifact once, deploy while preserving Enforcing, and assert persistent policy, labels and origin HTTP. Preserve loaded-file digest checks when reducing dependency fetches. Haiku's six fetches totaled **6m 07.244s**; that is measured overhead, not a guaranteed saving from a cache change.

6. **Make queued message delivery idempotent.** Persist a stable message identifier across retries and verify that an accepted review event reaches the native session once. The duplicate caused another complete validation cycle and attempted publication after merge. Measure acceptance and delivery separately so a queued response does not conceal repetition.

The intended sequence completed through a reviewed human merge and one human recovery job. The automatic handoff worked, but agent execution needed substantial intervention. The helper permission stall, context growth, repeated compatibility mistakes and duplicate prompt delivery still prevent a dependable unattended repair demonstration.
