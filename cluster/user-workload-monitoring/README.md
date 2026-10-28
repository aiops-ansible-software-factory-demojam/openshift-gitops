# Webapp monitoring and outage issues

Blackbox exporter probes the internal Forgejo and nginx HTTP Services.
OpenShift user workload Prometheus, Thanos Ruler, and a dedicated Alertmanager
store monitoring data using the StorageClass selected by bootstrap.

When `probe_success{job="webapp"}` stays zero for one minute, `WebappDown`
fires. After a ten-second group wait, Alertmanager sends the alert to an
authenticated Event-Driven Ansible (EDA) event stream. The rulebook launches
AAP's `call_ao_webhook` job. AO investigates with optional native MCP diagnostics
or the AAP audit-facts fallback, then runs `webapp_alert_issue` to open/reuse one
Forgejo incident with the diagnosis. Its opening webhook starts authoring through
the second EDA listener.

## Check the probe

After [bootstrap](../../README.md), run from the repository root:

```bash
export KUBECONFIG="$HOME/.kube/config"
oc whoami --show-server
oc whoami
oc -n openshift-user-workload-monitoring get prometheus,thanosruler,alertmanager
oc -n blackbox-exporter get deployment,servicemonitor,probe,prometheusrule,alertmanagerconfig
oc -n openshift-user-workload-monitoring exec prometheus-user-workload-0 -c prometheus -- \
  /bin/promtool query instant http://localhost:9090 'probe_success{job="webapp"}'
```

The probe checks internal nginx availability independently of public Route login.
A missing series does not fire this rule; it covers HTTP probe failures.

## Configure notifications

Bootstrap generates the Bearer token and gateway webhook URL in
`blackbox-exporter/webapp-eda-webhook`. Credentials are not stored in Git.
Ansible config-as-code creates the matching EDA credential, project, supported
decision environment, and `demojam-webapp-issues` activation.

After changing Ansible fixtures, run `make demo-hydrate` then
`make aap-configure` to refresh configuration and credentials, or `make aap-sync`
for configuration alone. Publish GitOps changes before running `make bootstrap`.

The checked-in Alertmanager route uses a ten-second group wait, a 30-second group
interval, a 23-hour repeat interval and `sendResolved: true`. EDA starts RCA only
for firing alerts; resolved deliveries do not launch another author. Incident
creation is serialized and reuses open outage issues. Forgejo may close the
linked incident on merge; this is not proof of recovery. Require Enforcing,
backend HTTP 200, probe success and normal alert resolution after AAP deployment.
Public OIDC login pages cannot establish backend health.

Python CVE discovery is explicitly triggered through AO/AAP observation and
Lightwell metadata; it is not this blackbox availability alert or a fleet SBOM scan.
