# OpenShift Virtualization

The `openshift-virtualization` child Application installs the Red Hat
OpenShift Virtualization operator from the `stable` channel in
`openshift-cnv`, then creates the `HyperConverged` resource. The root
Application waits for the child to be Synced and Healthy; the custom
health check reports Healthy only when `HyperConverged` is Available.
The bootstrap script also waits for this child at the published revision.

The cluster needs a node with `/dev/kvm`. On a virtualized OpenShift node,
the parent hypervisor must expose hardware virtualization to that node.
The operator and test VM require enough free CPU and memory. The test VM
uses an ephemeral container disk, so it needs no storage class.

## Verify a bootstrapped cluster

Set `KUBECONFIG` to the demo cluster's kubeconfig, then run:

```bash
oc whoami --show-server
oc whoami
oc -n openshift-gitops get application openshift-virtualization
oc -n openshift-cnv get subscription hco-operatorhub
oc -n openshift-cnv get hyperconverged kubevirt-hyperconverged
oc -n openshift-cnv get kubevirt kubevirt-kubevirt-hyperconverged
oc apply -f cluster/openshift-virtualization/examples/cirros-kvm-check.yaml
oc -n virt-nested-probe wait vm/cirros-kvm-check --for=jsonpath='{.status.ready}'=true --timeout=5m
oc -n virt-nested-probe get vm,vmi,pods
```

To confirm hardware acceleration, inspect the VM's launcher pod. Its
QEMU process should have `-accel` followed by `kvm`:

```bash
pod=$(oc -n virt-nested-probe get pod -l kubevirt.io=virt-launcher -o jsonpath='{.items[0].metadata.name}')
oc -n virt-nested-probe exec "$pod" -c compute -- sh -c '
  pid=$(pgrep -xo qemu-kvm)
  tr "\000" "\n" < "/proc/$pid/cmdline" | grep -A1 "^-accel$"
'
```

The example VM is for a temporary check and is not included in the GitOps
Application. Remove it with:

```bash
oc delete -f cluster/openshift-virtualization/examples/cirros-kvm-check.yaml
```
