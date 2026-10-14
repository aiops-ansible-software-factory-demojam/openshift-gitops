# Automation Orchestrator workflows

These YAML files define three manual AO workflows and two EDA webhook workflows.
Bootstrap publishes them; `make ao-configure` validates and creates or updates every `*.yaml` here by
its `name`. An unchanged definition keeps its version. Runtime IDs and
credentials are supplied during configuration; secrets never appear in the YAML.

Run the commands below from the repository root after
[bootstrap](../../../README.md).

| Definition | What it does | Run it |
| --- | --- | --- |
| [omnigent-dispatch.yaml](omnigent-dispatch.yaml) | Prepares an issue branch in Backstage, starts the agent, and requests a PR | `make demo ISSUE=N` |
| [llm-question.yaml](llm-question.yaml) | Asks the configured model a question using a Task Agent node | `make ao-llm-test` |
| [aap-webapp-nginx.yaml](aap-webapp-nginx.yaml) | Runs AAP's existing `webapp_nginx` job in the `demo` organization | `make ao-aap-run` |
| [rootcause.yaml](rootcause.yaml) | Gathers audit logs through AAP, asks the model for a root cause, and creates a Forgejo issue | AAP's `call_ao_webhook` job with `ao_webhook_path: alertmanagealert` |
| [omnigent-remediation.yaml](omnigent-remediation.yaml) | Prepares the incident branch and sends the issue/RCA to Omnigent for a tested fix PR | Forgejo issue webhook through EDA and `call_ao_webhook` with `ao_webhook_path: forgejo-issue-remediation` |

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
network policy lets AAP reach AO's internal UI/API service. The workflow reads
`pull_audit_logs`'s `affected_host_log_output` artifact and passes the
model's diagnosis to `webapp_alert_issue` alongside the original alert payload.
The issue job reuses an existing open incident when Alertmanager sends repeats.

When MCP is enabled, the `airca` RCA agent directly queries the selected
`Demo Webapp Diagnostics` tools and returns `rootCause`, `escalateTo` and
`remediationSteps`. AAP supplies at most 3,000 characters of structured audit
facts: current enforcement mode, collection time, recent AVC operations and
contexts, and explicit truncation/collection limitations. Raw stdout and the
full alert payload are excluded from prompts. Diagnostic tool responses enter
the agent's conversation during execution, and traces stay in AO for inspection.

The primary agent has a 180-second timeout and continues on failure. A condition
routes successful RCA to `createissue`, preserving `airca.result.content`.
A failed or timed-out primary invocation instead runs `airca_fallback` without
tools; its result goes to `createissue_fallback`. These branches are exclusive:
only a completed diagnosis reaches one issue job. The fallback explicitly
reports unavailable live diagnostics and consumes no failed invocation fields.
Unavailable SELECTED tools can fail AO before reasoning starts, so a prompt
instruction alone is not a reliable fallback.

There are no script nodes. `APP_SCRIPT_NODES_ENABLED=false` is reconciled across
the caller processes. The deployed invocation API hardcodes a 10,000-character
prompt limit, even though `workflow_engine.max_prompt_length` is configurable
and defaults to 100,000. Bounding facts at the AAP producer keeps both agent
prompts below the effective limit without enabling worker code execution.

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
Restore the demo with `make webapp-nginx` and verify `make webapp-verify` plus
the absence of an active `WebappDown` alert. This test deliberately interrupts
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
and session. AO completion proves task acceptance; follow Omnigent for the PR.

To update an installed demo, publish the changes, hydrate the selected Ansible
source branch, then run `make aap-configure`. This applies both EDA listeners,
publishes AO workflows, and reconciles the hook. Bootstrap and demo reset run
the same setup automatically. Reruns preserve the token and update the existing
hook. An explicit redelivery of an opening webhook can start another session
on the same issue branch; inspect existing runs before redelivering. HTTP job
and session launches have no automatic retries.

## Issue to PR

Run `make demo-hydrate` to get the starter issue number, then replace `N` above
with that positive number. The required workflow input is `issue_number`.
Backstage validates the issue and confirms `feature/issue-N` before AO creates
the session. The machine credential is exchanged for a native Omnigent token,
and enabled users from `DEMO_USERS_FILE` receive read access to the session.

The launcher prints execution and session IDs. AO completion means the agent
accepted the task; inspect [Omnigent](../../omnigent/README.md) for the checks
and PR URL.

## Model question or AAP job

```bash
make ao-llm-test QUESTION='What is 2 plus 2? Answer briefly.'
make ao-aap-run
make webapp-verify
```

The model command prints its execution ID and answer. The AAP command requires
the webapp to be provisioned, waits for completion, and prints the job ID, URL,
and status. Job launches have no retries; inspect AAP before repeating a launch
whose response was lost.

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
