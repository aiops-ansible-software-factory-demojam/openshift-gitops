# User workload monitoring

OpenShift's Cluster Monitoring Operator creates user workload Prometheus,
Thanos Ruler and a dedicated Alertmanager. Bootstrap selects their persistent
StorageClass. `enableAlertmanagerConfig: true` enables application-owned routing.

Blackbox exporter probes the internal Forgejo and webapp HTTP Services. The
`WebappDown` PrometheusRule fires when `probe_success{job="webapp"}` stays zero
for one minute. Its namespaced AlertmanagerConfig sends firing notifications
(after a ten-second group wait) to the authenticated EDA event stream. Resolved
notifications are disabled; repeats occur hourly while the alert stays firing.

Bootstrap creates or reuses `blackbox-exporter/webapp-eda-webhook` with a random
Bearer token and the gateway webhook URL. No notification credentials are in
Git. A fixed event stream UUID in the seeded Ansible inventory keeps the URL
stable. Config-as-code creates the matching EDA credential, project, supported
decision environment and `demojam-webapp-issues` activation.

The rulebook starts AAP template `webapp_alert_issue`. Its playbook opens an
issue in Forgejo `demo-owner/ansible-collection-demo.webapp`, recording the failed target
and alert details. It reuses an open issue with the outage marker; the template
serializes deliveries to prevent simultaneous duplicate creation. Close the
issue after investigating. A later outage can then open a new issue.

After publishing GitOps changes, run `make bootstrap`. For subsequent Ansible
fixture changes run `make demo-hydrate`, then `make aap-configure` to reconcile
configuration and credentials, or `make aap-sync` for configuration alone.

Inspect monitoring without printing webhook credentials:

```bash
oc -n openshift-user-workload-monitoring get prometheus,thanosruler,alertmanager
oc -n blackbox-exporter get deployment,servicemonitor,probe,prometheusrule,alertmanagerconfig
oc -n openshift-user-workload-monitoring exec prometheus-user-workload-0 -c prometheus -- \
  /bin/promtool query instant http://localhost:9090 'probe_success{job="webapp"}'
```

The probe checks nginx availability on the internal Service, independently of
the public Route's OIDC login. A missing probe series is not a `WebappDown`
condition; this rule covers HTTP probe failures.
