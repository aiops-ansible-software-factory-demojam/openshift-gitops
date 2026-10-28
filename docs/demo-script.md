# Demo script: Lightwell and nginx — recorded run walkthrough

A five-minute walkthrough for **exactly three presenters**, using the completed
2026-10-28 AWS run with the module-first authoring guidance. Each presenter owns
one uninterrupted **100-second** section, including screen actions and transition.
There are only two speaker/screen-control handoffs. Follow Python to completion,
then return to nginx; the actual work ran in parallel.

| Presentation time | Presenter | Section | Screen ownership |
| --- | --- | --- | --- |
| 0:00–1:40 | Presenter 1 — host | Architecture, baselines, both triggers and elapsed-time context | Architecture, Homepage, baseline results and trigger evidence |
| 1:40–3:20 | Presenter 2 — Lightwell | Discovery, authoring, two testing stages, merge, approval and verified Python release | Python AO execution, PR diff, independent AAP acceptance, promotion and invoice results |
| 3:20–5:00 | Presenter 3 — nginx | Diagnosis, module-based fix, independent tests, reviewed recovery and closing evidence | nginx RCA, PR diff, Molecule results, AAP recovery and monitoring |

## Before the presentation

Open the tabs in story order. Keep a visible progress strip:
**Detect → Author → Test → Review → Deploy → Verify**. Presenter 1 begins with
screen control; Presenter 2 takes it at **1:40**; Presenter 3 takes it at **3:20**.
The other two presenters remain silent during each section. No further handoff
occurs after Presenter 3 takes over.

Use the [architecture XML](diagrams/demo-architecture.drawio) and
[workflow XML](diagrams/demo-workflow.drawio), opened in Draw.io. Prepare the
actual baseline captures, both AO executions, each PR diff and test evidence,
review/merge records, Python's native AAP approval, and final application results.
The operator-only checkpoint map below helps select the right screens. Use the
[run-specific screen links and navigation guide](demo-screen-links.md) to preload
objects. Each timed block below has exact **View changes** cues. Sign into each
application before presenting; links identify objects but grant no additional access.

### Which clock are we showing?

There are two different clocks: the **five-minute presentation timer** and the
**recorded run elapsed clock**. Put both labels on edited clips; do not imply
that a five-minute walkthrough is a five-minute live remediation.

| Measured interval in this run | Duration | Meaning |
| --- | --- | --- |
| Reset start through final verified recovery/closure | **79.5 minutes** | Includes reset, bootstrap, connectivity retries, both incident paths and operator actions. |
| Reset itself | **12.7 minutes** | Disposable guests, sessions and Forgejo work were reset; AAP history and runtime credentials were preserved. |
| Both incident paths, running in parallel | **35.0 minutes** | Starts when the nginx fault-launch sequence begins; ends at Python's final incident reconciliation. This is not 35 minutes per path or coding time alone. |
| Python independent AAP validation | **14.3 minutes** | Reruns candidate checks and then trusted acceptance on separate disposable guests; includes machine lifecycle and cleanup. |
| nginx independent operator validation | **4.4 minutes** | Exact published source: build, install, lint, units and full fresh RHEL 9/10 Molecule lifecycle. |
| Native Python production approval wait | **About 80 seconds** | Actual time waiting for the operator decision in this execution, not an automatic approval or fixed workflow delay. |

The setup needed three bootstrap retries after Kubernetes API, GitHub and Forgejo
connectivity timeouts. Those failed setup logs remain recorded. Old orphan EDA
jobs were removed before reset; this attempt then had **one coding session per
application**. Both incident paths completed successfully after readiness passed.
Describe this as a successful incident run with disclosed setup retries, not an
uninterrupted first-attempt bootstrap. The earlier **66.8-minute** rehearsal is a
different run; do not use its timings or footage in this walkthrough.

### Run checkpoint map — elapsed from the same incident-sequence start

Times below are rounded to the nearest second. They identify recorded checkpoints,
not intervals to add together. The nginx fault sequence began first; invoice
detection followed after its HTTP 403 was confirmed.

| Recorded elapsed time | Checkpoint to show |
| --- | --- |
| +00:00 | Start nginx fault-launch sequence after readiness. |
| +01:16 | nginx fault job finishes; backend HTTP 403 and probe failure confirmed. |
| +03:17 | Invoice trigger command has completed; follow its AO detection/remediation execution. |
| +10:57 | Python agent's release-manifest PR is published. |
| +12:51 → +27:10 | Python independent validation runs for 14.3 minutes. |
| +20:24 | nginx agent's PR is published while Python acceptance is still running. |
| +24:03 → +28:26 | Operator independently validates nginx for 4.4 minutes. |
| +28:08 | Python's required validation status is published green. |
| +29:27 | nginx tested PR is merged. |
| +30:11 | Python tested PR is merged. |
| +33:06 | nginx recovery is verified: Enforcing, backend HTTP 200 and healthy probe. |
| +35:00 | Python deployment proof, business checks and incident reconciliation are complete. |

The merges were **44 seconds apart because validation finished close together**,
not because orchestration required waiting for both applications. There was about
one to two minutes of review/API/operator handling after each validation gate.
Do not add the two testing durations to calculate overall elapsed time: they overlap.
When switching from Python back to nginx on stage, label the rewind
**“Meanwhile — nginx path from the same run.”**

### What “independent acceptance” means

1. **Agent development tests:** the coding agent runs checks while preparing its
   change. Those results help development but do not authorize production.
2. **Independent published-commit validation:** after PR publication, validate the
   exact committed source again. Python's AO workflow launches AAP to rerun the
   candidate checks plus trusted acceptance maintained outside the author's write
   permissions. It covers fresh RHEL 9/10 guests, artifact identity, normal/security
   regression behavior, idempotence, rollback and destruction. nginx's operator
   exports the published SHA into isolated source, installs separately, and reruns
   build/install, lint, units and full RHEL 9/10 Molecule testing.

This repetition is intentional. It checks the submitted commit independently of
the agent's report and workspace. It is not a second coding session, and the agent
was not privately coached or its branch repaired. Python's prebuilt deployment,
provenance and rollback framework was reused; its actual PR changed the release
manifest. nginx's actual PR added SELinux policy tasks and regression assertions.

The requested screen guide intentionally includes this environment's object URLs
and IDs to make the walkthrough clickable. Keep credentials and raw agent reasoning
out of presentation material. The local `.rendered/rehearsals/active-run` pointer
identifies the evidence directory; confirm its run identity before using it because
future resets change that pointer. The evidence was recorded with AWS RHEL guests
and LiteLLM/MaaS `claude-haiku-4-5` for both consumers, not an OpenShift AI or CNV run.
The [implementation-state guide](stable-demo-rehearsal.md) also preserves the earlier
rehearsal; the measured timing table above belongs specifically to this walkthrough.

## Presenter 1 — establish the problem and start both paths

**Own 0:00–1:40.** Set the scene and start both paths; hand off once to Presenter 2.

### 0:00–0:25 — introduce the shared factory

**Stage direction:** Show the architecture. Point to the shared OpenShift management
plane and two separate RHEL production hosts. Show the configured provider label;
do not open model credentials. Overlay **“Recorded AWS run · 2026-10-28.”**

**View changes:** **0:00** open [architecture XML](diagrams/demo-architecture.drawio)
in Draw.io, Architecture page; hold it for this block. At **0:18**, point at the
model-provider box without opening configuration. [Homepage][home] is the fallback
if the diagram was not opened beforehand.

> We are walking through one completed run with two incidents: a vulnerable Python
> invoice application and an nginx outage caused by SELinux. They run on separate
> RHEL hosts. OpenShift hosts the shared management plane, with MaaS providing
> inference. The changes and recovery evidence you see belong to this run.

### 0:25–0:50 — explain the clocks and gates

**Stage direction:** Show workflow page **01 Walkthrough** and the measured-time
card. Keep **“Presentation 5 minutes / incident paths 35 minutes, parallel”** visible.

**View changes:** **0:25** switch to [workflow XML](diagrams/demo-workflow.drawio),
page **01 Walkthrough**. **0:37** switch to this script's [measured-time table](#which-clock-are-we-showing)
or a slide made from it. Keep both clocks labeled.

> The two incident paths ran in parallel and finished in thirty-five minutes,
> including tests, human decisions and deployment. Reset through completion took
> about eighty minutes, including setup retries. This five-minute walkthrough skips
> those waits; it does not claim five-minute remediation. People retain review and
> production control throughout.

### 0:50–1:15 — establish both baselines

**Stage direction:** Show the normal invoice result, then the bounded regression
PDF timeout with PyPDF2 3.0.1. Switch to nginx's baseline HTTP 200 and Permissive mode.
Keep `pythonapps` and `webapps` distinct. These are baseline captures, not new faults.

**View changes:** **0:50** show the saved Python baseline excerpt from the
[local evidence instructions](demo-screen-links.md#local-evidence-views), backed by
[baseline job 2071][python-baseline]. **1:03** switch to [nginx baseline job 2097][web-baseline]
and the recorded HTTP 200/Permissive checkpoint. The live apps are fixed now; use
historical evidence here, not a new fault or a live regression run.

> Ordinary invoices work, but the regression PDF times out with the vulnerable
> Python dependency. nginx initially serves HTTP while SELinux is permissive.
> Bootstrap prepared these baselines without starting incidents. Automation Orchestrator
> coordinates the workflows, Developer Hub prepares branches, and the coding agents
> propose changes in separate sandboxes. Before triggering, we verified both
> baselines, both model consumers, and one running authenticated listener per event stream.

### 1:15–1:40 — trigger both and hand off

**Stage direction:** Show the recorded `webapp_selinux_enable` launch, then its
403/failed-probe evidence, then `make invoice-trigger BACKEND=aws`. Advance the
run clock from **+00:00** to **+03:17**. At **1:40**, give Presenter 2 screen control
with the Python detection execution selected.

**View changes:** **1:15** open [fault job 2113][web-fault], Output; show
Enforcing and the recorded 403/failed-probe checkpoint. **1:27** switch to [AO][ao]
and select the **invoice-security-detect** execution using [execution D1](demo-screen-links.md#ao-executions).
At **1:40**, Presenter 2 takes control of that same AO view. Do not launch either
trigger again during this walkthrough.

> First we enable SELinux enforcing on nginx and confirm HTTP four-oh-three.
> Then we trigger invoice detection. Each event starts its own path; both now
> progress together. Presenter Two will follow Lightwell through the release change,
> independent acceptance, human merge and approved Python deployment.

## Presenter 2 — Lightwell discovery to verified Python release

**Own 1:40–3:20.** Finish the entire Python story before handing off once.

### 1:40–2:05 — find the approved remediation

**Stage direction:** Highlight `invoice_check`, `invoice_discover`, and `invoice_route`.
Show the installed package, pinned advisory revision, selected wheel/checksum and
`app_patch` route. Trace the issue-opening webhook through EDA to the coding session.

**View changes:** **1:40** stay on AO detection D1; trace check → discovery →
router. **1:48** open [Lightwell discovery job 2115][lightwell-discovery] or
[router job 2116][cve-router], Output/artifacts, to show the approved selection.
**1:58** switch to [Python incident #1][python-issue] and identify its structured finding.
Private credential values must stay collapsed; use public job artifacts if task output is redacted.

> Ansible observes the installed package and business behavior, then discovers a
> compatible Lightwell backport using standard modules and pinned advisory evidence.
> The router chooses the approved patch path. Forgejo and EDA carry the incident
> into authoring. In this run, the Python PR was published about eleven minutes
> after the incident sequence began.

### 2:05–2:30 — distinguish both test stages

**Stage direction:** Show the actual release-only diff. Then show agent test output
and the independent AAP job as **two labeled stages**. Overlay **“Independent AAP
validation: 14.3 minutes · recorded +12:51 → +27:10.”** Skip the wait visibly.

**View changes:** **2:05** switch to [Python PR #2 — Files changed][python-diff];
show the release-lock-only diff. **2:12** open [Omnigent][omnigent], select
**Invoice remediation issue 1** with [session S1](demo-screen-links.md#coding-sessions),
and show test tool output. **2:19** switch to [independent acceptance job 2131][python-acceptance],
Output; show the RHEL lifecycle and regression/rollback results. Label the 14.3-minute
skip; keep agent tests and independent acceptance visually distinct.

> The agent updates the release lock and runs development tests. AAP then tests
> the exact published commit again, plus a separate trusted acceptance suite.
> That second stage took fourteen-point-three minutes on fresh RHEL nine and ten
> guests. It checks artifact identity, regression behavior and rollback; the agent's
> report alone cannot satisfy the gate.

### 2:30–2:55 — show merge and production approval

**Stage direction:** Show green `invoice/ec2-validation` at **+28:08**, then the
recorded human merge at **+30:11**. Expand `invoice_promote`: validate, human approval,
recheck, deploy. Label **“Approval wait: about 80 seconds; deploy job: 41 seconds.”**
These job durations exclude surrounding scheduling, synchronization and verification.

**View changes:** **2:30** open [Python PR #2][python-pr], Conversation/checks;
show `invoice/ec2-validation` and the completed human merge. **2:39** switch to
[promotion workflow 2148][python-promotion], its graph/visualizer. **2:47** select
**production-approval (2151)** and show the recorded decision, then point to
[recheck 2153][postapproval-check] → [deploy 2154][python-deploy]. This execution is
already approved/completed; do not click Approve or Relaunch.

> After the required status turns green, a human reviews and merges the PR.
> The existing promotion workflow checks its release contract, waits for native
> AAP approval, rechecks, then deploys. Approval took about eighty seconds here.
> The deployment job itself took forty-one seconds; neither figure includes the
> surrounding orchestration and verification.

### 2:55–3:20 — prove Python recovery and hand off

**Stage direction:** Show installed PyPDF2 `3.0.1+rhlw.1`, matching wheel checksum
and tested source, successful normal/regression checks, completed workflow and closed
incident at **+35:00**. Use captured results; do not restart extraction or approval.
At **3:20**, give Presenter 3 screen control with nginx RCA selected and the
**“Meanwhile — same run, nginx path”** caption visible.

**View changes:** **2:55** open [Python release status][python-status] and show
version, source revision and wheel hash. **3:02** switch to [business check 2158][business-check]
for the recorded normal/regression results, or the matching captured portal results.
**3:10** show [closed Python incident #1][python-issue]. At **3:20**, Presenter 3
opens [nginx incident #1][web-issue] with “Meanwhile — same run” visible. The live
[portal][python-app] is a fixed-state view, not the historical vulnerable baseline.

> At thirty-five minutes, Python's deployment proof, business checks and incident
> reconciliation are complete. The approved Lightwell version, checksum and source
> match acceptance, and the same regression document works. The reusable deployment
> framework already existed. Presenter Three will rewind to the nginx path that
> was running alongside this work.

## Presenter 3 — nginx diagnosis, independent validation and recovery

**Own 3:20–5:00.** Stay with nginx through recovery and close without another handoff.

### 3:20–3:45 — follow the alert into diagnosis

**Stage direction:** Keep the parallel-path caption visible. Show `WebappDown`,
EDA, AO's AAP audit-facts RCA and the incident. Show one coding session for nginx.
Do not substitute optional MCP footage: this run used the audit-facts path.

**View changes:** **3:20** show [nginx incident #1][web-issue], including RCA.
**3:28** switch to [AO][ao], **Check Audit logs, Determine RCA, Create Issue**,
[execution N1](demo-screen-links.md#ao-executions), then [audit-facts job 2119][audit-facts]
if needed. **3:38** open [Omnigent][omnigent], **Webapp outage issue 1**,
[session S2](demo-screen-links.md#coding-sessions). Show tool/test output, not raw reasoning.

> While Python was progressing, nginx's failed probe raised an alert. EDA called
> Automation Orchestrator, which gathered audit facts and recorded the diagnosis
> in Forgejo. That opening webhook started one nginx coding session. The agent
> received the cause and instructions to preserve enforcing mode, rather than
> disable SELinux to restore service.

### 3:45–4:10 — show the module-based fix and retest

**Stage direction:** Open `community.general.sefcontext`, its declared production
dependency, `restorecon` and the added label assertions. Show the published PR at
**+20:24**, then independent logs at **+24:03 → +28:26**. Overlay **“Second test
stage: 4.4 minutes · exact published commit · fresh guests.”**

**View changes:** **3:45** open [nginx PR #2 — Files changed][web-diff]; select
[`roles/nginx/tasks/selinux.yml`][web-policy]. **3:53** select
[`extensions/molecule/nginx/verify.yml`][web-tests] to show label assertions.
**4:01** switch to the saved operator [independent validation log](demo-screen-links.md#local-evidence-views).
There is no AAP job for this operator-run validation; label its 4.4-minute duration.

> The fix uses the existing sefcontext module for persistent SELinux labels,
> followed by restorecon. It adds label regression checks. After the agent's tests,
> the operator independently exports the published commit and reruns build, lint,
> units and Molecule. That took four-point-four minutes, including fresh RHEL hosts,
> idempotence, enforcing-mode verification and cleanup.

### 4:10–4:35 — review, merge and deploy

**Stage direction:** Show independent idempotence passing on both RHEL versions,
then nginx merge at **+29:27** and successful `webapp_nginx`. Label **“Deployment job:
27 seconds; source/inventory refresh and health verification take additional time.”**
Briefly show the two merge timestamps without switching to another application's tabs.

**View changes:** **4:10** stay in that independent log at the successful
idempotence, verify and destroy recap. **4:18** switch to [nginx PR #2][web-pr],
Conversation, to show the reviewed merge. **4:25** open [nginx recovery job 2150][web-deploy],
Output. Keep Python's merge timestamp as an overlay rather than opening another
application's workflow during this block.

> nginx's independent tests pass, including the second converge that proves
> idempotence. The operator reviews, merges and launches the existing AAP recovery
> job. That job takes twenty-seven seconds, with synchronization and verification
> additional. The merges happened close together because tests finished close
> together, not because either flow required waiting for the other.

### 4:35–5:00 — prove both outcomes and close

**Stage direction:** Show Enforcing, internal HTTP 200, probe success and no active
outage alert; nginx recovery was verified at **+33:06**. Finish on both successful
outcomes and **“35 minutes total, parallel paths.”** Hold through **5:00**.

**View changes:** **4:35** show the saved [Enforcing/probe verification log](demo-screen-links.md#local-evidence-views)
and [live nginx page][web-app]. **4:43** switch to [Homepage][home] for healthy probe/alert widgets;
use [OpenShift monitoring](demo-screen-links.md#monitoring-and-final-health) if a widget is unavailable.
**4:51** finish on workflow page **01 Walkthrough** with the two verified outcomes
and 35-minute card. Hold through **5:00**; no further handoff.

> nginx recovery is verified at minute thirty-three: HTTP two hundred, SELinux
> enforcing and a resolved alert. Python finishes by minute thirty-five with its
> approved Lightwell release. Both changes passed independent tests and human
> gates. We have shown one recorded run, with measured waits and verified outcomes,
> rather than treating a PR as recovery.

## Rehearsal cues and questions

- Use the five-minute stage timer; hand off only at **1:40** and **3:20**. Handoffs
  belong to the outgoing presenter's 100 seconds. Speaking lengths are balanced;
  rehearse screen navigation within each block instead of borrowing another's time.
- Put **“Presentation time”** on the stage timer and **“Recorded elapsed”** on the
  run clock. Label skipped waits; use the checkpoint table to avoid mixing runs.
- When asked whether tests ran twice: **yes**. The agent's tests precede a separate
  published-commit validation stage; Python also has trusted acceptance outside
  the author's write permissions. That is intentional, not duplicate authoring.
- The 35 minutes includes operator handling and approval. The 14.3- and 4.4-minute
  test stages overlap; do not add them or claim either is pure model execution.
- Do not claim every generated task perfectly follows the guide. The meaningful
  improvement here is the module-based nginx policy and passing independent
  idempotence. Prompt guidance supplements code review and tests; it replaces neither.
- nginx recovery is an operator-controlled AAP launch, not Python's native approval
  workflow. The automated workflows never approve or merge their own changes.
- Do not portray prebuilt Python deployment/provenance/rollback content as newly
  authored. Its PR changed the release lock; show that actual diff.
- Present the router's `app_patch` branch. Alternative mitigation routes have
  fixture coverage, not a live containment demonstration in this run. Default
  production has one host per app; rollback/canary tests used disposable guests.
- If discussing earlier failures, keep their evidence separate. The previous nginx
  attempt failed idempotence and remained unmerged. This run passed; setup retries
  are disclosed. Do not splice either failed attempt into the recovery footage.

<!-- Run-specific browser object references; no credentials. -->
[home]: https://homepage.apps.cluster.example.invalid
[python-app]: https://pythonapp.apps.cluster.example.invalid
[python-status]: https://pythonapp.apps.cluster.example.invalid/api/status
[web-app]: https://webapp.apps.cluster.example.invalid
[ao]: https://automation-orchestrator-automation-orchestrator.apps.cluster.example.invalid
[omnigent]: https://omnigent.apps.cluster.example.invalid
[hub]: https://rhdh.apps.cluster.example.invalid
[aap]: https://aap-ansible-automation-platform.apps.cluster.example.invalid
[console]: https://console-openshift-console.apps.cluster.example.invalid
[python-issue]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.pythonapp/issues/1
[python-pr]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.pythonapp/pulls/2
[python-diff]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.pythonapp/pulls/2/files
[web-issue]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/issues/1
[web-pr]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/pulls/2
[web-diff]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/pulls/2/files
[web-policy]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/src/commit/fe4cb243c448ed0b17ab11619f8ec36f9c32ef0d/roles/nginx/tasks/selinux.yml
[web-tests]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.webapp/src/commit/fe4cb243c448ed0b17ab11619f8ec36f9c32ef0d/extensions/molecule/nginx/verify.yml
[python-release]: https://forgejo.apps.cluster.example.invalid/demo-owner/ansible-collection-demo.pythonapp/src/commit/178bd0c69a430e019b79dbc424fc7d5c2174bd36/releases/invoice.json
[python-promotion]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/workflow/2148
[python-baseline]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2071/output
[web-baseline]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2097/output
[web-fault]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2113/output
[lightwell-discovery]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2115/output
[cve-router]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2116/output
[python-ticket]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2117/output
[audit-facts]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2119/output
[web-ticket]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2121/output
[python-acceptance]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2131/output
[python-status-job]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2132/output
[prepare-release]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2145/output
[preapproval-check]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2149/output
[web-deploy]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2150/output
[postapproval-check]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2153/output
[python-deploy]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2154/output
[deployment-proof]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2157/output
[business-check]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2158/output
[close-python]: https://aap-ansible-automation-platform.apps.cluster.example.invalid/execution/jobs/playbook/2159/output
