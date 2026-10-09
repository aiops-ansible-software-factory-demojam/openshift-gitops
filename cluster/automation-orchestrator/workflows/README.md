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
Existing clusters migrate to dispatch credential type `Demo AAP configuration v4`;
the earlier type stays intact because AAP forbids editing schemas already in use.

## Blackbox alert to issue

A firing `WebappDown` alert reaches EDA through Alertmanager's authenticated
event stream. The `webapp-alert-issue.yml` rulebook in `demojam-ansible` launches
`call_ao_webhook`, which calls the `alertmanagealert` AO trigger. An ingress
network policy lets AAP reach AO's internal UI/API service. The workflow reads
`pull_audit_logs`'s `affected_host_log_output` artifact and passes the
model's diagnosis to `webapp_alert_issue` alongside the original alert payload.
The issue job reuses an existing open incident when Alertmanager sends repeats.

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

`MODEL_PROVIDER` in `.env` selects LiteLLM or OpenCode Go. Go uses an internal
LiteLLM proxy to add required headers and translate the default model's calls
to Responses. Use `OPENCODE_GO_PROTOCOL=chat` for a Go Chat Completions model.
Edit `.env` and run `make model-config` to switch providers in AO and Omnigent.
Reconciliation publishes workflows without executing demo jobs.

Implementation lives in [bootstrap/bootstrap.sh](../../../bootstrap/bootstrap.sh);
`../reconcile-omnigent-workflow.sh` is an alias. Integration host allowlists
are separate from workflow HTTP and OIDC settings, with TLS verification enabled.
