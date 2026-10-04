# Webapp monitoring and outage issues

Blackbox exporter probes the internal Forgejo and nginx HTTP Services.
OpenShift user workload Prometheus, Thanos Ruler, and a dedicated Alertmanager
store monitoring data using the StorageClass selected by bootstrap.

When `probe_success{job="webapp"}` stays zero for one minute, `WebappDown`
fires. After a ten-second group wait, Alertmanager sends the alert to an
authenticated Event-Driven Ansible (EDA) event stream. The rulebook launches
AAP's `webapp_alert_issue` job, which opens a Forgejo issue in
`demo-owner/ansible-collection-demo.webapp` with the failed target and alert details.

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

Notifications repeat hourly while firing; resolved notifications are disabled.
The job serializes deliveries and reuses an open issue with the outage marker.
Close it after investigating so a later outage can open a new issue.
