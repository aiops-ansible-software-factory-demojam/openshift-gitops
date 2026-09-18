# Automation orchestrator workflows

`sandbox-hello-world-direct-api.json` is the exported definition of the live
`sandbox-hello-world-direct-api` prototype. It uses HTTP request nodes to call
the in-cluster Kubernetes API directly: create a one-shot `Sandbox`, wait for
its command to exit, read the pod log, and delete the `Sandbox`.

Credential IDs in exports are installation-specific. After importing this file
into another orchestrator instance, select that instance's `agent-sandbox-api`
HTTP Bearer Token credential on all three HTTP request nodes before publishing.

The worker must trust the OpenShift API CA. This release of the
`AutomationOrchestrator` CRD has no supported worker environment or volume
fields, so the live prototype mounts a generated
`automation-orchestrator-http-ca-bundle` ConfigMap at
`/var/run/orchestrator-http-ca`. The bundle combines the platform trust bundle
with the namespace's `kube-root-ca.crt`, preserving both public HTTPS and
Kubernetes API trust. `../reconcile-sandbox-prototype.sh` creates the encrypted
runtime credential, imports or updates this definition, and applies the
operator-owned worker CA patch without storing either secret in Git.
