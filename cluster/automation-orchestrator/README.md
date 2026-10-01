# Automation Orchestrator

This child application installs the standalone Automation Orchestrator. Its
workflow worker is allowed to call the Omnigent and Backstage feature gate
cluster Services. The gate uses a dedicated Developer Hub service token, validates
the issue, invokes its feature template, and waits for the branch before AO
creates a managed agent session. An existing issue branch is reused on a
subsequent dispatch. The gate has no Forgejo credential or public Route. Bootstrap
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

The manual workflow accepts an issue number, waits for the golden path, calls
`POST /v1/sessions` with `host_type: managed`, then sends the task to the seeded
OpenCode agent. Bootstrap generates the machine client Secret and reconciles an
encrypted HTTP Basic credential in Orchestrator. Only the token-exchange node
uses it, to authenticate to Omnigent's native `/oauth/token`; API nodes use the
returned bearer token. Bootstrap adds session read grants for enabled configured
users. The session-create POST has zero retries to prevent duplicate sessions.

Bootstrap also reconciles a generic OIDC provider against the independent
[demo Keycloak](../demojam-keycloak/README.md), using the actual operator-generated Route
for its callback. Demo groups map to Orchestrator's built-in users and admins
groups. The existing admin account remains the bootstrap API identity.

The operator's optional `automation-orchestrator-admin-settings` ConfigMap enables
`APP_OIDC_ALLOW_PRIVATE_NETWORKS` because OpenShift ingress DNS resolves the demo
Keycloak Route to a private address. This setting applies to OIDC providers;
workflow HTTP hosts keep their separate allowlist and TLS verification remains
enabled for the Keycloak provider. A backend annotation ensures an existing
Deployment reloads the settings when this configuration is first installed.
