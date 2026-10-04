# Automation Orchestrator

Automation Orchestrator (AO) coordinates the issue-to-PR demo. It asks the
internal Backstage feature gate to validate the Forgejo issue, run the
Developer Hub template, and confirm `feature/issue-N` exists. Only then does
it create an Omnigent session and send the task to `automation-developer`.
Repeat dispatches reuse the prepared branch.

## Configure and run

Bootstrap configures AO after its workloads and Omnigent are ready. To refresh
integrations and publish the checked-in workflows, run from the repository root:

```bash
make ao-configure
make demo-hydrate     # Find the starter issue number
make demo ISSUE=N     # Replace N with that positive number
```

The demo prints AO execution and Omnigent session IDs. AO finishes once
Omnigent accepts the task; the agent continues asynchronously. Inspect the
session for checks and the PR URL. See the [workflow guide](workflows/README.md)
for model questions and AAP job execution.

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
