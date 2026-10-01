#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$demo_repo_root"
manifest=${AAP_LICENSE_FILE:-$demo_repo_root/aap_manifest.zip}
[[ -r $manifest ]] || { echo 'Place aap_manifest.zip in the repo root.' >&2; exit 2; }
demo_verify_cluster
demo_wait_for_api
namespace=ansible-automation-platform
bash "$demo_repo_root/bootstrap/readiness.sh" aap
# Bootstrap creates these credentials directly; dispatch never owns their secrets.
python3 "$demo_repo_root/bootstrap/aap-runtime.py" credentials
# Resource Operator owns the initial inventory/project/template base fields.
# This operator ignores API dependency errors instead of retrying them.
# Wait for the real project before creating the template that references it.
oc apply -f "$demo_repo_root/bootstrap/aap-resources/demo-inventory-ansibleinventory.yaml" \
  -f "$demo_repo_root/bootstrap/aap-resources/demojam-ansible-ansibleproject.yaml"
for resource in ansibleinventory/demo-inventory ansibleproject/demojam-ansible; do
  oc -n "$namespace" wait --for=condition=Successful "$resource" --timeout=15m
done
python3 "$demo_repo_root/bootstrap/aap-runtime.py" wait-project
oc apply -f "$demo_repo_root/bootstrap/aap-resources/aap-configure-all-jobtemplate.yaml"
oc -n "$namespace" wait --for=condition=Successful jobtemplate/aap-configure-all --timeout=15m
# Attach the supported EE and runtime credential, sync the initial inventory,
# then launch dispatch through AAP and wait for its Controller job to succeed.
python3 "$demo_repo_root/bootstrap/aap-runtime.py" dispatch
echo 'AAP configuration from Forgejo completed.'
