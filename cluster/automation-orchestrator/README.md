# Automation Orchestrator

This child application installs the standalone Automation Orchestrator. Its
workflow worker is allowed to call the Omnigent HTTPS Route. Bootstrap
reconciles and publishes `workflows/omnigent-dispatch.yaml` after the Argo CD
rollout and the Omnigent Deployment become ready:

```bash
bash cluster/automation-orchestrator/reconcile-omnigent-workflow.sh
```

The manual workflow accepts a task, mints a short-lived machine token, calls
`POST /v1/sessions` with `host_type: managed`, then sends the task to the seeded
OpenCode agent. Bootstrap generates the machine client Secret and reconciles an
encrypted HTTP Basic credential in Orchestrator. The workflow has zero retries
on its POST requests so a network retry cannot create a second session or task.
