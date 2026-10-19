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
