# Automation Orchestrator

This child application installs the standalone Automation Orchestrator. Its
workflow worker is allowed to call the internal Omnigent Service. Bootstrap
reconciles and publishes `workflows/omnigent-dispatch.yaml` after the Argo CD
rollout and the Omnigent Deployment become ready:

```bash
bash cluster/automation-orchestrator/reconcile-omnigent-workflow.sh
```

The manual workflow accepts a task, calls `POST /v1/sessions` with
`host_type: managed`, then sends the task to the seeded OpenCode agent. Omnigent
creates and removes the OpenShell sandbox. The workflow has zero retries on both
POST requests so a network retry cannot create a second session or task.
