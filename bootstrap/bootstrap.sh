#!/usr/bin/env bash
set -euo pipefail

oc whoami --show-server
oc whoami

# A fresh cluster cannot accept ArgoCD/Application objects until OLM registers
# their APIs. Keep retries bounded by this Job's activeDeadlineSeconds.
until oc get crd argocds.argoproj.io applications.argoproj.io >/dev/null 2>&1; do
  sleep 5
done
oc wait --for=condition=Established crd/argocds.argoproj.io crd/applications.argoproj.io --timeout=300s

until oc apply -n openshift-gitops -f /config/openshift-gitops-argocd.yaml; do
  sleep 5
done
until oc -n openshift-gitops get argocd openshift-gitops -o jsonpath='{.status.phase}' | grep -qx Available; do
  sleep 5
done
# Health customizations must exist before the parent starts syncing children.
until oc -n openshift-gitops get configmap openshift-gitops-cm -o go-template='{{index .data "resource.customizations.health.argoproj.io_Application"}}' | grep -q 'Child sync'; do
  sleep 5
done
oc apply -n openshift-gitops -f /config/root-application.yaml
