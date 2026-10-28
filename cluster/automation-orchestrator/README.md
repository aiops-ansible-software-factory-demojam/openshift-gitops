# Automation Orchestrator

Automation Orchestrator (AO) coordinates detection, incident authoring and
approved recovery. EDA delivers newly opened outage issues after the RCA is
included in their body. `omnigent-remediation` asks the internal Backstage gate
to validate the incident and prepare `feature/issue-N`, then starts one shared
Omnigent session. Duplicate incident deliveries do not start another author.

The agent submits a tested PR. After independent operator validation and human
merge, the operator deploys nginx through its existing AAP wrapper and verifies
enforcing HTTP recovery. The invoice workflows retain independent validation,
native production approval and reviewed Python remediation.

## Configure and run

Bootstrap configures AO after its workloads and Omnigent are ready. Refresh the
checked-in workflows from the repository root with `make ao-configure`.
The nginx scenario starts through its real alert path:

```bash
bash bootstrap/bootstrap.sh aap launch webapp_selinux_enable
```

This deliberately introduces the SELinux outage. Follow the alert, RCA, Forgejo
issue, AO execution and Omnigent session. For Python, use `make invoice-trigger`.
The former manual issue-dispatch workflow is removed. See the
[workflow guide](workflows/README.md) for configuration and review gates.

AO uses the operator-managed Route's `/api/v1` API. If that Route is unavailable,
set `AO_USE_PORT_FORWARD=true` to use `svc/automation-orchestrator-ui`, or
`AO_API_BASE_URL` for a custom endpoint. Configuration waits for the API to
return JSON before proceeding.

## Login and credentials

Browser login uses [demo Keycloak](../demojam-keycloak/README.md); demo groups
map to AO's built-in users and admins. The local admin remains the bootstrap
API identity. Login tries `automation-orchestrator-admin-password`, then the
operator's initial-admin-password Secret if needed.

The feature gate uses a dedicated Backstage service token and has no public
Route or Forgejo credential. AO exchanges its stored machine credential at
Omnigent's `/oauth/token` for a bearer token; enabled configured users receive
read access to new sessions. Session creation has zero retries to prevent
duplicates. Inspect the result before repeating a launch with a lost response.

The admin settings allow private-network OIDC because Keycloak ingress resolves
to a private address. Workflow HTTP hosts have a separate allowlist, and TLS
verification stays enabled. Changing `.env` and running `make model-config`
refreshes model settings in both AO and Omnigent.

## Current scope

There are four authored demo workflows: RCA, nginx authoring, CVE detection/router,
and continuous Python remediation. The AO wrappers `llm-question`, `invoice-validate`
and `aap-webapp-nginx`, plus the manual `omnigent-dispatch`, are retired. AAP's
`invoice_validate` and `webapp_nginx` job templates remain required. Platform-managed
integration health/discovery and agent-execution entries are not extra demo flows.

The latest clean rehearsal used LiteLLM/MaaS `claude-haiku-4-5` for both AO and
Omnigent, over Chat Completions. Configuration examples may select other models;
record the actual provider used. See [tested state](../../docs/stable-demo-rehearsal.md)
and [workflow XML](../../docs/diagrams/README.md).
