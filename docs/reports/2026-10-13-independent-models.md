# Independent AO and Omnigent models — October 13

The automation now accepts separate provider, model, endpoint, credential,
protocol and Qwen reasoning settings for AO and Omnigent. Local configuration
and lifecycle tests pass. Four full bootstrap attempts failed before AO and
Omnigent deployed, so the live mixed-model flow remains untested.

This run selects LiteLLM `qwen38-27b` with low reasoning for AO and OpenCode Go
`claude-haiku-5-5` over Anthropic for Omnigent. AO's per-attempt timeout is
90 seconds. There is no overall incident or coding-session deadline.

## Configuration

```bash
AO_MODEL_PROVIDER='litellm'
AO_MODEL='qwen38-27b'
AO_QWEN_REASONING_EFFORT='low'
OMNIGENT_MODEL_PROVIDER='opencode-go'
OMNIGENT_MODEL='claude-haiku-5-5'
OMNIGENT_MODEL_PROTOCOL='anthropic'
```

Empty scoped overrides inherit the selected provider's shared defaults.
AO uses the LiteLLM endpoint/key; Omnigent uses the OpenCode Go endpoint/key.
Scoped endpoint and API-key overrides also support two accounts on the same
provider. `make model-config` reconciles both selections. Existing coding
sessions keep their startup configuration.

Bootstrap validates both consumers before making model changes or resetting
the demo. It configures AO's integration, bridge, default model and workflow
bindings independently of Omnigent's native SDK and model secret. All new
model-selection and readiness-wait logic is in `bootstrap/bootstrap.sh`.
The existing identity helper calls the new readiness-wait function.

The Enforcing verifier also now waits for AAP's result event after job
completion. It launches `getenforce` once, polls only for a missing result,
and fails immediately if the result is not Enforcing.

## Validation

The local tests cover independent and reversed providers, separate accounts
on the same provider, shared defaults, absent credentials, invalid transport
or reasoning settings, and keeping keys out of native SDK JSON. All nine
model-configuration cases passed.

All four AAP event cases passed: immediate and delayed Enforcing results,
an actual Permissive result, and an absent event. Each launched one command.
The ten existing webhook-client cases and two Forgejo webhook cases passed.
Bash syntax, ShellCheck at warning/error severity and `git diff --check` passed.

Before bootstrap, both selected providers returned HTTP 200 to the submitted
prompt `Reply with exactly: MODEL_READY`:

| Consumer | Model | Request time | Provider-reported usage |
| --- | --- | --- | --- |
| AO | qwen38-27b | 1.282 s | 46 prompt; 24 completion, including 19 reasoning tokens |
| Omnigent | claude-haiku-5-5 | 1.228 s | 23 input; 9 output; 0 thinking tokens |

Bootstrap-created Omnigent settings in the new cluster also matched Haiku,
the Anthropic SDK, the selected Go credential and endpoint, and the absence
of added thinking options. This inspected the Secret, not a running session.

These short probes establish access. They do not measure sustained decoding
throughput or establish that either live application has loaded its settings.

## Bootstrap attempts

The cluster was freshly provisioned, so this run did not reset an existing
demo or retain a previous AAP installation. Local cluster commands used
`~/.kube/config`.

| Attempt | Source | Start UTC | End UTC | Duration | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | c1da055 | 16:16:06.685 | 17:27:51.298 | 1 h 11 m 44.613 s | Exit 1: readiness budget expired before the Omnigent Application existed |
| 2 | 965956e | 17:31:16.051 | 18:34:22.692 | 1 h 3 m 6.641 s | Exit 1: the same startup window expired before Omnigent existed |
| 3 | 965956e | 18:35:30.513 | 18:42:28.635 | 6 m 58.122 s | Exit 2: Keycloak public route readiness window expired |
| 4 | e2b2ccd | 18:49:31.160 | 19:08:12.286 | 18 m 41.126 s | Exit 2: public Keycloak discovery remained unavailable within the extended readiness window |

The four commands consumed **2 h 40 m 30.502 s**. The clock from the first
start to the final failure was **2 h 52 m 5.601 s**, including **11 m 35.099 s**
between commands for diagnosis, source changes and retry setup. These are
bootstrap timings. Incident, inference, candidate validation and recovery
times are unavailable because those stages never started.

Attempt 1's phase markers give this breakdown. Durations run from one printed
phase marker to the next; they include commands and waits within that phase.

| Phase | Duration |
| --- | --- |
| Input and cluster prerequisite checks | 6.927 s |
| Install OpenShift GitOps | 5 m 44.241 s |
| Prepare identity credentials and user catalog | 4 m 50.725 s |
| Start app rollout | 1 m 0.491 s |
| Provision identity, hydrate Forgejo and wait for later applications | 1 h 0 m 2.213 s |

The first attempt reached identity provisioning and Forgejo hydration, then
waited on the app-of-apps rollout. HCO reported a missing
`openshift-virtualization-os-images` namespace, missing CRDs and unready
operator deployments. Pipelines also reported a pending dependency upgrade.
The failed attempt's logs and timings were retained.

Commit `965956e` makes bootstrap create the virtualization image namespace
before the first child sync. The second attempt created that namespace and
reran the whole bootstrap. Namespace creation alone did not restore readiness:
operator restarts, unavailable webhooks and delayed image pulls continued.

The user confirmed provisioning had finished. Read-only checks found the
OpenShift 4.22.16 upgrade had completed at 09:01:39 UTC. The node was Ready
without memory, disk or PID pressure. The API readiness endpoint passed.
Operator and kubelet logs showed repeated liveness-probe failures. Argo's
Healthy label for Pipelines preceded TektonConfig's own Ready condition, so
the label was not treated as proof that Tekton was ready.

A 76.33-second read-only sample of the node's `/proc/stat` showed 70.95%
CPU steal, 20.44% user time, 6.52% system time and 0.89% idle time. The
[kernel documentation](https://www.kernel.org/doc/html/latest/filesystems/proc.html#miscellaneous-kernel-statistics-in-proc-stat)
defines steal as involuntary waiting. This suggests host contention or a
VM CPU cap as a likely contributor to the readiness failures; the host's
allocation has not been inspected. Kubernetes CPU usage alone had understated
the scheduling constraint because it did not include stolen time.
A second sample over 638.24 seconds showed 70.22% steal, so the observation
was sustained across more than ten minutes. The user asked to continue;
the host's CPU allocation and contention remain unverified.
A third sample at 19:15:53 UTC measured 66.90% steal over 37.56 seconds.
CPU scheduling starvation is the strongest lead, rather than a verified
host-level root cause. Direct inspection of the hypervisor's CPU allocation
and contention would distinguish a cap from an overloaded host.

CRI-O recorded a stop request for the sampled virt-operator container at
17:55:26.809 UTC. Its reported exit code 2 followed at 17:55:27. The pod's
events also recorded liveness-triggered restarts. This evidence does not
establish an independent application panic from the exit code alone.

Image pulls and container creation were also slow: virt-launcher took
18 m 54.625 s to pull about 627 MB, and virt-handler took 6 m 53.467 s to
pull about 270 MB. After the pull, virt-handler encountered container-creation
timeouts before becoming Ready. HCO's conversion webhook repeatedly had no
ready endpoints, preventing virtualization reconciliation and later app rollout.

Keycloak's deployment stayed at generation 1 throughout the retries. A restarted
container took about 7 m 57 s to finish startup, longer than bootstrap's former
five-minute public-route wait. Commit `e2b2ccd` extends that wait to fifteen
minutes, covering the container's ten-minute startup probe budget. The fourth
attempt still failed: Keycloak briefly became Ready, exited again, then
encountered container-creation timeouts and an unavailable public discovery
endpoint. Extending the wait corrected a bootstrap mismatch but did not resolve
the recurring cluster failures.
At the final 19:18:40 UTC snapshot, Keycloak was Ready again with two restarts,
while HCO's conversion webhook still had no ready endpoints. AO and Omnigent
Applications were still absent. Readiness recovering after a failed wait does
not turn that bootstrap attempt into a pass.

No fault, RCA workflow, incident webhook, coding task, candidate test, merge
or application recovery ran. No operator pod was manually restarted,
no vendor deployment was patched, and no coding agent received feedback.
There were three bootstrap retries and two bootstrap prerequisite changes before
an incident existed.
Two read-only diagnostic commands were corrected: the node-log timestamp format
and a route lookup that initially read an empty `spec.host`. Bootstrap already
used the assigned route hostname. Neither correction changed a workload.

The [prompt appendix](2026-10-13-qwen-ao-haiku-coding-prompts.md) records the
submitted provider probe and configured coding-agent instructions. The latter
were inspected in the Secret and never delivered to a coding task. No RCA
prompt, incident task prompt or model follow-up was submitted.

## Source branches and pull requests

| Repository | Branch changes from current origin/main | Pull request |
| --- | --- | --- |
| openshift-gitops | 50 commits; 35 files before this report commit. Bootstrap/EDA/AO/Omnigent wiring, sandbox dependency preloads, lifecycle checks, demo skill, reports and independent model configuration | [#40](https://github.com/aiops-ansible-software-factory-demojam/openshift-gitops/pull/40), draft pending live validation |
| demojam-ansible | 2 commits; 10 files. Forgejo issue listener/rulebook and AO handoff; separate permissive setup after provisioning; nginx deployment preserves SELinux mode | [#3](https://github.com/aiops-ansible-software-factory-demojam/demojam-ansible/pull/3), open |
| ansible-collection-demo.webapp | 1 commit; 7 files. `make molecule` discovers and runs all scenarios; nginx is the only scenario; instructions/devfile updated and empty scenario removed | [#3](https://github.com/aiops-ansible-software-factory-demojam/ansible-collection-demo.webapp/pull/3), draft; full lint/build/Molecule checks pending |
| ansible-collection-template | main; no changes | None |

The independent-provider change is commit `c1da055`; its virtualization
namespace prerequisite is `965956e`, and the route-wait adjustment is `e2b2ccd`.
All three changed repositories use `feature/forgejo-eda-remediation`. A fresh
authenticated fetch confirmed none was behind its current `origin/main`.
No GitHub implementation PR was merged. The collection's unrelated lint draft
is not part of this change.

Collection validation confirmed `make -n molecule` expands to
`molecule test --all` and discovers the single nginx scenario. Full native
lint/build/Molecule validation remains pending because the managed sandbox
never deployed. Live verification of AO's loaded integration and workflow,
Omnigent task delivery, the test-gated merge and the single recovery job is also
pending.

The [sanitized evidence](evidence/2026-10-13/ao-qwen-omnigent-haiku.json) contains
the command clocks, phase markers, provider probes and readiness observations.

Credentials, private provider addresses, live workshop hostnames, runtime IDs
and raw native reasoning are excluded from this report.
