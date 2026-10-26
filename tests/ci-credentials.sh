#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/bootstrap/bootstrap.sh"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
demo_sandbox_image() { echo registry.fixture/demo:latest; }
aap_connect() { :; }
aap_request() { printf '{"id":999}\n'; }
aap_wait() { :; }
demo_invoice_forgejo_connect() { export FORGEJO_URL=https://forgejo.fixture FORGEJO_TOKEN=fixture-token; }
oc() {
  if [[ $* == *imagestreamtag* ]]; then
    printf 'sha256:%064d' 0
  elif [[ $* == *molecule-aws-credentials* ]]; then
    jq -n --arg profile "$(printf "export PROVISIONER=aws\nexport AWS_REGION=us-east-2\nexport AWS_SHARED_CREDENTIALS_FILE=/native/path\n" | base64 -w0)" \
      --arg credentials "$(printf '[default]\n' | base64 -w0)" \
      '{data:{"profile.sh":$profile,credentials:$credentials}}'
  elif [[ $* == *molecule-provisioner-token* ]]; then
    printf '{"data":{"ca.crt":"Q0E=","token":"VE9LRU4="}}'
  elif [[ $* == *omnigent-machine-client-credential* ]]; then
    printf '{"data":{"username":"Y2xpZW50","password":"c2VjcmV0"}}'
  elif [[ $* != *policy* ]]; then
    echo 'Unexpected CI configuration operation.' >&2
    return 1
  fi
}
aap_find() { printf '{"id":30}\n'; }
aap_upsert() {
  local id
  jq -e . <<<"$3" >/dev/null
  case $2 in
    'Demo CI Tests'|'Demo CI Publisher'|'Demo CI Author Callback') id=1 ;;
    demo-ci-tests) id=10; printf '%s' "$3" >"$scratch/$DEMO_BACKEND-tests.json" ;;
    demo-ci-publisher) id=20 ;;
    demo-ci-ee) id=40 ;;
    webapp_validate) id=100 ;;
    demo_ci_publish) id=200 ;;
    demo-ci-author) id=50 ;;
    demo_ci_iteration) id=300 ;;
    *) echo 'Unexpected CI object.' >&2; return 1 ;;
  esac
  printf '{"id":%s}\n' "$id"
}
aap_associate() { printf '%s %s\n' "$1" "$2" >>"$scratch/$DEMO_BACKEND-attachments"; }
for DEMO_BACKEND in aws cnv; do
  demo_ci_configure
  rg -q '^job_templates/100/credentials/ 10$' "$scratch/$DEMO_BACKEND-attachments"
  ! rg -q '^job_templates/100/credentials/ (20|30)$' "$scratch/$DEMO_BACKEND-attachments"
  rg -q '^job_templates/200/credentials/ 20$' "$scratch/$DEMO_BACKEND-attachments"
  rg -q '^job_templates/200/credentials/ 30$' "$scratch/$DEMO_BACKEND-attachments"
  ! rg -q '^job_templates/200/credentials/ 10$' "$scratch/$DEMO_BACKEND-attachments"
  rg -q '^job_templates/300/credentials/ 50$' "$scratch/$DEMO_BACKEND-attachments"
  rg -q '^job_templates/300/credentials/ 30$' "$scratch/$DEMO_BACKEND-attachments"
  ! rg -q '^job_templates/300/credentials/ (10|20)$' "$scratch/$DEMO_BACKEND-attachments"
done
jq -e '.inputs.profile|fromjson|.PROVISIONER=="aws" and (has("AWS_SHARED_CREDENTIALS_FILE")|not)' "$scratch/aws-tests.json" >/dev/null
jq -e '.inputs.kubeconfig|fromjson|.users[0].user.token=="TOKEN" and .contexts[0].context.namespace=="molecule-tests"' "$scratch/cnv-tests.json" >/dev/null
echo 'CI test and publisher credentials remain separate for both backends.'
