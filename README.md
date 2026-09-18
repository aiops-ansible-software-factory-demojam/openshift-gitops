# Demo OpenShift GitOps

A disposable, single-cluster demo environment, using the OLM, Kustomize and
ArgoCD app-of-apps patterns from `igou-openshift`.

Everything lives under `cluster/<app>`. `cluster/kustomization.yaml` assembles
nine child Applications; each child renders its own directory. There are no
cluster overlays, ESO dependencies, S3 buckets, backups or lab-specific storage
classes. All PVCs use the cluster's default StorageClass.

## First deployment

Prerequisites:

- A fresh OpenShift cluster with OLM, the `redhat-operators` and
  `certified-operators` catalogs, working ingress, and a default StorageClass
  supporting dynamically provisioned RWO volumes.
- Cluster-admin access through `KUBECONFIG`, and registry access for Red Hat
  operator and application images. Activate AAP with your demo entitlement after
  installation.
- The operator channels listed below must exist in the target cluster's catalogs.
  They follow the reference repo; older OpenShift catalogs may differ.
- Enough compute for AAP, Orchestrator, Developer Hub and their databases. This
  configuration reduces replicas but does not provision or size the cluster.
- These files published on this public repository's `main` branch. ArgoCD reads
  GitHub, not your local working tree; repository credentials are not required.

Set the ingress domain before publishing. On a fresh checkout:

```bash
bash scripts/set-domain.sh apps.your-demo-cluster.example.com
```

This replaces `apps.demo.example.com` in the Orchestrator, Keycloak, Developer Hub
and Forgejo configuration. Review and publish those changes to `main`. AAP and
ArgoCD use operator-generated route hosts.

Verify you are targeting the demo cluster, then bootstrap:

```bash
oc whoami --show-server
oc whoami
oc apply -k bootstrap
oc -n openshift-gitops wait --for=condition=Complete job/gitops-bootstrap --timeout=1800s
oc -n openshift-gitops get applications
```

`bootstrap/` needs only the built-in OpenShift APIs. It installs the GitOps
operator, RBAC and a Job. The Job waits for Argo CRDs, applies the configured
ArgoCD instance, waits for its health customizations, and creates the root
Application. This avoids submitting custom resources before their CRDs exist.
The default operator-created ArgoCD instance is disabled so there is one owner
of its configuration. Bootstrap completion means GitOps is running; the apps
continue installing asynchronously.

The bootstrap service account and ArgoCD application controller have
cluster-admin permissions to install operators and cluster-scoped resources.
Bootstrap files are applied locally; they are not reconciled by the root app.
To rerun after changing bootstrap configuration or after a failed Job:

```bash
oc -n openshift-gitops delete job gitops-bootstrap
oc apply -k bootstrap
```

## Deployment order

| Parent wave | Application | Installation |
| --- | --- | --- |
| 0 | cloudnative-pg | Certified operator, `stable-v1`; readiness hook |
| 10 | ansible-automation-platform | Operator `stable-2.7`; gateway, controller and EDA |
| 10 | automation-orchestrator | Operator `stable`; standalone instance, no file storage |
| 10 | sandboxed-containers-operator | Operator `stable`; KataConfig with explicit worker opt-in |
| 10 | agent-sandbox-operator | Operator `preview-0.9` only |
| 10 | rhbk | Operator `stable-v26.6`; vanilla Keycloak |
| 10 | rhdh | Operator `fast-1.10`; vanilla Developer Hub with guest access |
| 10 | forgejo | Helm chart `17.1.6`; rootless Forgejo `15.0.8` |
| 20 | agent-sandboxes | Kata template, paused warm pool, session/client RBAC, networking and cleanup |

Child Application health propagates both sync status and health to the parent.
The CNPG PostSync hook waits for the installed CSV, its deployment rollout and
the Cluster/Database CRDs before the parent can advance to wave 10. A failed or
running hook keeps the parent gated.

Inside each app, namespaces are wave -3, OperatorGroups -2, Subscriptions -1,
Secrets/configuration 0, CNPG Clusters 1, additional databases 2, and application
instances 3. Subscription health waits for OLM installation; CNPG health waits
for `Ready` and database `applied` status. Forgejo's data PVC is wave 3 with its
Deployment to support `WaitForFirstConsumer` storage.

Automatic sync and self-heal are enabled, pruning is disabled, and failed syncs
retry with backoff. OLM InstallPlans are automatically approved, including the
Agent Sandbox preview channel. `SkipDryRunOnMissingResource` handles newly
installed APIs; it is not used as a readiness gate.

## Vanilla scope and credentials

Authored passwords and credential values are `changeme`. Required connection
metadata in Secrets (host, port, database, SSL mode, and the fixed
`eda_event_stream` role name) contains working values. Other authored usernames
are also `changeme`. Operator-generated internal keys, certificates and service
credentials are left to their operators.

- **AAP:** `admin` / `changeme`. One CNPG instance holds separate gateway,
  controller and EDA databases. The event-stream role has PostgreSQL's default
  database CONNECT privilege and owns no tables. Automation Hub is disabled,
  matching the reference repo, so the initial install does not require RWX
  content storage. No projects, inventories, credentials or job templates.
- **Orchestrator:** `admin` / `changeme`. Its own CNPG instance holds backend,
  Temporal and Temporal visibility databases. No AAP/LLM integrations or
  workflows. With no S3 configuration, file uploads are unavailable.
- **Keycloak:** bootstrap administrator `changeme` / `changeme`. Its own CNPG
  database, edge-terminated Route, no imported realms or clients. Create a
  regular administrator after first login; this is a bootstrap account.
- **Developer Hub:** guest sign-in enabled for the demo, its own CNPG instance.
  Its database role can create the per-plugin databases Backstage needs. No
  SSO, external catalogs, dynamic plugins or scaffolder integrations.
- **Forgejo:** administrator `changeme` / `changeme`, its own CNPG database and
  10Gi repository PVC. The `nonroot-v2` SCC grant is scoped to its service
  account. HTTPS is exposed; external SSH publishing is not configured.
- **Agent sandboxing:** KataConfig selects explicitly enrolled workers, excluding
  control-plane nodes. The session app provides a Python/Git Kata template,
  initially paused warm pool, ephemeral workspaces, namespace limits, scoped
  client RBAC, DNS/Forgejo-only session egress and automatic claim cleanup.
  Worker labeling and enabling the pool remain explicit steps. See
  [sandbox setup and smoke test](cluster/agent-sandboxes/README.md).

Each database is single-instance PostgreSQL 15 with a 10Gi PVC and no PDB or
backup configuration. Changing a bootstrap password later is not necessarily
an application password rotation; consult the relevant operator.

## Verification and troubleshooting

Local tools: Kustomize (with Helm support), Helm with OCI support, kubeconform,
and Bash. Run:

```bash
make test
```

This renders bootstrap, the root and all nine apps, checks shell syntax, tests
session cleanup and validates built-in Kubernetes schemas. Custom APIs without local schemas are
reported as skipped, not validated. To check the Lua health gates, also install
Lua and `yq`, then run `make test-health` (`LUA` can select another interpreter).

The initial implementation was additionally checked against CRD schemas read
from the reference cluster. That does not replace installation testing against
the demo cluster's catalog versions. No live demo deployment has been tested.

```bash
oc -n openshift-gitops logs job/gitops-bootstrap
oc -n openshift-gitops get applications \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
oc -n cloudnative-pg get subscription,csv,deployments
oc -n ansible-automation-platform get clusters.postgresql.cnpg.io,pods,routes
oc -n automation-orchestrator get clusters.postgresql.cnpg.io,pods,routes
oc -n keycloak get clusters.postgresql.cnpg.io,pods,routes
oc -n rhdh get clusters.postgresql.cnpg.io,pods,routes
oc -n forgejo get clusters.postgresql.cnpg.io,pods,routes
```

If the parent remains at wave 0, inspect CNPG's Subscription, CSV and readiness
Job. If a database remains Pending, check that namespace's PVCs and default
storage provisioning. Inspect Subscription conditions for missing catalog
channels, dependency-resolution failures or image pull errors.

Only `bootstrap/` and the root Application list use plain `oc apply -k`.
Forgejo uses Helm inflation; render individual apps with
`kustomize build --enable-helm --helm-kube-version v1.31.0 cluster/<app>`.

Configuration references:

- [AAP external databases](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-configure_an_external_database_for_ansible_automation_platform)
- [AAP EDA event-stream database](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-configure_an_external_database_for_event_streams_on_aap_operator_on_ocp)
- [Standalone Orchestrator](https://docs.redhat.com/en/documentation/automation_orchestrator/2026.8/plan-understand_the_independent_topology)
- [Keycloak operator configuration](https://www.keycloak.org/operator/advanced-configuration)
- [ArgoCD operator configuration](https://argocd-operator.readthedocs.io/en/latest/reference/argocd/)
