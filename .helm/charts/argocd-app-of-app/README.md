# Argo CD app-of-apps chart

This Helm chart generates Argo CD `AppProject` and `Application` resources.
The root application uses it to deploy the cluster's child applications.

Start with [values.yaml](values.yaml) and the
[configuration example](cluster-config-example.yaml). The demo's application
list is in [cluster/values.yaml](../../../cluster/values.yaml).

From this chart directory, render an example or package an update:

```bash
helm template demo . -f cluster-config-example.yaml
helm package .
```

Adapted from [stevesea's Argo CD Helm app-of-apps example](https://github.com/stevesea/argocd-helm-app-of-apps-example).
