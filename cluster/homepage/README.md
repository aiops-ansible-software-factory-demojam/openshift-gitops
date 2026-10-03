# Demo Homepage

Homepage is the demo's starting page. Open the URL printed by bootstrap and
sign in through [demo Keycloak](../demojam-keycloak/README.md) as a member of
`demo-users` or `demo-admins`.

The page links to applications, the OpenShift console, GitOps, monitoring,
GitHub sources, and Forgejo repositories visible to the demo agent. It includes
an ordered issue-to-PR walkthrough and documentation shortcuts. Each destination
enforces its own permissions; a navigation link does not grant access.

## Refresh links and status

Bootstrap discovers actual Routes and repositories. After changing either,
run from the repository root:

```bash
make homepage-refresh
```

This regenerates navigation and verifies data sources. Homepage restarts only
if generated links change. Environment cards show the cluster, ingress domain,
tracked branch, reconciled revision, and last successful bootstrap time.
Refreshing preserves that timestamp; older installations show `Not recorded`
until their next bootstrap.

Live widgets refresh every 30 seconds. They show Argo application health,
webapp and Forgejo probes, firing alerts, CPU and memory, recent AAP jobs,
EDA activation status, and AO executions. Failed queries show an error rather
than retaining stale results.

## Configuration

GitOps owns the pinned Homepage image, dark slate settings in [config/](config/),
[dashboard sidecar](dashboard.cjs), Deployment, and RBAC. Bootstrap owns the
discovered navigation and environment ConfigMaps and the AAP/AO auditor accounts.
Static configuration changes trigger a rollout after GitOps reconciliation.

An OAuth2 Proxy sidecar handles browser login; the Route exposes only that proxy.
The dashboard sidecar serves fixed JSON summaries on pod-local port 3001 using
read-only Kubernetes access and dedicated application auditor credentials.
Those credentials stay in `homepage-dashboard-credentials`; they are not exposed
in widgets or mounted into the Homepage application container.

The page cache uses a writable volume for OpenShift's assigned user ID. Startup
regenerates the page from mounted settings without additional privileges.
