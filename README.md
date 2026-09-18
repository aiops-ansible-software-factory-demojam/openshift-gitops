# Demo OpenShift GitOps

A disposable, single-cluster demo environment, using the OLM, Kustomize and
ArgoCD app-of-apps patterns from `igou-openshift`.

Everything lives under `cluster/<app>`. `cluster/kustomization.yaml` renders the
vendored `argocd-app-of-app` Helm chart with `cluster/values.yaml`, producing
one AppProject and nine child Applications. Each child renders its own directory.
There are no cluster overlays, ESO dependencies, S3 buckets, backups or
lab-specific storage classes. All PVCs use the cluster's default StorageClass.

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

This replaces `apps.demo.example.com` in the Orchestrator, Developer Hub and
Forgejo configuration. Review and publish those changes to `main`. AAP and
ArgoCD use operator-generated route hosts.

Verify you are targeting the demo cluster, then bootstrap:

```bash
oc whoami --show-server
oc whoami
bash bootstrap/bootstrap.sh
```

The script follows Red Hat's CLI installation flow: it applies the operator
Namespace, OperatorGroup and Subscription, then waits for OLM and the operator
deployment. The operator creates its default cluster-scoped Argo CD instance in
`openshift-gitops`; the script server-side applies the checked-in ArgoCD object
over that default, waits for the instance and all its pods to become healthy,
and applies the root Application. It then prints Application status every ten
seconds until the root app-of-apps is Synced and Healthy.

The default instance receives its cluster-scoped permissions from the Red Hat
operator. Bootstrap does not create a Job, service account, cluster role binding
or `openshift-gitops` namespace. The script is idempotent and can be rerun after
changing the checked-in ArgoCD or root Application:

```bash
bash bootstrap/bootstrap.sh
```

The three operator installation objects can still be inspected locally with
`kustomize build bootstrap`; the script applies the same files directly so it
can wait between APIs becoming available.

## Deployment order

| Parent wave | Application | Installation |
| --- | --- | --- |
| 0 | cloudnative-pg | Certified operator, `stable-v1`; readiness hook |
| 10 | ansible-automation-platform | Operator `stable-2.7`; gateway, controller and EDA |
| 10 | automation-orchestrator | Operator `stable`; standalone instance, no file storage |
| 10 | sandboxed-containers-operator | Operator `stable`; KataConfig with explicit worker opt-in |
| 10 | agent-sandbox-operator | Operator `preview-0.9` only |
| 10 | rhbk | Adopts the environment-provided operator and Keycloak instance |
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
  controller, EDA and metrics databases. The event-stream role has PostgreSQL's default
  database CONNECT privilege and owns no tables. Automation Hub is disabled,
  matching the reference repo, so the initial install does not require RWX
  content storage. No projects, inventories, credentials or job templates.
- **Orchestrator:** `admin` / `changeme`. Its own CNPG instance holds backend,
  Temporal and Temporal visibility databases. No AAP/LLM integrations or
  workflows. With no S3 configuration, file uploads are unavailable.
- **Keycloak:** GitOps adopts the environment's `keycloak-og`, `rhbk-operator`,
  Keycloak CR and `sso` Route without replacing its data plane. The environment
  must provide `keycloak-pgsql`, `keycloak-pgsql-user`, `keycloak-tls`, the
  imported `sso` realm and its OpenShift OAuth client. The PostgreSQL
  Deployment, PVC, Secrets and realm import Job are deliberately not rendered
  or pruned by this repository.
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

This renders the three operator bootstrap objects, the app-of-apps chart and all
nine apps, checks shell syntax, tests session cleanup and validates built-in
Kubernetes schemas. Custom APIs without local schemas are reported as skipped,
not validated. To check the Lua health gates, also install Lua and `yq`, then run
`make test-health` (`LUA` can select another interpreter).

The initial implementation was additionally checked against CRD schemas read
from the reference cluster. The complete bootstrap was also tested live on the
demo cluster with the catalog versions resolved there.

```bash
oc -n openshift-gitops-operator get subscription,csv,deployments
oc -n openshift-gitops get argocd,pods
oc -n openshift-gitops get applications \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
oc -n cloudnative-pg get subscription,csv,deployments
oc -n ansible-automation-platform get clusters.postgresql.cnpg.io,pods,routes
oc -n automation-orchestrator get clusters.postgresql.cnpg.io,pods,routes
oc -n keycloak get operatorgroup,subscription,keycloak,pods,routes
oc -n rhdh get clusters.postgresql.cnpg.io,pods,routes
oc -n forgejo get clusters.postgresql.cnpg.io,pods,routes
```

If the parent remains at wave 0, inspect CNPG's Subscription, CSV and readiness
Job. If a database remains Pending, check that namespace's PVCs and default
storage provisioning. Inspect Subscription conditions for missing catalog
channels, dependency-resolution failures or image pull errors.

The bootstrap script applies its checked-in objects with `oc apply`. The root
Application renders `cluster/` with the vendored app-of-apps chart. Forgejo also
uses Helm inflation; render individual apps with
`kustomize build --enable-helm --helm-kube-version v1.31.0 cluster/<app>`.

Configuration references:

- [AAP external databases](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-configure_an_external_database_for_ansible_automation_platform)
- [AAP EDA event-stream database](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/install-configure_an_external_database_for_event_streams_on_aap_operator_on_ocp)
- [Standalone Orchestrator](https://docs.redhat.com/en/documentation/automation_orchestrator/2026.8/plan-understand_the_independent_topology)
- [Keycloak operator configuration](https://www.keycloak.org/operator/advanced-configuration)
- [ArgoCD operator configuration](https://argocd-operator.readthedocs.io/en/latest/reference/argocd/)
- [Red Hat OpenShift GitOps CLI installation](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.19/html/installing_gitops/installing-openshift-gitops)
- [igou-openshift app-of-apps chart](https://github.com/igou-io/igou-openshift/tree/main/.helm/charts/argocd-app-of-app)
