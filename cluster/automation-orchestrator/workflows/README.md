# Automation Orchestrator workflows

These YAML files define three manual AO workflows. Bootstrap publishes them;
`make ao-configure` validates and creates or updates every `*.yaml` here by
its `name`. An unchanged definition keeps its version. Runtime IDs and
credentials are supplied during configuration; secrets never appear in the YAML.

Run the commands below from the repository root after
[bootstrap](../../../README.md).

| Definition | What it does | Run it |
| --- | --- | --- |
| [omnigent-dispatch.yaml](omnigent-dispatch.yaml) | Prepares an issue branch in Backstage, starts the agent, and requests a PR | `make demo ISSUE=N` |
| [llm-question.yaml](llm-question.yaml) | Asks the configured model a question using a Task Agent node | `make ao-llm-test` |
| [aap-webapp-nginx.yaml](aap-webapp-nginx.yaml) | Runs AAP's existing `webapp_nginx` job in the `demo` organization | `make ao-aap-run` |

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
