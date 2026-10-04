# OpenShift Virtualization

This application installs the Red Hat OpenShift Virtualization operator from
the `stable` channel in `openshift-cnv`, then creates `HyperConverged`.
Bootstrap waits for it to become Available before proceeding with VM work.

At least one node needs `/dev/kvm`, enough free CPU and memory, and hardware
virtualization exposed by its parent hypervisor if the node is itself a VM.
The demo uses Virtualization for the RHEL webapp and Molecule test guests.

## Check a bootstrapped cluster

From the repository root:

```bash
export KUBECONFIG="$HOME/.kube/config"
oc whoami --show-server
oc whoami
oc -n openshift-gitops get application openshift-virtualization
oc -n openshift-cnv get hyperconverged kubevirt-hyperconverged
oc -n openshift-cnv get kubevirt kubevirt-kubevirt-hyperconverged
```

To test VM boot and KVM acceleration, create the temporary
[CirrOS example](examples/cirros-kvm-check.yaml). It uses an ephemeral container
disk and requires no StorageClass:

```bash
oc apply -f cluster/openshift-virtualization/examples/cirros-kvm-check.yaml
oc -n virt-nested-probe wait vm/cirros-kvm-check --for=jsonpath='{.status.ready}'=true --timeout=5m
oc -n virt-nested-probe get vm,vmi,pods
pod=$(oc -n virt-nested-probe get pod -l kubevirt.io=virt-launcher -o jsonpath='{.items[0].metadata.name}')
oc -n virt-nested-probe exec "$pod" -c compute -- sh -c '
  pid=$(pgrep -xo qemu-kvm)
  tr "\000" "\n" < "/proc/$pid/cmdline" | grep -A1 "^-accel$"
'
```

The output should show `-accel` followed by `kvm`. This VM is outside the
GitOps application; remove it after the check:

```bash
oc delete -f cluster/openshift-virtualization/examples/cirros-kvm-check.yaml
```
