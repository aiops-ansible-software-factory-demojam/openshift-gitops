# Demo script: Lightwell and nginx

A five-minute walkthrough for **exactly three presenters**, using one recorded,
complete dual-application run. Each presenter owns one uninterrupted 100-second
section, including their screen actions and transition. There are only two
speaker handoffs. The narration is balanced in length; rehearse at a measured
pace and use the remaining time for the indicated visual pauses.

| Time | Presenter | Section | Screen ownership |
| --- | --- | --- | --- |
| 0:00–1:40 | Presenter 1 — host | Introduce the factory, establish both baselines, trigger both incidents | Architecture, Homepage, application baselines and trigger evidence |
| 1:40–3:20 | Presenter 2 — Lightwell | Follow the Python CVE from discovery through tested, approved deployment | Python AO execution, Forgejo PR, AAP acceptance/approval, invoice results |
| 3:20–5:00 | Presenter 3 — nginx | Follow the SELinux outage from alert through tested recovery; close | nginx AO execution, Forgejo PR, independent tests, AAP recovery and monitoring |

## Before the presentation

All three presenters use the same verified run and agree on the two screen-control
handoffs. Open the required tabs in story order and keep a visible progress strip:
**Detect → Author → Test → Review → Deploy → Verify**. Presenter 1 begins with
screen control; Presenter 2 takes it at 1:40; Presenter 3 takes it at 3:20. Each
presenter handles their own cues. The other two remain silent during that section.

Prepare these views before recording or presenting:

- The [architecture XML](diagrams/demo-architecture.drawio) and
  [workflow XML](diagrams/demo-workflow.drawio), opened in Draw.io.
- Homepage, both application baseline results, and the recorded commands that
  triggered each incident after the same reset/bootstrap.
- Python discovery/router evidence, its actual release-lock PR, independent AAP
  acceptance, human merge, native approval, deployment proof and final invoice results.
- nginx's alert/RCA, actual code and regression-test diff, independent validation,
  human merge, AAP recovery, enforcing-mode check and resolved monitoring alert.

The five-minute presentation compresses elapsed work; it is not a five-minute
live execution. Label cuts with measured waits from that run. The latest clean
reset-to-completion run took 66.8 minutes, including operator actions; do not label
that entire interval as model or test time. Show baseline and recovery captures
in their actual order, without mixing attempts or inventing timestamps. During a
live presentation, play the captured checkpoints instead of starting a second
incident or pretending approval/deployment completed instantly.

Use the [current-state record](stable-demo-rehearsal.md) for source refs and scope.
This script describes AWS RHEL guests and LiteLLM/MaaS inference as used in the
latest clean run. It does not claim OpenShift AI or CNV was demonstrated. Keep
credentials and private configuration out of every displayed terminal.

## Presenter 1 — establish the problem and start both paths

**Own the stage from 0:00 to 1:40.** Finish on both incident executions; hand off
once to Presenter 2. Do not return to the microphone later.

### 0:00–0:25 — introduce the shared factory

**Stage direction:** Show the architecture diagram. Point to the OpenShift
management plane, then the two separate production hosts. Keep the model endpoint
visible without opening its credential configuration.

> Today we are following two incidents through the same Ansible software factory:
> a vulnerable Python invoice application and an nginx outage caused by SELinux.
> They run on separate RHEL hosts. OpenShift runs the shared management plane,
> and our model endpoint is provided through MaaS. Both will recover without
> weakening their security or review gates.

### 0:25–0:50 — explain ownership and gates

**Stage direction:** Switch to workflow page **01 Walkthrough**. Trace both rows
once; point out the different recovery gates. Do not open individual job details.

> Automation Orchestrator coordinates the work, Developer Hub prepares contribution
> branches, and the coding agent proposes changes. Ansible Automation Platform runs
> deployment and validation jobs. People retain control of review and production.
> We will show both recoveries, including the checks that make each result credible.

### 0:50–1:15 — establish both baselines

**Stage direction:** Show the captured normal invoice result, then the regression
PDF's bounded timeout. Switch once to nginx's baseline HTTP 200 and Permissive
mode. Keep the two host names/groups visibly distinct.

> First, the baselines: ordinary invoices work, but the regression document times
> out with the vulnerable dependency. On the other host, nginx serves HTTP while
> SELinux is permissive. These are independent failures; deploying both applications
> does not trigger either incident. Each needs its own event.

### 1:15–1:40 — trigger both and hand off

**Stage direction:** Show the recorded `make invoice-trigger BACKEND=aws` and
`bash bootstrap/bootstrap.sh aap launch webapp_selinux_enable` results from this
run. Show Python detection starting and nginx's backend HTTP 403/failed probe.
At **1:40**, pass screen control to Presenter 2 with the Python AO tab selected.

> We start invoice detection and separately enable SELinux enforcing on the nginx
> host. Its probe now fails, while Python detection gathers dependency evidence.
> Both paths are running. Presenter Two will follow Lightwell from the vulnerability
> finding to the approved Python release.

## Presenter 2 — Lightwell discovery to verified Python release

**Own the stage from 1:40 to 3:20.** Tell the entire Lightwell story in one block.
End on verified invoice processing, then hand off once to Presenter 3.

### 1:40–2:05 — find the approved remediation

**Stage direction:** Show `invoice_check`, `invoice_discover`, and `invoice_route`
in the Python detection execution. Highlight the observed package/version, pinned
advisory revision, selected Lightwell artifact and `app_patch` result.

> Ansible observes the installed dependency and application behavior. Its Lightwell
> role uses standard modules to match pinned advisory evidence with a compatible
> package from the authenticated index. The CVE router selects the approved patch
> path. A timeout alone does not identify a vulnerability or prove a fix.

### 2:05–2:30 — author and independently test

**Stage direction:** Trace the incident webhook through EDA to Developer Hub and
Omnigent. Open the actual Python PR diff, then the independent acceptance result.
Label the elapsed test wait rather than playing it in real time.

> The incident reaches the coding agent through Forgejo and EDA. Developer Hub
> prepares its branch. Here, the agent updates the release lock; the deployment
> machinery already exists. Independent AAP acceptance tests the published commit
> on fresh RHEL nine and ten guests, including regression behavior and rollback.

### 2:30–2:55 — show the two human gates

**Stage direction:** Show the successful `invoice/ec2-validation` status and human
merge. Switch to the recorded `invoice_promote` execution: expand the release
check, human approval, recheck and deployment nodes. Show the exact source binding.

> After acceptance passes, a human reviews and merges the PR. A separate native
> AAP approval authorizes production. The reusable promotion workflow checks the
> release contract before and after that approval, then deploys the tested source
> and exact artifact. It creates no new workflow for this release.

### 2:55–3:20 — prove recovery and hand off

**Stage direction:** Show the installed Lightwell version, wheel checksum and
matching source revision. Replay the same regression PDF and a normal invoice
successfully; show the completed workflow and closed incident. At **3:20**, give
screen control to Presenter 3 with nginx's alert/RCA execution selected.

> The portal now processes the same regression document and normal invoices.
> The deployed version, checksum and source match acceptance, and the incident
> closes after verification. Failed validation would stop this flow. Presenter
> Three will show how the nginx incident reaches recovery through a different
> deployment gate.

## Presenter 3 — nginx diagnosis, tested recovery and close

**Own the stage from 3:20 to 5:00.** Stay with nginx through recovery, then close
the presentation. No further speaker or screen-control handoffs occur.

### 3:20–3:45 — follow the alert into diagnosis

**Stage direction:** Show the recorded `WebappDown` alert and EDA handoff, then AO's
RCA and the Forgejo incident. For this AWS run, show the AAP audit-facts path.
Use MCP evidence only if it actually appears in the selected run.

> nginx stopped serving because enforcing SELinux blocked its document root.
> The failed probe raises an alert; EDA calls Automation Orchestrator, which gathers
> audit evidence and records the diagnosis in Forgejo. That incident's opening
> webhook starts authoring. The agent receives evidence rather than an instruction
> to disable SELinux.

### 3:45–4:10 — inspect the fix and its tests

**Stage direction:** Open the nginx PR's SELinux changes and added Molecule
assertions. Show independent build, installation, lint, unit and full RHEL 9/10
Molecule results, including idempotence, verification and cleanup. Label test waits.

> The agent proposes the SELinux configuration change and adds regression assertions.
> We independently test the exact published commit, using an isolated source export
> and fresh RHEL nine and ten hosts. Build, lint, unit tests, idempotence and
> enforcing-mode verification must pass before a person merges the change.

### 4:10–4:35 — merge and recover through AAP

**Stage direction:** Show the recorded human review/merge, followed by the single
`webapp_nginx` recovery job. Highlight the existing wrapper and successful job
result. Keep this distinct from Python's native approval workflow.

> nginx uses an operator-controlled recovery launch. After reviewing the evidence
> and merging, the operator runs the existing AAP nginx job once. It deploys the
> reviewed collection while preserving enforcing mode. This path does not use
> Python's native approval workflow, and the coding agent never deploys production.

### 4:35–5:00 — prove both outcomes and close

**Stage direction:** Show nginx's Enforcing result, internal HTTP 200, successful
probe and resolved alert. Finish on workflow page **01 Walkthrough** beside the
Python release evidence. Hold the final view through **5:00**; stop together.

> We finish with evidence: nginx returns HTTP two hundred with SELinux enforcing,
> and its alert resolves. Python processes both invoice tests with the approved
> Lightwell release. Two incidents used shared orchestration and separate application
> changes, with tested commits, human decisions and verified recovery for both.

## Rehearsal cues

- Start a visible five-minute timer. Presenter changes occur only at **1:40** and
  **3:20**; include the spoken handoff in the outgoing presenter's allocation.
- Rehearse each 100-second block independently. Cut screen navigation or shorten
  narration within that block rather than borrowing another presenter's time.
- Keep the architecture overview short. Follow Python to completion before
  switching back to nginx; do not interleave their individual jobs on stage.
- Use only the actual PR changes and actual recorded evidence. A release-only
  Python PR does not mean the agent authored the prebuilt release/rollback framework.
- If a demonstrated gate failed, identify the failed attempt. Use the complete
  clean run for the recovery story; do not splice a passing result onto a failed run.
- Present only the router's `app_patch` branch here. Alternative containment and
  review routes can be discussed from workflow page 05 during questions; they
  were not live containment demonstrations in this run.
