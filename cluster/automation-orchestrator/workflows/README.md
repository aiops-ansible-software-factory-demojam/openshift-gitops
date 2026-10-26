# Automation Orchestrator workflows

These YAML files define one manual CVE-detection workflow and three EDA webhook workflows.
Bootstrap publishes them; `make ao-configure` validates and creates or updates every `*.yaml` here by
its `name`. An unchanged definition keeps its version. Runtime IDs and
credentials are supplied during configuration; secrets never appear in the YAML.

Node and trigger `position` values preserve the demo walkthrough layout from the
AO editor. Copy layout changes back into these definitions before reconciliation.
Bootstrap generates session-sharing steps from the enabled demo users; their
saved positions live in `session-sharing-layouts.json`, keyed by workflow name
and step ID. Additional sharing steps use the default layout until customized.
Keep runtime credentials, integration IDs and user identities out of layout data.

Declare referenced webhook fields in each EDA trigger's `input_schema`, just as
for manual triggers. The AO editor checks `${trigger.field}` references against
this schema before publication, even when backend validation accepts the same
workflow without it. The incident workflows require `issue_number`; the audit
workflow requires the `alert_payload` object. Keep their existing webhook paths
and authorized service-account binding when editing the schema.

The invoice polling loops use native boolean expressions such as
`read_pr.body.ready == False`. AO evaluates them after the first iteration;
they are conditions, not substitutions performed before the poll executes.
After polling, `read_candidate` confirms the eligible PR and supplies the
candidate SHA/number to validation, review and deployment checks. This avoids
referencing loop-body outputs from later steps, which the editor incorrectly
rejects as non-upstream references. Existing node positions are retained; the
confirmation step sits above the candidate polling loop.

Run the commands below from the repository root after
[bootstrap](../../../README.md).

| Definition | What it does | Run it |
| --- | --- | --- |
| [rootcause.yaml](rootcause.yaml) | Investigates with MCP audit evidence, falls back to AAP facts when unavailable, and creates one Forgejo issue | AAP's `call_ao_webhook` job with `ao_webhook_path: alertmanagealert` |
| [omnigent-remediation.yaml](omnigent-remediation.yaml) | Tracks the nginx fix through authoring, exact human merge, native AAP approval and verified deployment | Forgejo issue webhook through EDA and `call_ao_webhook` with `ao_webhook_path: forgejo-issue-remediation` |
| [invoice-security-detect.yaml](invoice-security-detect.yaml) | Observe the dependency, discover approved candidates and reconcile the incident | `make invoice-trigger BACKEND=aws` |
| [invoice-security-remediation.yaml](invoice-security-remediation.yaml) | Track authoring, independent validation, human merge, approval, deployment and verification | Existing Forgejo invoice issue webhook through EDA |

`bootstrap/bootstrap.sh` creates or reuses the `demojam-eda-webhook` AO service
account before AAP configuration. Its client credentials are preserved in
`automation-orchestrator/demojam-eda-webhook-client` and passed through AAP's
dispatch credential to the inventory-defined webhook credential. Expired,
disabled, or stale clients are replaced; a disabled service account stops setup.
Workflow reconciliation binds the EDA trigger to that local account. Bootstrap
and maintenance commands need no continuation scripts or manual credential edits.
Existing clusters migrate to dispatch credential type `Demo AAP configuration v6`;
the earlier type stays intact because AAP forbids editing schemas already in use.

## Blackbox alert to issue

A firing `WebappDown` alert reaches EDA through Alertmanager's authenticated
event stream. The `webapp-alert-issue.yml` rulebook in `demojam-ansible` launches
`call_ao_webhook`, which calls the `alertmanagealert` AO trigger. An ingress
network policy lets AAP reach AO's internal UI/API service. The workflow passes
the completed diagnosis to `webapp_alert_issue` alongside the original alert.
The issue job reuses an existing open incident when Alertmanager sends repeats.

When MCP is enabled, `airca` runs first with nine selected native diagnostic
tools. It reads `/var/log/audit/audit.log` through `read_log_file`, requesting
20 lines, then correlates actual AVC entries with nginx/service/resource
diagnostics. Audit reads use the non-root account's read permissions, preserved
by auditd rotation. There is no custom collector, snapshot or SELinux MCP tool.
A successful read sets `auditEvidenceAvailable=true`; a denied, empty or
unavailable read sets it false. Missing AVC entries in a bounded tail do not
rule out SELinux, and the diagnosis must identify that limitation.

The stock server supplies HTTPS, JWT authentication and tool authorization.
The policy selects tools and localhost; service/journal filters and log sizes
retain upstream behavior. The 20-line request is a workflow instruction, not
a custom enforced response cap. Raw audit reads can include unrelated events.

A failed/timed-out primary or unavailable MCP audit evidence routes through
`auditlogs` and then `airca_fallback` with no tools. Only this branch runs the
privileged AAP collector. Its compact facts enter the fallback prompt and its
completed diagnosis reaches `createissue_fallback`. Both publication paths are
exclusive, including when the primary completes but reports unavailable audit
evidence. Raw stdout and failed invocation traces never enter a prompt.

There are no script nodes. `APP_SCRIPT_NODES_ENABLED=false` remains reconciled
across caller processes. The shipped invocation API hardcodes 10,000 prompt
characters, below the separate workflow setting's 100,000-character default.

Initial bootstrap publishes an audit-only workflow before the guest exists.
After AAP installs the guest service, authenticated discovery resolves tool
UUIDs and binds an explicit runtime credential through
`integration_connections`. The integration's management credential is also
configured for health checks. All other discovered tools are disabled. An
unchanged tool selection preserves IDs and therefore does not create an
unnecessary workflow version. Disabled mode binds no tools and removes the
failure branch, leaving `auditlogs → airca → createissue`; audit evidence remains
compact and script execution remains disabled.

See the top-level README for `WEBAPP_MCP_ENABLED`, credential/certificate
lifecycle, maintenance commands and validation limits. MCP never applies
remediation; review/merge and AAP recovery remain the normal demo boundary.

To exercise the flow on the demo VM, run AAP's `webapp_selinux_enable` template.
Enforcing SELinux blocks nginx's demo document root and the blackbox probe
returns HTTP 403. Allow the one-minute alert rule and Alertmanager's delivery
timers to run, then check EDA, the AO execution, and the Forgejo incident.
After independently testing and merging the PR, approve its `webapp_promote`
execution and verify `make webapp-verify` plus the absence of an active
`WebappDown` alert. This test deliberately interrupts
the demo webapp until it is restored.

## Incident to fix PR

`bootstrap/bootstrap.sh` provisions the separate
`demojam-forgejo-issues` event stream and `demojam-forgejo-remediation`
activation through AAP config-as-code. It publishes the AO workflow before
registering Forgejo's issue webhook. The persistent token is stored in
`forgejo/forgejo-eda-webhook` and passed into AAP's dispatch credential; it is
independent of Alertmanager's token. The hook uses Forgejo's encrypted
Authorization header and HTTPS to the AAP event-stream endpoint.

EDA accepts only newly opened, open collection issues with
`<!-- demojam-webapp-outage -->` and `Root Cause:` in their body. Edits,
comments, closed/reopened issues, starter issues, and PR events do not launch
agents. The existing RCA workflow includes the diagnosis before creating the
incident, so its opening webhook already carries the root cause.

AO re-reads the issue through Backstage, prepares `feature/issue-N`, creates
an `automation-developer` session with the configured model, shares it with
enabled demo users, and submits the task. The agent must preserve SELinux
enforcing, add a regression check, run `make molecule`, and submit
the collection fix as a PR. It does not merge or modify the application VM.
The AAP handoff job publishes `ao_execution_id` for following the AO execution
and session. Follow Omnigent for the PR and AO for merge, production approval
and deployment verification.

To update an installed demo, publish the changes, hydrate the selected Ansible
source branch, then run `make aap-configure`. This applies both EDA listeners,
publishes AO workflows, and reconciles the hook. Bootstrap and demo reset run
the same setup automatically. Reruns preserve the token and update the existing
hook. Duplicate opening deliveries reuse the incident claim and do not start another
author or deployment. HTTP job
and session launches have no automatic retries.

## Incident to authoring

EDA supplies the required positive `issue_number` after detection creates an
incident. Backstage validates it and confirms `feature/issue-N` before AO creates
the session. The machine credential is exchanged for a native Omnigent token,
and enabled users from `DEMO_USERS_FILE` receive read access to the session.
Follow [Omnigent](../../omnigent/README.md) for the checks and PR, and AO for the
review, approval and verified deployment stages.

The manual issue-number dispatcher and its launcher were early test scaffolding
and are removed. Bootstrap removes an unused installed copy on reconciliation.
If it has execution records, bootstrap disables it and retains that audit history.
The invoice detection workflow retains its separate manual detection trigger.

## Model configuration

`AO_MODEL_PROVIDER` in `.env` selects LiteLLM or OpenCode Go for AO;
`AO_MODEL` selects its decision/RCA model. Empty fields inherit the shared
`MODEL_PROVIDER` and that provider's model defaults. Go uses an internal
LiteLLM proxy to add required headers and translate the default model's calls
to Responses. Use `AO_MODEL_PROTOCOL=chat` for a Go Chat Completions model,
or `anthropic` for Claude Haiku (`claude-haiku-5-5`). Bootstrap selects the
matching LiteLLM backend for AO. `AO_QWEN_REASONING_EFFORT` controls Qwen
reasoning independently, falling back to `QWEN_REASONING_EFFORT`.
Omnigent uses its own `OMNIGENT_MODEL_PROVIDER`, `OMNIGENT_MODEL` and
`OMNIGENT_MODEL_PROTOCOL`; it can run Go Haiku while AO uses LiteLLM Qwen.
Provider keys/endpoints remain shared defaults with optional consumer overrides
such as `AO_MODEL_API_KEY` and `OMNIGENT_MODEL_ENDPOINT`.
Edit `.env` and run `make model-config` to apply both consumers' selections.
Reconciliation publishes workflows without executing demo jobs.

Implementation lives in [bootstrap/bootstrap.sh](../../../bootstrap/bootstrap.sh);
`../reconcile-omnigent-workflow.sh` is an alias. Integration host allowlists
are separate from workflow HTTP and OIDC settings, with TLS verification enabled.

## Continuous invoice remediation

The existing `invoice-security-detect` trigger and Forgejo → EDA webhook are
unchanged. `invoice-security-remediation` now keeps one execution running from
the authoring handoff through production verification:

1. Developer Hub prepares the issue branch. A repeated opening delivery that
   finds an existing Python issue branch does not start another author or rollout;
   follow the original execution. The single-replica helper serializes preparation
   per incident and uses Recreate updates to avoid overlapping claim owners. The
   branch is the durable checkpoint across helper restarts. Webapp handoff behavior
   is unchanged.
2. Native AO do-while and wait nodes observe the non-draft incident PR through the
   read-only feature gate. The branch, repository and base are fixed; model text
   is never used to select a PR or source SHA.
3. AAP publishes a pending required check, independently tests the exact head,
   then publishes success only for trusted RHEL acceptance. Failed tests publish
   failure and stop the flow. A launch failure with no job ID fails closed.
4. AO waits for a human review/merge. A changed head, unmerged closure, ambiguous
   PR or missing main ancestry stops orchestration. The workflow never merges.
5. `invoice_prepare_release` rechecks merge and trusted acceptance and returns a
   public immutable release contract. AO launches the reusable `invoice_promote`
   workflow with that contract and the exact tested `scm_branch`. AAP checks the
   contract, waits for human approval, rechecks it and then runs `invoice_deploy`.
   No release-specific project, credential, job template or workflow is created.
6. A trusted read-only AAP gate requires successful approval and deployment nodes
   and the actual deployed SHA/wheel. Application checks then require the exact
   approved release and successful business/regression behavior before the
   existing issue reconciler closes the incident.

Polling uses durable AO timers, not script nodes or sleeping AAP jobs. Each PR
and human-merge wait is bounded to 2,880 observations spaced 30 seconds apart
(about 24 hours plus API time). Validation allows two hours; configuration allows
30 minutes; production execution allows two hours and retains its separate
30-minute AAP approval deadline. Timeouts and rejection never authorize deployment.
Mutating AAP nodes have zero automatic retries. Investigate an uncertain launch
before starting another execution.

These are linked code changes: reconcile the feature-gate ConfigMap and update the
trusted `demojam-ansible` project, run `make invoice-configure BACKEND=aws`, then
`make ao-configure`. Do not reseed either application collection during an active
incident. Publishing changes does not exercise the flow or approve production.
The legacy `invoice-validate`, `invoice-promote` and `invoice-verify` commands
remain operator recovery paths. Inspect existing branch/session/job ownership
before recovery; do not redeliver an incident to create a second rollout.

The invoice detection workflow now routes independent CVE evidence through
`invoice_route`: approved application fix, approved temporary service containment,
deferred review or manual security review. Only the application-fix branch creates
an EDA authoring ticket. Other affected findings use a distinct security response
marker and retain an open review. Containment launches the native AAP
`invoice_contain` workflow, with trusted checks on both sides of its human approval.
The coding-agent session and existing remediation trigger are unchanged. See the
[CVE response routing policy](../../../docs/invoice-lightwell-demo.md#cve-response-routing).

## Approved nginx recovery

`omnigent-remediation` now continues after the agent submits its PR. It claims
an incident once, waits for an eligible PR on `feature/issue-N`, captures its head,
and waits for a human to merge that exact PR and commit into main. Drafts wait;
closed, changed, cross-repository or ambiguous PRs stop the flow. Duplicate issue
deliveries cannot start another author or deployment.

The operator independently tests the exact published commit before merging.
The PR must change `extensions/molecule/nginx/tasks/regression.yml` and include it
from the scenario's verification play. The trusted controller playbook
`playbooks/webapp/validate-regression.yml` runs those same assertions against the
original merge base and the published fix on disposable guests. Every original
guest must fail an authored assertion; every repaired guest must pass. A command
or infrastructure error cannot count as the original-code failure. The trusted
suite separately corrupts content labels, restores them from persistent SELinux
policy, and requires enforcing HTTP recovery. Both lifecycles include cleanup.
The operator copies its receipt out of the sandbox and publishes it using trusted
`playbooks/webapp/publish-regression.yml` on the operator machine. Publishing
credentials never enter the coding/test sandbox, and only a `demo-reviewer`
status is accepted. Its exact-head `webapp/regression-validation` status is required by branch
protection and checked again before promotion. A changed filename or a prompt
claim alone cannot establish a passing regression.
After merge, AO launches the reusable native AAP `webapp_promote` workflow with
that commit and incident/PR identities. Its graph is
`validate-release → production-approval → recheck-release → deploy`.
The trusted checks require the matching merged web incident and native execution;
the second also proves the successful approval belongs to this exact run.

`webapp_deploy` checks out the reviewed commit in `webapp-collection` and runs
`playbooks/promote_webapp.yml`. It calls the local nginx role from that checkout,
using `vars/webapp.yml`, after checking the source, contract and exact web-only
host scope. Production collection requirements belong in
`collections/requirements.yml` as well as `galaxy.yml`. After handlers finish,
SELinux must remain enforcing and the configured page must return HTTP 200.
Per-host proof must cover every approved host; AO verifies the actual trusted
gate jobs, approval, deploy template/project/source and recovery artifacts.
Normal blackbox monitoring resolves the outage alert after recovery.

`webapp_nginx` remains the baseline/setup entry point. Do not launch it as an
extra recovery after the approved workflow. The new project, credential and JTs
are configured once by the normal AAP dispatcher, independently of invoice setup.
Pinned jobs bind the approved full SHA to Controller's protected
`awx_job_scm_branch`. `awx_project_revision` is used only without a job override;
it describes the project's default source, which can advance to a merge commit.
The native deployment uses only the web SSH credential; review API access stays
on the trusted controller gates. No per-release AAP objects are created.

Apply/sync the companion source changes and run AAP/AO configuration before using
this path. Updating GitHub PRs alone does not update the running demo.

### CI feedback and completion

Both authoring workflows loop until independent CI passes for the latest PR
head. The author polls `demo-goldenpath ci <issue> --wait`; exit 75 is pending,
not completion. Validators publish diagnostics through the separate trusted
`demo_ci_publish` job. A failed head waits for an agent-authored new commit;
AO does not rerun unchanged failures. It resumes the same idle session with
sanitized diagnostics, while active authors continue without duplicate prompts.
A new head gets a new pending status and full validation. Only a green exact
head can advance to human review and native production approval. This replaces
the previous one-pass authoring/review boundary; infrastructure cleanup failure
still requires operator resolution and cannot produce green CI.
