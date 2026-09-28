# Automation Orchestrator workflow

`omnigent-dispatch.yaml` is the portable manual workflow definition. It creates
an Agent Sandbox managed session, then sends its task through Omnigent's
internal Service once the runner can receive it.
`../reconcile-omnigent-workflow.sh` validates, creates or updates, and publishes
it after bootstrap. The machine client credential is stored in Orchestrator;
its value is never stored in this YAML.
