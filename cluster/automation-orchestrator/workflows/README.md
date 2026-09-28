# Automation Orchestrator workflow

`omnigent-dispatch.yaml` is the portable manual workflow definition. It creates
an Agent Sandbox managed session, then sends its task through Omnigent's
internal Service once the runner can receive it.
`../reconcile-omnigent-workflow.sh` validates, creates or updates, and publishes
it after bootstrap. The machine client credential is stored in Orchestrator;
its value is never stored in this YAML.

After bootstrap, `bash scripts/dispatch-demo-task.sh` at the repository root
calls the published workflow through AO's API and prints the created Omnigent
session ID. The workflow finishes after Omnigent accepts the task; inspect the
session for the OpenCode response.
