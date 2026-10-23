#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/bootstrap/bootstrap.sh"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

python3 - "$scratch" <<'PY'
import io,json,sys,zipfile
from pathlib import Path
root=Path(sys.argv[1]); child=io.BytesIO()
with zipfile.ZipFile(child,'w') as archive:
 archive.writestr('export/entitlements/aap.json',json.dumps({'pool':{'productName':'Ansible Automation Platform','providedProducts':[]},'certificates':[]}))
with zipfile.ZipFile(root/'manifest.zip','w') as archive:
 archive.writestr('consumer_export.zip',child.getvalue())
PY
export AAP_LICENSE_FILE="$scratch/manifest.zip"
mkdir "$scratch/aws" "$scratch/cnv"
DEMO_BACKEND=aws demo_manifest "$scratch/aws"
if DEMO_BACKEND=cnv demo_manifest "$scratch/cnv"; then
  echo 'CNV accepted a manifest without a RHEL entitlement.' >&2
  exit 1
fi

yq . "$root/bootstrap/aap-dispatch-credential-type.yaml" |
  jq -e '(.inputs.required | index("entitlement")) == null and
    any(.inputs.fields[]; .id == "entitlement") and
    (.injectors.file.template | contains("default("))' >/dev/null

export MODEL_PROVIDER=openshift-ai OPENSHIFT_AI_ENDPOINT=https://inference.example.test/v1
export OPENSHIFT_AI_MODEL=example-coding-model OPENSHIFT_AI_API_KEY=fixture-not-a-secret
demo_model_inputs ao
[[ $model_endpoint == "$OPENSHIFT_AI_ENDPOINT" && $model_protocol == chat && $model_provider == openshift-ai ]]
unset model_key
demo_model_inputs omnigent
[[ $model_npm == @ai-sdk/openai-compatible ]]
unset model_key

demo_ao_workflow_definition "$root/cluster/automation-orchestrator/workflows/invoice-security-remediation.yaml" fixture-credential fixture-agent |
  jq -e 'any(.nodes[]; .id == "authenticate_omnigent" and .parameters.credential_id == "fixture-credential") and
    any(.nodes[]; .id == "create_session" and .parameters.body.agent_id == "fixture-agent") and
    any(.edges[]; .from == "create_session" and (.to | startswith("share_session_")))' >/dev/null
echo 'Invoice bootstrap checks passed: AWS manifest/credential boundaries, OpenShift AI inputs, and workflow credential injection.'

# Exercise real material hydration against two application/package profiles.
# This uses synthetic unsigned fixture descriptors and a no-op Kubernetes client;
# it never reads .env, real repository credentials or AWS keys.
(
  demo_repo_root="$scratch/profile-root"
  mkdir -p "$demo_repo_root/demo/invoice"
  cp "$root/demo/invoice/baseline.json" "$demo_repo_root/demo/invoice/baseline.json"
  cp "$root/demo/invoice/profile.json" "$demo_repo_root/demo/invoice/profile.json"
  export INVOICE_LIGHTWELL_USERNAME=fixture-user INVOICE_LIGHTWELL_TOKEN=fixture-token
  export INVOICE_SIGNING_KEY_FILE="$scratch/fixture.pub"
  printf 'fixture-public-key\n' >"$INVOICE_SIGNING_KEY_FILE"
  INVOICE_SIGNING_KEY_SHA256=$(sha256sum "$INVOICE_SIGNING_KEY_FILE" | cut -d' ' -f1)
  export INVOICE_SIGNING_KEY_SHA256
  export INVOICE_LIGHTWELL_ARTIFACT_FILE="$scratch/artifact.json"
  export REMEDIATION_PROFILE_FILE='' REMEDIATION_BASELINE_FILE=''
  oc() { return 0; }
  # Discovery behavior is exercised with real Ansible in the collection tests.
  # Here check staging and publication without network or cluster writes.
  demo_invoice_discover_material() {
    [[ ${MOCK_DISCOVERY_FAIL:-false} == false ]] || return 1
    cp "$1" "$2"
  }
  for package in PyPDF2 sqlparse; do
    python3 - "$demo_repo_root" "$INVOICE_LIGHTWELL_ARTIFACT_FILE" "$package" <<'PY'
import json, sys
from pathlib import Path
root, target, package = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
profile = json.loads((root / 'demo/invoice/profile.json').read_text())
profile['package']['name'] = package
profile['advisories'] = [{'id':'TEST-ADVISORY','source':'fixture-only',
                         'affected_versions':['1.0'],'fixed_versions':['1.0+fixture']}]
(root / 'demo/invoice/profile.json').write_text(json.dumps(profile))
baseline = json.loads((root / 'demo/invoice/baseline.json').read_text())
baseline['package'] = package
(root / 'demo/invoice/baseline.json').write_text(json.dumps(baseline))
target.write_text(json.dumps({'channel':'lightwell','package':package,'version':'1.0+fixture',
    'filename':package.lower()+'-1.0+fixture-py3-none-any.whl','sha256':'a'*64,
    'url':'https://packages.redhat.com/fixture.whl','provenance_url':'https://packages.redhat.com/provenance',
    'cves':['TEST-ADVISORY']}))
PY
    demo_invoice_material
    jq -e --arg package "$package" '.profile.package.name == $package and .lightwell.package == $package' \
      "$demo_repo_root/.rendered/invoice/material.json" >/dev/null
  done
  before=$(sha256sum "$demo_repo_root/.rendered/invoice/material.json")
  export MOCK_DISCOVERY_FAIL=true
  if demo_invoice_material 2>/dev/null; then
    echo 'Material was published after failed discovery.' >&2
    exit 1
  fi
  [[ $(sha256sum "$demo_repo_root/.rendered/invoice/material.json") == "$before" ]]
)
echo 'Material staging accepts two application profiles and does not overwrite material on failed discovery.'
