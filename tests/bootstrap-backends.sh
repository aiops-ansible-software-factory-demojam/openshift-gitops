#!/usr/bin/env bash
# Select the intended target before any destructive lifecycle command.
set -Eeuo pipefail
test_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$test_repo_root/bootstrap/bootstrap.sh"
test_scratch=$(mktemp -d)
trap 'rm -rf -- "$test_scratch"' EXIT
printf "DEMO_BACKEND='aws'\nBOOTSTRAP_REPO_URL='https://example.com/demo.git'\n" >"$test_scratch/env"
export ENV_FILE="$test_scratch/env" KUBECONFIG="$HOME/.kube/config"
oc() { printf '%s' "${recorded_backend:-}"; }
demo_preflight() { printf 'SELECTED:%s\n' "$DEMO_BACKEND"; }

for scenario in env inherited cli-before cli-after recorded conflict invalid help; do
  if (
    unset DEMO_BACKEND
    recorded_backend=
    case $scenario in
      env) demo_main preflight ;;
      inherited) export DEMO_BACKEND=cnv; demo_main preflight ;;
      cli-before) demo_main --backend cnv preflight ;;
      cli-after) demo_main preflight --backend=cnv ;;
      recorded) printf "DEMO_BACKEND=''\n" >"$test_scratch/empty"; ENV_FILE="$test_scratch/empty"; recorded_backend=aws; demo_main preflight ;;
      conflict) recorded_backend=aws; demo_main preflight --backend cnv ;;
      invalid) demo_main preflight --backend azure ;;
      help) ENV_FILE=/missing; demo_main --help ;;
    esac
  ) >"$test_scratch/output" 2>&1; then
    case $scenario in
      env|recorded) rg -q 'SELECTED:aws' "$test_scratch/output" ;;
      inherited|cli-before|cli-after) rg -q 'SELECTED:cnv' "$test_scratch/output" ;;
      help) rg -q 'Usage:' "$test_scratch/output" ;;
      *) cat "$test_scratch/output"; exit 1 ;;
    esac
  else
    [[ $scenario == conflict || $scenario == invalid ]] || { cat "$test_scratch/output"; exit 1; }
    ! rg -q 'SELECTED:' "$test_scratch/output"
  fi
  printf 'PASS %s backend selection\n' "$scenario"
done

: >"$test_scratch/waits"
oc() { printf '%s\n' "$*" >>"$test_scratch/waits"; }
DEMO_BACKEND=aws
demo_readiness sandbox
demo_readiness aap
! rg -q 'hyperconverged|kubevirt|datasource' "$test_scratch/waits"
rg -q 'tektonconfig' "$test_scratch/waits"
rg -q 'ansibleautomationplatform' "$test_scratch/waits"
printf 'PASS AWS waits only for installed platform APIs\n'

printf "AWS_BOOTSTRAP_ACCESS_KEY_ID=''\nAWS_BOOTSTRAP_SECRET_ACCESS_KEY=''\nAWS_DEMO_REGION='us-east-2'\n" >"$test_scratch/inherited"
(
  export ENV_FILE="$test_scratch/inherited" AWS_BOOTSTRAP_ACCESS_KEY_ID=example-inherited-id
  export AWS_BOOTSTRAP_SECRET_ACCESS_KEY=example-inherited-secret AWS_DEMO_REGION=us-west-2
  demo_load_env
  [[ $AWS_BOOTSTRAP_ACCESS_KEY_ID == example-inherited-id ]]
  [[ $AWS_BOOTSTRAP_SECRET_ACCESS_KEY == example-inherited-secret ]]
  [[ $AWS_DEMO_REGION == us-west-2 ]]
)
printf 'PASS inherited AWS inputs survive dotenv placeholders\n'

# AWS replaces guest endpoints; the login proxy still selects its own pod.
DEMO_BACKEND=aws
jq -n '{spec:{source:{kustomize:{patches:[]}}}}' |
  demo_backend_root_override |
  jq --arg resources "$(realpath --relative-to="$test_scratch" "$test_repo_root/cluster/webapp-vms")" '
    .spec.source.kustomize.patches[] | select(.target.name == "webapp-vms") |
    .patch | fromjson | .[0].value | .resources=[$resources] |
    .apiVersion="kustomize.config.k8s.io/v1beta1" | .kind="Kustomization"' \
    >"$test_scratch/kustomization.yaml"
command oc kustomize "$test_scratch" --load-restrictor=LoadRestrictionsNone |
  yq -j . | jq -s -e '
    [.[] | select(.kind == "Service")] as $services |
    ($services | map(select(.metadata.name == "webapp-login")) | .[0].spec.selector.app == "webapp-login") and
    ($services | map(select(.metadata.name == "webapp" or .metadata.name == "webapp-ssh")) |
      length == 2 and all(.spec | has("selector") | not))' >/dev/null
printf 'PASS AWS guest Services omit selectors while the login Service retains one\n'
