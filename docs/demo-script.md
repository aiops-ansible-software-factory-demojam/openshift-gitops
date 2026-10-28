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
The operator-only checkpoint map below helps select the right screens.

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

Keep credentials, private hostnames, runtime IDs and raw agent reasoning out of
committed presentation material. The local `.rendered/rehearsals/active-run` pointer
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

> We are walking through one completed run with two incidents: a vulnerable Python
> invoice application and an nginx outage caused by SELinux. They run on separate
> RHEL hosts. OpenShift hosts the shared management plane, with MaaS providing
> inference. The changes and recovery evidence you see belong to this run.

### 0:25–0:50 — explain the clocks and gates

**Stage direction:** Show workflow page **01 Walkthrough** and the measured-time
card. Keep **“Presentation 5 minutes / incident paths 35 minutes, parallel”** visible.

> The two incident paths ran in parallel and finished in thirty-five minutes,
> including tests, human decisions and deployment. Reset through completion took
> about eighty minutes, including setup retries. This five-minute walkthrough skips
> those waits; it does not claim five-minute remediation. People retain review and
> production control throughout.

### 0:50–1:15 — establish both baselines

**Stage direction:** Show the normal invoice result, then the bounded regression
PDF timeout with PyPDF2 3.0.1. Switch to nginx's baseline HTTP 200 and Permissive mode.
Keep `pythonapps` and `webapps` distinct. These are baseline captures, not new faults.

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

> Ansible observes the installed package and business behavior, then discovers a
> compatible Lightwell backport using standard modules and pinned advisory evidence.
> The router chooses the approved patch path. Forgejo and EDA carry the incident
> into authoring. In this run, the Python PR was published about eleven minutes
> after the incident sequence began.

### 2:05–2:30 — distinguish both test stages

**Stage direction:** Show the actual release-only diff. Then show agent test output
and the independent AAP job as **two labeled stages**. Overlay **“Independent AAP
validation: 14.3 minutes · recorded +12:51 → +27:10.”** Skip the wait visibly.

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

> nginx's independent tests pass, including the second converge that proves
> idempotence. The operator reviews, merges and launches the existing AAP recovery
> job. That job takes twenty-seven seconds, with synchronization and verification
> additional. The merges happened close together because tests finished close
> together, not because either flow required waiting for the other.

### 4:35–5:00 — prove both outcomes and close

**Stage direction:** Show Enforcing, internal HTTP 200, probe success and no active
outage alert; nginx recovery was verified at **+33:06**. Finish on both successful
outcomes and **“35 minutes total, parallel paths.”** Hold through **5:00**.

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
