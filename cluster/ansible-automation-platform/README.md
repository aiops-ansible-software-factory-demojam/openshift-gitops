# Ansible Automation Platform

The `ansible-automation-platform-operator` Argo CD application installs the
AAP 2.7 operator. This application creates one AAP instance with platform
gateway, automation controller, and Event-Driven Ansible. Hub, Lightspeed,
MCP, and metrics service are disabled. The instance uses the cluster's RBD
StorageClass and single replicas for its gateway, controller, Redis, and EDA
services.

The operator generates the initial admin credentials in a Secret; they are
not stored in Git. Find the gateway Route and confirm the components with:

```bash
oc -n ansible-automation-platform get ansibleautomationplatform aap
oc -n ansible-automation-platform get routes
oc -n ansible-automation-platform get automationcontrollers,edas
oc -n ansible-automation-platform get deployments,statefulsets,pods
aap_host=$(oc -n ansible-automation-platform get route aap -o jsonpath='{.spec.host}')
curl -fsS "https://$aap_host/api/gateway/v1/ping/"
```

The operator is installed in sync wave 10, before the instance in wave 30.
This is a standalone AAP deployment; AO's existing issue workflow does not
depend on it.

The first install pulls several large images. If the node briefly reports
`DiskPressure`, inspect its free space and wait for kubelet to clear the
condition before retrying the rollout. The cluster's kubelet uses a five
minute pressure transition period. Do not add a disk pressure toleration to
the AAP pods.
