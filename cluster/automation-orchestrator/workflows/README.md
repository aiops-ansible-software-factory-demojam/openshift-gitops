# Automation Orchestrator workflow

`omnigent-dispatch.yaml` is the portable manual workflow definition. It creates
an Omnigent managed session and sends a task through Omnigent's internal API.
`../reconcile-omnigent-workflow.sh` validates, creates or updates, and publishes
it after bootstrap. The workflow holds no credential or cluster API token.
