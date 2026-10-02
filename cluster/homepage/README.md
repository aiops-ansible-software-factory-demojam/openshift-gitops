# Demo Homepage

The landing page uses the homelab's pinned Homepage image and dark slate layout.
An OAuth2 Proxy sidecar authenticates users through `demojam-keycloak`; the Route
exposes only the proxy. Members of `demo-users` or `demo-admins` can sign in.

Bootstrap creates the endpoint, navigation and environment ConfigMaps, then
fills `services.yaml` from actual Routes after the stack is ready. The page has
application and identity links, an ordered issue-to-PR walkthrough, documentation
and operational shortcuts, and individual links to GitOps source repositories
and every Forgejo repository visible to the demo agent, including golden-path
output. Private template repositories remain subject to Forgejo authorization.

The Automation group brings together AAP and Automation Orchestrator links,
job templates, EDA activation links, collection issue/PR shortcuts, and
workflow/alerting guides. Automation widgets for jobs, EDA activation status,
workflows and recent executions are under Live status at the bottom of the page,
alongside cluster and monitoring widgets. The ordered demo walkthrough and the
repository index remain separate navigation sections.

Live widgets refresh every 30 seconds: Argo CD application counts and health,
blackbox webapp/Forgejo availability, webapp probe duration and firing demo
alerts, cluster/node CPU and memory, recent Controller jobs, EDA activation
status, and recent executions of `omnigent-dispatch`. Environment cards show
the cluster, ingress domain, tracked branch, reconciled revision and last
successful bootstrap time. `make homepage-refresh` preserves that completion
time; an older installation displays `Not recorded` until its next bootstrap.

A small Node.js sidecar uses the same pinned Homepage image and exposes only
fixed JSON summaries on pod-local port 3001. Homepage's Custom API widgets read
those summaries. The sidecar has a projected, rotating Kubernetes service
account token with read access to Applications, nodes, node metrics and
monitoring. It uses dedicated AAP Platform Auditor and AO auditor accounts;
bootstrap creates their random passwords once in
`homepage/homepage-dashboard-credentials`. These are service credentials,
separate from the configurable demo-user password. Neither API credentials nor
the service account token are mounted into the Homepage application container,
returned in widget responses, or exposed through a Service/Route. Kubernetes
and monitoring TLS use their injected CA bundles; application APIs use their
public HTTPS Routes. Failed queries replace old data with an error.

GitOps owns the Deployment, sidecar source, RBAC and static settings. Bootstrap
owns discovered navigation/environment data and the two application account API
calls. Static config/source hashes trigger a rollout when GitOps changes them.
Homepage's Argo CD application prunes superseded config after reconciliation.
Refreshing navigation restarts Homepage only when generated links change.

Links refresh at bootstrap time. After adding/changing Routes or repositories,
run `make homepage-refresh` to regenerate them and verify all data sources. Homepage's
native discovery supports Ingress and HTTPRoute, rather than OpenShift Routes.
Generated links do not grant access; each destination enforces its own roles.

On every container start, a lifecycle hook regenerates Homepage's prebuilt page
from the mounted settings so the title and layout apply before users arrive.
An init container copies the page cache to a writable volume for OpenShift's
assigned user ID; the application runs without additional security privileges.
