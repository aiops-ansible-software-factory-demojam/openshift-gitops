# Agent sandbox sessions

This application installs reusable session configuration, not an agent. It uses
the Red Hat operator's `v1beta1` SandboxTemplate → SandboxWarmPool → SandboxClaim
API and executes commands through Kubernetes `pods/exec`. No HTTP router or
public execution endpoint is deployed.

## What GitOps manages

- `agent-sandboxes`: isolated session namespace, token-free `sandbox` service
  account, resource quota, default resource limits and NetworkPolicies.
- `agent-sandbox-clients`: trusted client/cleanup namespace. Its
  `sandbox-provisioner` service account may create/delete claims and exec into
  session pods, but cannot create pods, change templates or read Secrets.
- `python-kata` template: digest-pinned UBI Python 3.12 with Bash and Git,
  `runtimeClassName: kata`, arbitrary non-root UID, read-only root filesystem,
  dropped capabilities, 2Gi ephemeral workspace and 512Mi temporary directory.
  Requests: 250m CPU/512Mi memory; limits: 2 CPU/2Gi memory per session, plus
  Kata runtime overhead. Ansible is not included in this starter image.
- `python-kata` warm pool: **zero replicas initially**. Set to one once a worker
  is ready. The namespace permits at most four claims and six sandbox objects/
  pods, including idle pool inventory; aggregate resource quotas also apply.
- Cleanup CronJob: every ten minutes, deletes claims at least one hour old,
  even if a client omitted its expiry. It runs in the client namespace so exec
  access to session pods cannot expose the cleanup pod's Kubernetes token.
  The template also caps pod lifetime at two hours, including time spent idle
  in the pool. Idle pods may therefore be replaced periodically.

Runtime-created claims, sandboxes and pods are deliberately absent from the
GitOps resource list. ArgoCD must not recreate expired sessions. Deleting a
claim deletes its owned sandbox/pod; collect outputs before cleanup. No PVCs,
shared credentials, host mounts or elevated SCC grants are provided.

## Worker enrollment

`cluster/sandboxed-containers-operator/cluster-kataconfig-kataconfig.yaml` enables
local Kata only on nodes labelled `sandbox.demo/enabled=true`, with the worker
role and without either control-plane role label. GitOps does not label Nodes.
There is no NFD dependency or automatic hardware eligibility check: first
confirm the worker/platform supports local Kata. Peer pods are not configured.

On the demo cluster, after hardware verification, enroll one worker at a time.
This is a deliberate live operation that may drain and reboot that worker:

```bash
oc whoami --show-server
oc whoami
oc label node YOUR_WORKER sandbox.demo/enabled=true
oc get kataconfig cluster-kataconfig
oc get mcp kata-oc
oc get runtimeclass kata
```

Wait for the selected worker to be ready, the machine-config pool update to
finish, and KataConfig's ready node count to reflect it. Then change
`python-kata-sandboxwarmpool.yaml` to `spec.replicas: 1` and publish. The warm pool
health check stays Progressing until a sandbox is ready. With zero replicas it
is intentionally Healthy/paused, which does not imply Kata is operational.

For an already bootstrapped cluster, rerun the bootstrap Job as described in
the root README to install the new warm-pool health customization.

## Networking

Session pods have no direct inbound access and can reach only OpenShift DNS
(TCP/UDP 53 and 5353) and Forgejo pods on TCP 3000. Clone using the internal URL
`http://forgejo-http.forgejo.svc:3000/OWNER/REPO.git`. DNS includes OpenShift's
post-DNAT port. Verify DNS and clone access on the target network.

Public internet, package downloads, LLM endpoints, AAP and other cluster APIs
are denied by default. Add narrow destination policies when the demo flow is
known; network policy does not restrict repository paths or HTTP operations.
Use an appropriately scoped Forgejo credential if a private repository needs
access. The current template projects no credentials.

Trusted clients can reach TCP 443/6443 for API access plus DNS. Their policies
are separate from session policies. The agent consumer belongs in the client
namespace with `serviceAccountName: sandbox-provisioner` and explicit token
mounting. Its Role is namespace-wide within `agent-sandboxes`; this is a shared
demo service identity, not per-user isolation. Do not run untrusted session
commands in the client namespace.

## Consumer contract and smoke test

The consumer creates a `SandboxClaim` referencing `warmPoolRef.name: python-kata`,
with an absolute `lifecycle.shutdownTime`, `shutdownPolicy: Delete` and
`ttlSecondsAfterFinished: 60`. Wait for Ready, read `.status.sandbox.name`, exec
into that pod's `workspace` container, collect files, and delete the claim.
Template environment overrides are disabled. Allow up to ten minutes for cold
startup during the first run. The existing smoke script demonstrates this
contract and also handles cleanup when a command fails:

```bash
bash scripts/sandbox-smoke.sh
```

It needs `oc`, Bash, GNU `date`, and an authenticated identity with the client
Role's permissions. Run it from the repository root after the pool is ready.
It verifies Kata selection, non-root execution, absence of a service-account
token, Python/Git, file round-trip, and claim/sandbox/pod deletion. It does not
verify network-policy enforcement or prove resistance to VM escape.

To inspect installation without starting a session:

```bash
oc -n agent-sandboxes get sandboxtemplates,sandboxwarmpools,sandboxclaims
oc -n agent-sandboxes get sandboxes,pods,resourcequota
oc -n agent-sandbox-clients get cronjob sandbox-cleanup
```

Agent/backend integration, eligible worker selection and any additional tools
or credentials remain demo-specific. All manifests can be rendered without
either decision. No live worker enrollment or session test was performed when
this configuration was authored.

API reference: [Agent Sandbox quickstart](https://agent-sandbox.sigs.k8s.io/docs/use-cases/examples/quickstart/).
