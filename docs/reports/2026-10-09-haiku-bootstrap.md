# Haiku bootstrap and incident rehearsal — October 9, 2026

Bootstrap completed on the cluster in `~/.kube/config`, using the OpenCode Go subscription and `claude-haiku-5-5` for AO and Omnigent. The successful retry took **30m 55s**. From the first attempt through completion, including a transport correction and restart, setup took **38m 33s**.

The subsequent SELinux outage reached a tested Forgejo PR in **9m 17s**. Alerting, RCA, issue creation, the Forgejo webhook, EDA/AO, and the native agent handoff ran automatically. The session received one automatic task and no corrective human messages. Review found an Ansible compatibility metadata mismatch that must be corrected before merge. The PR remains open; the application was restored to the permissive demo baseline.

This was one rehearsal. It demonstrates an unattended session-to-tested-PR run, but does not establish a repeatability rate or prove deployment of this candidate to RHEL. The older Qwen runs used different configuration and infrastructure; the time difference cannot be attributed to the model or dependency preloads alone.

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
- **Review blocker:** `galaxy.yml` adds `community.general >=13.5.0`, whose installed `meta/runtime.yml` requires Core >=2.18. The candidate's `meta/runtime.yml:2` and role README still advertise >=2.16. Tests used Core **2.21.4**, so they do not prove the advertised older compatibility. Align the declared minimum before merge.

After review, `make webapp-nginx` and `make webapp-verify` restored and checked the original permissive baseline in **76s**. The candidate was not merged or deployed. Human merge and a human-launched recovery job remain the next steps; a healthy permissive baseline is not proof of the fix under Enforcing.

More node disk headroom should reduce the observed storage wait. A readiness check for authenticated alert ingestion could expose the transient 401 before a rehearsal. A generic validation check comparing production dependency requirements with the collection's declared Ansible minimum would catch the review blocker without prescribing the SELinux implementation.

The [timing evidence](evidence/2026-10-09/haiku-bootstrap.json) excludes runtime IDs, live hosts and credentials. The [prompt appendix](2026-10-09-haiku-prompts.md) preserves both smoke-test prompts and the session's single automatic task. Raw logs and session/tool records remain in ignored local artifacts.
