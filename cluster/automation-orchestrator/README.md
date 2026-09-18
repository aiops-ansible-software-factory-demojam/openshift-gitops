# Automation orchestrator

This directory owns the standalone Automation Orchestrator installation and
all resources used by its direct Agent Sandbox API prototype. It is applied at
app-of-apps wave 30, after `agent-sandboxes` creates the two target namespaces.

## Direct Agent Sandbox API prototype

The published `sandbox-hello-world-direct-api` workflow uses REST steps against
`https://kubernetes.default.svc` to create a one-shot `Sandbox`, wait ten
seconds, retrieve the pod log and delete the sandbox. Its command is only
`echo hello world`; it does not use an agent, a warm-pool claim or `pods/exec`.
The workflow uses the regular container runtime so it can run before a worker
is enrolled for Kata.

The `automation-orchestrator-sandbox-api` Role grants only direct Sandbox
create/get/delete and pod/log get. The ServiceAccount token Secret manifest has
no credential value in Git: Kubernetes populates it at runtime, and Automation
Orchestrator stores the value in its encrypted `agent-sandbox-api` HTTP Bearer
Token credential.

The workflow definition is under `workflows/`. Reconcile the application-level
credential, workflow and worker CA trust after the GitOps applications are
healthy:

```bash
bash cluster/automation-orchestrator/reconcile-sandbox-prototype.sh
```

The script obtains both required secrets at runtime and never prints them. Set
`AO_ADMIN_PASSWORD` to override reading the initial admin password Secret. It
also regenerates the combined public/Kubernetes CA bundle and reapplies the
operator-owned worker Deployment patch. This is required because the current
`AutomationOrchestrator` CRD has no supported worker environment or volume
fields. Re-run the script after an operator reconcile or upgrade removes that
patch, or after either source CA bundle changes.
