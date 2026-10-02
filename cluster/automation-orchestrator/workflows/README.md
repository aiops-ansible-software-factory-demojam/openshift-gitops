# Automation Orchestrator workflows

`omnigent-dispatch.yaml` is the portable manual workflow definition. Its
required input is `issue_number`. AO calls the internal Backstage feature gate,
which validates the issue, runs the Developer Hub feature template if the
branch is missing, waits for the Scaffolder task to complete, and confirms
`feature/issue-N` exists. Only then does AO create an Agent Sandbox session
and tell `automation-developer` to implement the issue and open a PR.
`../reconcile-omnigent-workflow.sh` validates, creates or updates, and publishes
it after bootstrap. The machine client credential is stored in Orchestrator;
its value is never stored in this YAML. A token-exchange node obtains a native
Omnigent bearer token, and bootstrap inserts read-sharing nodes for enabled
users from `DEMO_USERS_FILE` before sending the task. This allows those users to
inspect the workflow's session after signing in with Keycloak.

After `bash scripts/feature-demo.sh hydrate`, run
`bash scripts/dispatch-issue.sh 1` at the repository root. It calls the
published workflow through AO's API and prints the Omnigent session ID. The
workflow finishes after Backstage prepares the branch and Omnigent accepts the
task; inspect the session for the checks and PR URL.

`make ao-configure` reconciles credentials and integrations, validates every
`*.yaml` here, then creates or updates and publishes each workflow by its
`name`. An unchanged definition retains its version. Runtime IDs are inserted
by bootstrap; credentials never appear in these definitions.

`llm-question.yaml` asks the `.env` provider a simple question using a native
Task Agent node. `MODEL_PROVIDER` selects LiteLLM or OpenCode Go; bootstrap
registers that provider, discovers and enables the configured model, and uses
the encrypted API-key credential for health checks and execution. LiteLLM is
used directly. For OpenCode Go, bootstrap deploys a pinned LiteLLM proxy inside
the AO namespace: it adds Go's required session/client headers and translates
AO's Chat Completions calls to Responses for the default GPT model. Set
`OPENCODE_GO_PROTOCOL=chat` when selecting a Go Chat Completions model. The
proxy has an internal Service, a generated API key and a Secret holding the
upstream key; bootstrap owns its configuration and lifecycle.

```bash
make ao-configure
make ao-llm-test
make ao-llm-test QUESTION='What is 2 plus 2? Answer briefly.'
```

The run command prints the execution ID and the model's returned answer. To
switch providers, edit `.env` and run `make model-config`; this refreshes both
Omnigent and AO, then republishes workflows with the selected model. Only
`ao-llm-test` executes the question; reconciliation never launches demo jobs.

`aap-webapp-nginx.yaml` dispatches the existing `webapp_nginx` job in the
`demo` organization with its managed inventory and credentials. Bootstrap
registers the AAP gateway integration using the discovered admin credential
(or `.env` AAP overrides). After the webapp is provisioned, run:

```bash
make ao-aap-run
make webapp-verify
```

The command waits for AO completion and prints the AAP job ID, URL and status.
Job launches have no retries so an uncertain response cannot duplicate a job.
All implementation is in `bootstrap/bootstrap.sh`; the legacy reconcile script
is an alias. Integrations use a separate host allowlist from workflow HTTP
requests and OIDC. Bootstrap configures it on backend, worker and background
worker for the selected provider and AAP gateway, retaining TLS verification.
