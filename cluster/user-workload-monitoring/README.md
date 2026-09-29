# User workload monitoring

OpenShift's Cluster Monitoring Operator creates one user workload Prometheus,
one Thanos Ruler, and one dedicated Alertmanager on this single node cluster.
Each uses the default RBD StorageClass. No external alert receiver is
configured yet; add one when the alert target is chosen.

The blackbox exporter runs one replica and probes the in-cluster Forgejo demo
Service. The `Probe` and `ServiceMonitor` are scraped by user workload
Prometheus. Check the rollout and the probe result with:

```bash
oc -n openshift-user-workload-monitoring get prometheus,thanosruler,alertmanager
oc -n openshift-user-workload-monitoring get pods
oc -n blackbox-exporter get deployment,servicemonitor,probe
oc -n openshift-user-workload-monitoring exec prometheus-user-workload-0 -c prometheus -- \
  wget -qO- 'http://127.0.0.1:9090/api/v1/query?query=probe_success%7Bjob%3D%22forgejo-demo%22%7D'
```

When an alert target is available, configure a receiver for the dedicated
user workload Alertmanager. Do not add notification credentials to Git.
