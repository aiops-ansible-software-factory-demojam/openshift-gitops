# Automation Orchestrator

This child application installs the standalone Automation Orchestrator. Its
workflow worker is allowed to call the Omnigent cluster Service. Bootstrap
reconciles and publishes `workflows/omnigent-dispatch.yaml` after the Argo CD
rollout and the Omnigent Deployment become ready:

```bash
bash cluster/automation-orchestrator/reconcile-omnigent-workflow.sh
```

The script waits for the `AutomationOrchestrator` CR and UI/backend rollouts,
then calls `/api/v1` on the operator-managed Route (nginx in the UI pod proxies
`/api` to the backend). It retries until `GET /auth/providers` returns JSON, so
a briefly unready router or backend no longer surfaces as a cryptic `jq` parse
error. Set `AO_USE_PORT_FORWARD=true` to talk through
`svc/automation-orchestrator-ui` instead, or `AO_API_BASE_URL` for a custom
base URL. Login tries `automation-orchestrator-admin-password` first, then
`automation-orchestrator-initial-admin-password` if the Git-managed password
no longer matches the live admin account.

The manual workflow accepts a task, mints a short-lived machine token, calls
`POST /v1/sessions` with `host_type: managed`, then sends the task to the seeded
OpenCode agent. Bootstrap generates the machine client Secret and reconciles an
encrypted HTTP Basic credential in Orchestrator. The workflow has zero retries
on its POST requests so a network retry cannot create a second session or task.
