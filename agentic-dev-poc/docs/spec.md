# Manual-prompt agentic development POC

**Architecture:** Red Hat Automation Orchestrator → REST runner → NVIDIA OpenShell → Kubernetes sandbox on OpenShift → OpenCode.

**Specification version:** 1.0, September 21, 2026.  
**Status:** Researched implementation specification; not deployed or validated on the target cluster.  
**Target:** A separate, otherwise vanilla OpenShift cluster with an existing AO installation. The existing AAP installation remains unused. This project must not depend on `igou-openshift` or other homelab repositories.

## 1. Objective and scope

A user opens an AO workflow, enters a development prompt, and clicks Run. AO starts an isolated OpenCode execution, displays its progress, and retrieves a structured result with generated files and validation evidence. Every run begins with a fresh sandbox and fresh agent state.

The first demonstration uses an empty working directory, optionally initialized with a small, immutable fixture bundled with the application image. No repository URL, GitHub identity, issue, webhook, Git clone, push, or pull request is required. The result is a downloadable workspace and execution report, not a PR.

Included: one manual workflow, one required prompt field, one configured model, one active run, bounded execution, cancellation, output collection, cleanup, and repeatable deployment.

Excluded: AAP job templates or execution environments; OpenShift Virtualization; Kata or other VM RuntimeClasses; Hermes; NemoClaw; GitHub integration; browser IDEs; exposed OpenCode servers; interactive agent approval dialogs; multi-agent scheduling; automatic deployment; general-purpose cluster administration by the agent; HA; and automated resume of an interrupted model session.

No GPU is required for this design: model inference is an external HTTPS service. Local model serving is outside scope.

## 2. Research findings that determine the design

| Finding | Implementation consequence | Evidence |
|---|---|---|
| AO supports manual triggers with JSON-schema inputs. | Use the existing AO Run dialog; do not build another prompt UI. | R1 |
| AO REST steps send ordinary HTTP requests and expose parsed responses. | Make the runner a small REST API; do not run the coding loop inside an AO task-agent node. | R2, R3 |
| OpenShell clients use a gateway and its control protocols. | The REST runner is custom integration code, not an existing AO/OpenShell connector or invented OpenShell REST endpoint. | R7, R8 |
| The Kubernetes driver requires Agent Sandbox CRDs and a controller, which the OpenShell chart does not install. | Install this cluster-scoped dependency before the gateway. | R5, R16 |
| NVIDIA labels the native OpenShift path experimental and documents a privileged SCC grant for the sandbox service account. | This is an evaluation on a dedicated cluster, not a production or restricted-v2-compatible sandbox deployment. | R4 |
| Kubernetes gateway clients need appropriate application authentication, not merely a healthy endpoint or a client certificate. | Use TLS plus an OIDC machine identity for the runner. | R7, R10 |
| OpenShell supplies protected inference routing; OpenCode supports configurable model endpoints and noninteractive runs. | Configure a single API-key-backed model route and run OpenCode directly inside the sandbox. | R9, R12, R13 |
| Default OpenShell Kubernetes workspaces use PVCs. | Supply working storage and explicitly verify cleanup; “temporary task” does not mean “no PVC.” | R15 |

The baseline OpenShell release for this specification is **v0.0.116**, returned by the upstream latest-release API during research (published August 28, 2026). Use Helm chart version **0.0.116** and matching clients/runtime components. Do not combine its chart with unreleased `main` settings or newer runtime-layout instructions. R17.

AO documentation baseline is **2026.8**. The actual installed AO and OpenShift versions are deployment inputs, not facts established by this research. Record them before implementing the workflow.

## 3. Logical architecture

```text
User browser
    |
    | AO Run dialog: { prompt }
    v
Existing Automation Orchestrator
    |
    | HTTPS REST, stored runner credential
    | POST run / GET status / GET result / POST cancel
    v
Trusted REST runner                     OIDC issuer
    |                                     ^     ^
    | OpenShell CLI, TLS + bearer token ---+     |
    v                                           |
OpenShell gateway ------------------------------+
    |
    | Kubernetes compute driver / Kubernetes API
    v
Agent Sandbox CR + controller
    |
    v
OpenShell sandbox Pod + task workspace PVC
    |-- trusted OpenShell supervisor
    |-- untrusted agent process: OpenCode
    |-- fresh writable working directory
    |-- fixed development tools and policy
    |
    | protected HTTPS inference routing
    v
Configured model-provider API

Results: sandbox -> runner artifact store -> AO execution output

All execution/control components above, except the external model API and
possibly an existing identity provider, run on the separate OpenShift cluster.
AAP is installed but has no edge in this flow.
```

The runner launches work; it is not another AI agent. OpenShell performs runtime isolation. OpenCode interprets the task and uses development tools. AO owns the human-visible workflow.

## 4. Components and deployment boundaries

Use these logical namespaces; record actual namespace names in configuration:

| Namespace | Contents |
|---|---|
| Existing AO namespace | Existing AO; new workflow and stored REST credential only. |
| `agentic-poc` | Runner Deployment/Service, runner state and artifact PVC, configuration and client credentials. |
| `openshell` | Pinned OpenShell Helm release, gateway storage, generated credentials, sandbox service account, sandbox Pods/PVCs. |
| `agent-sandbox-system` | Pinned upstream Agent Sandbox controller and its supporting resources. |
| Identity-provider namespace, when needed | A dedicated OIDC service, such as Keycloak; not an AAP execution component. |

Deploy one runner replica with a Recreate strategy and SQLite on a PVC. This intentionally avoids a distributed queue, shared database operator, or concurrent worker coordination.

Deploy one OpenShell gateway with the chart's SQLite/StatefulSet mode. Do not add PostgreSQL, an external queue, cert-manager, a GPU operator, OpenShift AI, Gateway API, or a virtualization operator merely for this POC. An identity provider is required when there is no existing suitable OIDC issuer; its own deployment/storage requirements are separate from OpenShell's.

Agent Sandbox is an upstream CRD/controller installation, not an assumed OperatorHub product. Use a pinned release manifest, not a floating `latest` URL in committed deployment automation. Its supported served Sandbox API must match OpenShell's preflight: `agents.x-k8s.io/v1beta1` or `v1alpha1` for this reference release. R5, R16.

## 5. Authentication and transport

### 5.1 AO to runner

The runner listens on an internal ClusterIP Service over HTTPS. Create a dedicated, rotatable random bearer credential, store it in AO's credential store and in a runner Secret, and attach it to the REST steps. All run, result, artifact, and cancellation endpoints require it. Restrict health responses to non-sensitive status.

Use a certificate valid for the exact runner hostname. Configure trust through the installed AO version's supported mechanism and prove certificate verification from the executing AO worker. Do not disable certificate verification. A public-CA hostname with internal routing is an alternative only when explicitly selected in deployment configuration; it must not become an unauthenticated public endpoint.

Add narrowly scoped NetworkPolicies in both namespaces, taking existing AO operator policies into account. Network reachability and AO's outbound URL validation are separate requirements.

### 5.2 Runner to OpenShell

**Selected profile: internal TLS plus OIDC client credentials.** Keep `server.disableTls=false` and `server.auth.allowUnauthenticatedUsers=false`. Do not use the plaintext, unauthenticated developer profile as an automatic fallback. NVIDIA's OpenShift quickstart demonstrates a weaker private-evaluation setup; this spec deliberately keeps authentication. R4, R7.

Provision an OIDC confidential client named `agentic-poc-runner`, with client-credentials/service-account flow enabled and browser flows unnecessary. Configure issuer, audience, roles claim and role mapping to match OpenShell. A suggested audience is `openshell-cli`; suggested roles match OpenShell's defaults, `openshell-user` and a separate `openshell-admin` bootstrap identity.

Reuse a suitable existing issuer. When none exists, provision a single-instance Keycloak deployment using its documented deployment mechanism and a dedicated realm. Record its version, persistence, issuer URL, TLS trust and confidential-client configuration. Do not assume AO or OpenShift OAuth is automatically an interchangeable OpenShell OIDC issuer. Keycloak service accounts support client credentials, but role/audience claims must be configured deliberately. R10, R19.

Bootstrap operations create the workspace, provider and gateway model route with an administrative identity. The regular runner uses the least available role/workspace permissions that permit task creation, inspection, execution, file transfer and deletion. Verify actual authorization in the pinned release; do not invent unsupported fine-grained roles. Keep the administrative bootstrap credential out of the runtime Deployment.

The runner image contains the matching OpenShell CLI. Its gateway metadata, trusted CA and any required mTLS client bundle are provisioned by installation automation. Configure noninteractive client-credentials authentication using the documented CLI metadata and `OPENSHELL_OIDC_CLIENT_SECRET`; never require a browser or persist a human login. When the TLS listener requires a client certificate, provide that bundle in addition to the OIDC token. R7.

The gateway Service remains internal. No OpenShell Route, public gateway, `opencode serve`, or sandbox service-forwarding endpoint is required.

### 5.3 Supervisor identity and API-key isolation

Preserve the OpenShell supervisor's projected service-account-token/bootstrap mechanism and gateway-issued sandbox JWTs. Do not blanket-disable the mounts it needs. Verify that the agent process cannot read those credentials or the runner's OIDC secret. Runner and agent credentials must never be copied into the task workspace. R10.

Register the model API key through an administrative OpenShell provider bootstrap. The gateway's default credential store encrypts credentials in its database using a retained key-encryption Secret. Protect both that database and the Secret. Do not enable a broader Kubernetes-Secrets credential driver unnecessarily. R15, R16.

No API keys are entered in the AO prompt or returned in execution history. Use a separate, limited-budget model credential for the POC. API-key access does not imply compatibility with a consumer subscription or browser OAuth login.

## 6. Native OpenShift installation and verification

### 6.1 Preflight

Capture these before installation:

```sh
oc version -o yaml
oc get clusterversion version -o yaml
oc get storageclass
oc api-resources --api-group=agents.x-k8s.io
oc explain automationorchestrator.spec --recursive
helm show values oci://ghcr.io/nvidia/openshell/helm-chart --version 0.0.116
```

Record node architecture, kernel/runtime capabilities, CNI enforcement, existing AO namespace/network policies, and registry access. NVIDIA documents Kubernetes 1.29+ for Helm deployments; a generic “OpenShift 4.x” label alone does not prove runtime compatibility. Test the actual node kernel, filesystem/process restrictions, network-namespace setup and security-policy behavior. R11.

Use the ordinary Kubernetes runtime. Do not introduce Docker-in-Docker, nested k3s, a local Docker gateway, a VM, or an implicit Kata RuntimeClass. Use the default combined OpenShell supervisor/agent topology for the reference release; do not substitute a topology with weaker policy enforcement simply to pass admission. R6.

### 6.2 Install sequence

1. Install the pinned Agent Sandbox CRDs/controller; verify served API and controller readiness.
2. Create `openshell` and the necessary service-account bindings.
3. Grant the documented sandbox service account access to the privileged SCC, narrowly scoped to that account.
4. Configure the identity provider and TLS trust.
5. Render and install the pinned OpenShell chart; verify hooks, Secrets, PVCs and the gateway.
6. Verify gateway authentication, sandbox creation, execution, transfer and deletion without AO.
7. Only after those pass, deploy the runner and add the AO workflow.

The documented SCC binding is:

```sh
oc adm policy add-scc-to-user privileged -z openshell-sandbox -n openshell
```

Do not grant this SCC to all authenticated users, the entire namespace, the runner, or AO. Granting SCC use and a Pod's actual admitted privileges are distinct: inspect the resulting Pod, selected SCC and capabilities. The native sandbox is not a VM/kernel-isolation boundary. R4, R6.

### 6.3 Helm configuration contract

The following is a **values template**, with deployment inputs to substitute. Its field names are taken from the tagged chart, but it is not evidence of a successful installation. R15, R18.

```yaml
replicaCount: 1
workload:
  kind: statefulset

podSecurityContext:
  fsGroup: null
securityContext:
  runAsUser: null
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]

service:
  type: ClusterIP

agentSandbox:
  preflight:
    enabled: true

server:
  disableTls: false
  auth:
    allowUnauthenticatedUsers: false
  telemetryEnabled: false
  policyValidationFailureMode: fail_closed
  sandboxNamespace: openshell
  sandboxImage: REGISTRY/agentic-poc-opencode@sha256:IMAGE_DIGEST
  workspaceStorageClass: STORAGE_CLASS
  workspaceDefaultStorageSize: 2Gi
  defaultRuntimeClassName: ""
  enableUserNamespaces: false
  drivers:
    kubernetes:
      workspaceMode: shared
  oidc:
    issuer: https://ISSUER_HOST/realms/agentic-poc
    audience: openshell-cli
    rolesClaim: realm_access.roles
    adminRole: openshell-admin
    userRole: openshell-user

pkiInitJob:
  enabled: true
  serverDnsNames:
    - openshell.openshell.svc.cluster.local

certManager:
  enabled: false
openshiftRoute:
  enabled: false
grpcRoute:
  enabled: false
```

Use the chart-generated PKI for internal gateway transport and explicitly distribute trust to the runner. Keep the bootstrap hook enabled: it also creates sandbox JWT signing material. Cert-manager is optional, not required for this choice. Verify secret-volume permissions with OpenShift-assigned UIDs; do not resolve permission failures by running the gateway or runner privileged. R18.

Review the tagged chart's AppArmor setting against the OpenShift node/runtime. Where the field is inappropriate for a SELinux-based node, use the documented empty-value behavior only after validation; do not disable SELinux cluster-wide or assume every security mechanism has become active because the Pod starts. Record any patch in the deployment overlays.

Install from committed, substituted values:

```sh
helm upgrade --install openshell \
  oci://ghcr.io/nvidia/openshell/helm-chart \
  --version 0.0.116 \
  --namespace openshell \
  --values deploy/openshell/values.yaml \
  --wait --timeout 10m
```

## 7. OpenCode and model configuration

Build a dedicated, digest-pinned agent image with a pinned OpenCode version, Python and its standard-library test tools, shell utilities, the required CA trust, the model-provider SDK/cache, and a fixed task wrapper. Use a compatible OpenShell agent-image layout; pin the base image digest. Build outside task sandboxes.

Use `/sandbox` as the image's canonical working directory, with generated work under `/sandbox/work`. The image and policy must actually establish that path; it is a project choice, not an assumption about every upstream image. Keep writable OpenCode HOME/XDG state task-local. Keep the wrapper and policy/configuration inputs read-only to the agent.

Select one API-key-backed, tool-calling, streaming-capable OpenAI-compatible model endpoint for the first implementation. Configure OpenShell's protected `https://inference.local` route to that provider and model. This is a reference-release feature: re-evaluate routing APIs before upgrading beyond the pinned version. Direct arbitrary inference hosts must remain blocked. R9.

Example OpenCode configuration, rendered with the selected model ID:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "poc/SELECTED_MODEL",
  "small_model": "poc/SELECTED_MODEL",
  "enabled_providers": ["poc"],
  "share": "disabled",
  "autoupdate": false,
  "provider": {
    "poc": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "POC protected inference",
      "options": {
        "baseURL": "https://inference.local/v1",
        "apiKey": "openshell-managed-placeholder"
      },
      "models": {
        "SELECTED_MODEL": {
          "name": "POC model"
        }
      }
    }
  }
}
```

The placeholder is not the real key. OpenShell performs upstream credential handling. The custom provider example selects the Chat Completions-compatible SDK; providers requiring the Responses API or provider-specific semantics need the corresponding supported adapter and a tool-call compatibility test, not merely a changed base URL. R9, R13, R14.

Validate the selected model with an actual tool-call/result round trip and streaming response from inside the sandbox. A successful model-list request or plain text completion is insufficient. Preserve certificate validation and the sandbox's proxy CA configuration.

The wrapper launches `opencode run --format json --model ... --dir /sandbox/work` with the prompt supplied as data through an argument array/file, not shell interpolation. OpenCode's JSON mode emits events, not a ready-made final business-result object. Parse the event stream with the pinned version's schema. Never use `eval`, interpolate the prompt into `sh -c`, or expose `opencode serve`. R12.

Define an unattended permission profile: allow required workspace edits and test commands; deny interactive questions, policy/credential changes, external-directory access and unnecessary network tools. Do not leave required actions in an `ask` state. Application permissions are an additional control, not a substitute for OpenShell enforcement. Disable unused plugins, update checks, dynamic model-catalog fetches, LSP downloads and session sharing where supported by the pinned OpenCode version; preinstall everything required for the smoke task. R12, R14.

## 8. REST runner contract

These are **new application endpoints to implement**, not NVIDIA or Red Hat APIs.

| Method and path | Behavior |
|---|---|
| `POST /v1/runs` | Validate prompt, atomically reserve the one active slot, persist task, return 202 immediately. |
| `GET /v1/runs/{id}` | Return current state, phase, timestamps, terminal flag and sanitized error. |
| `GET /v1/runs/{id}/result` | Return a bounded structured result after completion; 409 while incomplete. |
| `GET /v1/runs/{id}/artifacts/{artifact_id}` | Return an authorized, size-bounded artifact by opaque ID, never arbitrary path. |
| `POST /v1/runs/{id}/cancel` | Idempotently request cancellation; return accepted/current state. |
| `GET /healthz`, `GET /readyz` | Health/readiness without secrets, prompts or artifact data. |

Example request:

```http
POST /v1/runs
Authorization: Bearer <AO-stored-runner-credential>
Idempotency-Key: <AO execution ID>
Content-Type: application/json

{
  "prompt": "Create a Python slugify function and tests, then run the tests.",
  "source_execution_id": "<AO execution ID>"
}
```

Example accepted response:

```json
{
  "run_id": "poc-01-example",
  "state": "accepted",
  "terminal": false,
  "status_path": "/v1/runs/poc-01-example"
}
```

Use a unique database constraint on the idempotency key. Same key and same request return the original run, even after completion or artifact expiry. Retention removes prompt and artifact payloads but preserves a lightweight request hash, original run ID and terminal outcome so an expired replay cannot launch another paid session. Same key with a different payload returns 409. A new key while another run is active returns 409 Busy; do not silently accumulate an unbounded queue.

Accept only the defined JSON fields. Require a nonblank prompt of at most 16,000 characters; enforce an overall 64 KiB request-body limit. Model, provider URL, image, namespace, policy, arbitrary environment variables, filesystem paths, commands and execution limits cannot be supplied by the prompt or API request.

Generate task IDs and sandbox names server-side. Bind artifacts and cancellation to the task record. Use constant-time credential comparison, request-rate limits, an authenticated API, and no sensitive request-body logging.

## 9. Runner lifecycle and fault handling

State machine:

```text
accepted -> provisioning -> preparing -> running -> collecting -> cleaning -> completed
                        \-> cleaning -> failed / timed_out / cancelled / interrupted
```

Track cleanup independently (`pending`, `complete`, `failed`), so task failure cannot hide an orphaned sandbox. Do not mark a run terminal until cleanup has resolved. Successful completion requires both successful execution and confirmed cleanup; failed or unknown cleanup produces an unsuccessful terminal result and continues to block readiness and admission.

For each accepted task:

1. Persist task ID, AO execution ID, deadline, configuration/image/policy hashes and intended sandbox name before creating resources.
2. Create a fresh, named sandbox through the OpenShell CLI with the fixed image, policy, CPU/memory limits and task labels. Wait for OpenShell Ready, not just Pod Running.
3. Upload a structured task file into the canonical workspace. Use separate create/upload/exec steps rather than rely on upload-versus-main-command startup ordering.
4. Execute a fixed wrapper noninteractively, with OpenShell's timeout and an independent runner watchdog. The wrapper reads the task file and invokes OpenCode. It does not accept a caller-supplied program.
5. Stream bounded events/logs to runner storage, recording actual process status. Generated code and tests execute only inside the sandbox.
6. Collect workspace files and a structured report through a bounded OpenShell exec stream. Validate the complete archive's paths, entry types, file count, expanded bytes and report size before extracting, reading or publishing any result.
7. Delete the sandbox in every completion path. Confirm deletion and cleanup of driver-owned Pods/PVCs; retain only exported artifacts and task metadata.

The pinned CLI documents noninteractive execution, resource flags, machine-readable inspection and file transfer. A stopped sandbox retains state; stop is not cleanup. Use deletion for normal disposal. R8.

Enforce one active run, a 180-second provisioning allowance, a 15-minute agent-runtime maximum, a 60-second collection allowance and a **20-minute total deadline**. A process-local timer alone is insufficient; store absolute deadlines and reconcile them after restarts.

On runner restart, inspect recorded tasks and gateway resources. Do not automatically rerun an uncertain paid model session. For this POC, mark it interrupted, stop/delete its sandbox and preserve any already-exported evidence. Resume is future work. An orphan reaper reconciles task labels and stored deadlines, without deleting unrelated resources.

Cancellation must reach OpenShell and terminate execution. Stopping an AO workflow is not proof that an independently running sandbox was killed. Implement an explicit Cancel Run operation and keep the external deadline authoritative. Repeated cancellation/deletion must be safe.

If cleanup fails, surface that state and retry with bounds. Stop accepting new work while the previous run has an uncontrolled live sandbox. Operator remediation uses separate administrative access; do not grant the runner cluster-admin as a convenience.

## 10. AO workflow

Create and publish `manual-opencode-poc` with these logical steps:

```text
Manual trigger
    -> Start run (REST POST)
    -> Bounded loop:
          Get status (REST GET)
          If terminal: exit loop
          Otherwise: Wait 5 seconds
    -> Get result (REST GET)
    -> Show final result / classify terminal outcome
```

Use a manual input schema with one field:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["prompt"],
  "properties": {
    "prompt": {
      "type": "string",
      "title": "Development prompt",
      "description": "Describe the code, tests, or analysis to produce in a fresh workspace.",
      "minLength": 1,
      "maxLength": 16000
    }
  }
}
```

Use AO's schema-capable Run dialog. A text-area widget is desirable but not assumed across UI versions. Serialize the request body as JSON; do not use unsafe string substitution that breaks on quotes/newlines.

Map the AO execution identifier to both the idempotency header and task metadata; Red Hat documents `${workflow_context.execution.id}` for this purpose. Configure the runner URL and stored credential centrally in the workflow, not as editable prompt fields. R1, R2.

Use ordinary REST steps, not an AO LLM integration or task-agent step. No model credential needs to be configured in AO. Use short REST timeouts, bounded retries for transient transport errors, and a maximum of 300 polling iterations. Respect the total run deadline in addition to loop counts. AO has Wait/Condition/While-loop mechanisms; use the installed version's actual node schema and expression bindings. R2, R3.

Keep endpoint paths exact: AO does not follow redirects, and REST 4xx/5xx responses fail a step unless handled. A failed task should normally still be inspectable through a successful status/result read; distinguish HTTP transport failure from a task's domain status. Map failed/timed-out/interrupted outcomes to the installed workflow's supported failure path, and make the runner result unambiguous even where workflow completion semantics differ. R2.

Create a second small manual workflow, `cancel-opencode-poc`, accepting a run ID and calling the authenticated cancel endpoint. Cancellation through this workflow is part of the baseline; automatic propagation of AO's Stop button is not assumed.

### Internal runner URL: required integration gate

AO blocks private/reserved destinations by default for workflow HTTP actions. Allow exactly the runner hostname, not private networks or wildcard suffixes. R2.

Inspect the installed AO CRD for `spec.workflowHttpRequestAllowedHosts` and use it only when the schema actually exposes it. The exact field was not verified against this target cluster. Before implementation is declared ready, record the installed operator's supported workflow-HTTP allowlist setting and prove an AO worker can call the runner.

Do **not** blindly substitute `APP_INTEGRATION_URL_ALLOWED_HOSTS`: Red Hat documents that separate setting for registered integration base URLs. The runner here is called through REST workflow steps. Where an installation additionally uses an integration object, both relevant checks may apply. Avoid permanent out-of-band Deployment patches that the operator can overwrite. R20.

Keep exported workflow definitions in the new project's `workflows/` directory. Build/export from the installed AO version rather than inventing an import format from conceptual step names. Store credential references, never secret values, in exports.

## 11. Network and privilege policy

Maintain an explicit connection matrix:

| Source | Destination | Permission |
|---|---|---|
| Human | Existing AO UI | Existing authenticated HTTPS access. |
| AO workers | Runner Service | HTTPS REST only; exact hostname/port; stored bearer credential. |
| Runner | OpenShell gateway | Gateway port 8080 over TLS; authenticated client operations. |
| Runner and gateway | OIDC issuer | Discovery/JWKS/token endpoints as required; verified HTTPS. |
| Gateway | Kubernetes API | Chart-defined RBAC only; provisioning and workload-authentication operations. |
| Gateway and sandbox supervisor | Each other | Only the control/SSH relay/callback ports used by the pinned topology. |
| Approved inference component | Model provider | Verified HTTPS to configured endpoints only. |
| Required components | Cluster DNS | Actual DNS service/port paths. |
| Agent | Kubernetes API, runner, AO, metadata, unrelated services | Denied. |

Derive relay/callback port selectors from the rendered pinned chart and actual Pods. Do not guess that the gateway's 8080 listener is the only port needed for exec, transfer or supervisor readiness. Likewise, observe the selected inference route's actual egress origin; do not place a provider allowance on only the gateway when the supervisor performs a required connection.

OpenShell policy must constrain agent traffic independently from Pod-level NetworkPolicy: the trusted supervisor and untrusted agent can share a Pod but require different privileges. Keep allowed inference access while denying agent control-plane calls. Host-level registry pulls are not the same as agent egress.

The chart's network-policy setting is not a claim of comprehensive egress isolation. Review rendered policies and enforce the complete matrix. Use the actual CNI's mechanisms for stable external egress; a normal Kubernetes NetworkPolicy is not a portable domain-name firewall. No all-private-CIDR or unrestricted Internet allowance is part of this POC. R6, R16.

Keep runner service-account token automount off unless a separately justified runtime operation needs it. Its OpenShell client, not an `oc` command, creates sandboxes. Keep generated-code execution and archive extraction out of the trusted runner. These controls limit exposure but do not make a privileged, shared-kernel evaluation equivalent to VM isolation.

## 12. Results, storage and retention

Return a bounded result such as:

```json
{
  "run_id": "poc-01-example",
  "state": "completed",
  "agent_exit_code": 0,
  "summary": "Created the requested module and tests.",
  "validation": {
    "status": "passed",
    "commands": [
      {"command": "python -m unittest discover -s tests -v", "exit_code": 0}
    ],
    "evidence": "recorded_execution"
  },
  "needs_human_review": true,
  "artifacts": [
    {"id": "workspace", "name": "workspace.tar.gz"},
    {"id": "events", "name": "events.ndjson"},
    {"id": "report", "name": "result.json"}
  ],
  "cleanup": {"state": "complete"}
}
```

Separate the agent's summary from runner-observed exit status and independently executed fixture validation. Do not infer test success from a natural-language statement, a zero-exit chat process, or a Ready sandbox. General task output remains subject to review even when tests pass.

Store `result.json`, bounded OpenCode events, diagnostic logs, workspace archive, and a file manifest with checksums. No secrets, raw bearer tokens, OIDC client credentials or hidden auth databases are permitted in artifacts. Treat all agent-generated files as untrusted: enforce canonical paths, reject escaping symlinks, reject special files, cap file count and total bytes, and serve downloads rather than automatically render active HTML.

AO displays the small final JSON in its execution view. The runner remains the artifact store. Do not assume AO attaches arbitrary external files automatically. For the first POC, provide an authenticated artifact API and an operator download command using a port-forward; no new public artifact UI or S3 service is required.

Use a 10 GiB runner PVC for SQLite and artifacts, and the pinned chart's documented gateway persistence. Allocate 2 GiB per sandbox workspace initially. A working default StorageClass or explicit class is mandatory. A Pending workspace PVC is a provisioning error, not permission to leave the workflow waiting indefinitely. R15.

Set an initial artifact cap of 100 MiB per run, 10 MiB of inline/streamed logs per category, and a seven-day retention limit, also subject to disk-capacity eviction. Do not delete gateway PVCs/credential keys as part of routine task cleanup. Verify that deleting each sandbox actually removes its driver-owned PVC; add a narrowly scoped administrative cleanup procedure only when observation proves one is needed.

## 13. Initial resource and operational limits

The following are **POC sizing proposals**, not NVIDIA or Red Hat minimum requirements. They exclude existing AO/AAP, cluster platform services and any newly provisioned identity provider.

| Component | Initial request | Initial limit |
|---|---|---|
| Runner | 250m CPU, 512 MiB memory | 1 CPU, 1 GiB |
| OpenShell gateway | 500m CPU, 1 GiB memory | 2 CPU, 2 GiB |
| One sandbox | 2 CPU, 4 GiB memory | 2 CPU, 4 GiB |

Set namespace ResourceQuota/LimitRange after inspecting helper/supervisor Pod counts. Do not use a “maximum one Pod” quota, because a sandbox is not necessarily the only helper workload created.

One configured model and one active task are enforced in the runner, not merely suggested in a prompt. Track model usage where the provider/events expose it. Configure any monetary cap at the provider or a verified inference gateway; do not claim a token/cost cap solely from a wall-clock timeout.

## 14. Acceptance tests and release gates

| Test | Required result |
|---|---|
| Dependency installation | Agent Sandbox API served, controller healthy; chart preflight succeeds. |
| OpenShift admission | Gateway/runner use intended nonprivileged SCC; only designated sandbox SA receives the documented elevated allowance. |
| Gateway identity | Correct machine identity succeeds; absent/invalid/expired credential fails protected operations. Health alone is not a pass. |
| AO internal HTTP | Published AO workflow reaches the runner with TLS verification, exact-host allowlisting and authentication. |
| Model integration | Streaming completion and tool-call/result cycle succeed through the configured route; invalid API key fails without browser login. |
| Functional smoke | Prompt creates a Python function and tests; fixed fixture validation executes in the sandbox; AO receives result and artifacts. |
| Prompt encoding | Quotes, Unicode, newlines and shell metacharacters survive as prompt data without becoming launcher commands. |
| Isolation | Each run has a different sandbox/session and no previous workspace/auth state. |
| Forbidden access | Agent cannot access runner/AO/Kubernetes API, metadata, unrelated services, host paths or real API keys. |
| Permissions | Required unattended work completes; no indefinite interactive permission question. |
| Idempotency | Repeated start with the same execution ID creates one sandbox and one paid execution. |
| Admission/busy behavior | A second distinct run is rejected while the slot is occupied. |
| Timeout and cancel | Execution ends, result records the reason, and sandbox resources are removed. |
| Restart | Runner restart never silently launches a second session; interrupted run reconciles and cleans up. |
| Artifact safety | Path traversal, symlink escape, oversize output and credential leakage checks fail safely. |
| Cleanup | No live task Pod or workspace PVC remains after completion; cleanup failure is visible and blocks unsafe subsequent work. |
| Repeatability | Three sequential successful runs leave only expected shared infrastructure and retained exported artifacts. |
| Independence | No GitHub credentials/calls, AAP jobs, VMs, or homelab-repository resources are involved. |

Example smoke prompt:

> Create a Python module containing `slugify(text)`. Convert text to lowercase, turn runs of spaces and punctuation into a single hyphen, trim leading/trailing hyphens, and return an empty string for empty input. Write standard-library unit tests, run them, and explain the implementation. Do not install dependencies.

For the controlled smoke test, provide an additional read-only fixture test suite that the agent cannot rewrite. Separately verify general generated tests and preserve their command output.

## 15. Implementation order and deliverables

**Gate A — Platform foundation:** version lock, namespaces, Agent Sandbox controller, SCC binding, storage, identity/TLS, gateway. Prove create → exec → upload/download → delete from a controlled administrative client. Do not begin by debugging AO and the sandbox platform simultaneously.

**Gate B — Agent image:** build/pin image and provider configuration; prove the model tool-call cycle and the fixture task without AO. Verify denied egress and secret isolation.

**Gate C — Runner:** implement typed API, persistent idempotency, one active slot, deadlines, cancellation, state reconciliation, artifact safety and authenticated endpoints. Test with a mock OpenShell client and a real sandbox.

**Gate D — AO:** configure credential, trust and exact-host allowlist; build/publish/export the manual workflow and cancellation workflow. Execute the full acceptance suite.

Keep the standalone project in a new repository or working directory such as:

```text
agentic-dev-poc/
  README.md
  docs/spec.md
  versions.lock.yaml
  deploy/
    namespaces/
    agent-sandbox/
    openshell/
    runner/
    identity/
    network-policies/
  images/opencode/
  runner/
  policies/
  fixtures/
  workflows/
  tests/
  scripts/bootstrap.sh
  scripts/smoke-test.sh
  scripts/cleanup.sh
```

Deliver source and tests for the runner, an API schema, image build definitions, deployment overlays, policy, workflow exports, setup/teardown instructions, a redacted acceptance report and an artifact example. `versions.lock.yaml` must contain the actual AO/OpenShift versions, Agent Sandbox release, OpenShell chart/client/image versions, OpenCode version, image digests and configuration hashes. Secret values never belong there.

## 16. Explicit unresolved deployment inputs

Implementation must obtain, record and validate: the installed AO/operator version and supported workflow-HTTP allowlist field; OpenShift and node-runtime compatibility; StorageClass; registry and pull credentials; OIDC issuer/client configuration; runner certificate trust in AO; the model provider/base URL/model ID and API key; OpenCode image/version; and the pinned Agent Sandbox release.

These are cluster/account-specific inputs, not facts established by public documentation. If admission, authentication, storage, or enforcement tests fail, stop that gate and report the failure. Do not silently replace OpenShell with an ordinary container, add virtualization, disable verification, or route work through AAP to make the demo appear successful.

## 17. Future GitHub integration

After the prompt-driven path passes, add GitHub event ingestion and repository checkout/publication as separate, authenticated components/workflow stages. Reuse the runner's task lifecycle and idempotency contract. Repository credentials, branch controls, untrusted issue authorization and PR publishing must be a new reviewed scope; they are not preprovisioned in this POC.

## References

Sources checked September 21, 2026. Vendor documentation can change independently of tagged code; pinned source governs release-specific fields. The specification's limits, endpoint names, namespace layout and lifecycle policies are design decisions, not claims of vendor defaults.

- **R1:** Red Hat, [Add a manual trigger](https://docs.redhat.com/en/documentation/automation_orchestrator/2026.8/develop-add_a_manual_trigger).
- **R2:** Red Hat, [Understand REST API steps](https://docs.redhat.com/en/documentation/automation_orchestrator/2026.8/develop-understand_rest_api_steps).
- **R3:** Red Hat, [Understand control flow steps](https://docs.redhat.com/en/documentation/automation_orchestrator/2026.8/develop-understand_control_flow_steps).
- **R4:** NVIDIA, [OpenShell on OpenShift](https://docs.nvidia.com/openshell/kubernetes/openshift).
- **R5:** NVIDIA, [Kubernetes setup](https://docs.nvidia.com/openshell/kubernetes/setup).
- **R6:** NVIDIA, [Kubernetes topology](https://docs.nvidia.com/openshell/kubernetes/topology).
- **R7:** NVIDIA, [Gateway authentication](https://docs.nvidia.com/openshell/reference/gateway-auth).
- **R8:** NVIDIA, [Manage sandboxes](https://docs.nvidia.com/openshell/sandboxes/manage-sandboxes).
- **R9:** NVIDIA, [Inference routing](https://docs.nvidia.com/openshell/sandboxes/inference-routing).
- **R10:** NVIDIA, [Kubernetes access control](https://docs.nvidia.com/openshell/kubernetes/access-control).
- **R11:** NVIDIA, [Support matrix](https://docs.nvidia.com/openshell/reference/support-matrix).
- **R12:** OpenCode, [CLI](https://opencode.ai/docs/cli/).
- **R13:** OpenCode, [Providers](https://opencode.ai/docs/providers/).
- **R14:** OpenCode, [Configuration](https://opencode.ai/docs/config/) and [Permissions](https://opencode.ai/docs/permissions/).
- **R15:** NVIDIA, [OpenShell v0.0.116 Helm values](https://github.com/NVIDIA/OpenShell/blob/v0.0.116/deploy/helm/openshell/values.yaml).
- **R16:** NVIDIA, [OpenShell v0.0.116 Helm README](https://github.com/NVIDIA/OpenShell/blob/v0.0.116/deploy/helm/openshell/README.md).
- **R17:** NVIDIA, [OpenShell v0.0.116 release](https://github.com/NVIDIA/OpenShell/releases/tag/v0.0.116).
- **R18:** NVIDIA, [Certificate management](https://docs.nvidia.com/openshell/kubernetes/managing-certificates), and tagged values under `pkiInitJob`, `certManager` and `openshiftRoute` in R15.
- **R19:** Keycloak, [Server administration: service accounts and client credentials](https://www.keycloak.org/docs/latest/server_admin/index.html).
- **R20:** Red Hat, [Allow internal service URLs for integrations](https://docs.redhat.com/en/documentation/automation_orchestrator/2026.8/configure-allow_internal_service_urls_for_integrations).
