# Automation Orchestrator workflow

`omnigent-dispatch.yaml` is the portable manual workflow definition. It creates
an Omnigent managed session and sends a task through Omnigent's HTTPS Route.
`../reconcile-omnigent-workflow.sh` validates, creates or updates, and publishes
it after bootstrap. The machine client credential is stored in Orchestrator;
its value is never stored in this YAML.
