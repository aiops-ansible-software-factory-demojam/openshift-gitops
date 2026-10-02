#!/usr/bin/env bash
# One implementation for installation and the demo's maintenance commands.
# Populate .env, then run this script without arguments for the full webapp.
# Sourcing this file defines functions only; it never starts a cluster operation.

demo_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=bootstrap/identity.sh
source "$demo_repo_root/bootstrap/identity.sh"
# shellcheck source=bootstrap/homepage.sh
source "$demo_repo_root/bootstrap/homepage.sh"

# -----------------------------------------------------------------------------
# Configuration, logging, and cleanup
# -----------------------------------------------------------------------------

demo_load_env() {
  local inherited_kubeconfig=${KUBECONFIG:-} inherited_branch=${BOOTSTRAP_BRANCH:-} original_dir=$PWD
  local env_file=${ENV_FILE:-$demo_repo_root/.env} had_allexport=false
  [[ $- != *a* ]] || had_allexport=true

  set +x
  [[ -r $env_file ]] || demo_die 'Copy .env.example to .env and populate it before running cluster commands.'
  # Resolve template expansions such as $PWD relative to this checkout.
  cd -- "$demo_repo_root"
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  [[ $had_allexport == true ]] || set +a
  cd -- "$original_dir"

  export KUBECONFIG=${inherited_kubeconfig:-${KUBECONFIG:-}}
  export BOOTSTRAP_BRANCH=${inherited_branch:-${BOOTSTRAP_BRANCH:-main}}
  export AAP_EE_IMAGE=${AAP_EE_IMAGE:-registry.redhat.io/ansible-automation-platform-27/ee-supported-rhel9@sha256:d97a6fc9c34132bfddf5c8f0db93a24fea67ed3db2094d15f78d7f4eba724f1f}
  export AAP_LICENSE_FILE=${AAP_LICENSE_FILE:-$demo_repo_root/aap_manifest.zip}
  [[ $AAP_LICENSE_FILE == /* ]] || AAP_LICENSE_FILE="$demo_repo_root/$AAP_LICENSE_FILE"
  export BOOTSTRAP_REPO_URL=${BOOTSTRAP_REPO_URL:-$(git -C "$demo_repo_root" remote get-url origin)}
  [[ $BOOTSTRAP_REPO_URL =~ ^https://[a-zA-Z0-9.-]+/[a-zA-Z0-9._/-]+$ ]] ||
    demo_die 'BOOTSTRAP_REPO_URL must be a public HTTPS Git repository URL without credentials.'
}

demo_die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 2
}

demo_step() {
  demo_current_step=$1
  printf '\n== %s ==\n' "$1"
}

demo_verify_cluster() {
  local server
  [[ -n ${KUBECONFIG:-} ]] || demo_die 'Export KUBECONFIG or set an explicit path/list in .env.'
  server=$(oc whoami --show-server) || return
  printf '%s\n' "$server"
  oc whoami || return
  [[ -z ${DEMO_CLUSTER_SERVER:-} || $server == "$DEMO_CLUSTER_SERVER" ]] ||
    demo_die 'The active cluster changed; restart with the intended kubeconfig.'
  export DEMO_CLUSTER_SERVER=$server
}

demo_wait_for_api() {
  local deadline=$((SECONDS + 900))
  until oc get clusteroperator kube-apiserver --request-timeout=30s -o json |
    jq -e '(.status.conditions | map({key: .type, value: .status}) | from_entries) as $c |
      $c.Available == "True" and $c.Progressing == "False" and $c.Degraded == "False"' >/dev/null; do
    (( SECONDS < deadline )) || demo_die 'Timed out waiting for a stable OpenShift API server.'
    echo 'Waiting for the OpenShift API server to finish reconciling...'
    sleep 10
  done
}

demo_sandbox_image() {
  local image
  image=$(yq -er '.data."config.yaml"' \
    "$demo_repo_root/cluster/omnigent/omnigent-sandbox-config-configmap.yaml" |
    yq -er '.sandbox.kubernetes.image') || return
  [[ $image == *:latest ]] || demo_die 'The demo sandbox image must use :latest for Always pulls.'
  printf '%s\n' "$image"
}

demo_model_inputs() {
  case ${MODEL_PROVIDER:-opencode-go} in
    opencode-go)
      model_endpoint=${OPENCODE_GO_ENDPOINT:-https://opencode.ai/zen/go/v1}
      model_name=${OPENCODE_GO_MODEL:-gpt-6-luna}
      model_key=${OPENCODE_GO_API_KEY:-}
      model_npm=@ai-sdk/openai
      ;;
    litellm)
      model_endpoint=${LITELLM_ENDPOINT:-}
      model_name=${LITELLM_MODEL:-}
      model_key=${LITELLM_API_KEY:-}
      model_npm=@ai-sdk/openai-compatible
      ;;
    *) echo 'MODEL_PROVIDER must be opencode-go or litellm.' >&2; return 2 ;;
  esac
  [[ -n $model_key && -n $model_endpoint && -n $model_name ]] || {
    echo 'Populate the selected provider key, endpoint, and model in .env.' >&2; return 2;
  }
  model_endpoint=${model_endpoint%/}
  [[ $model_endpoint == https://* && $model_endpoint != *[[:space:]?#]* &&
     $model_endpoint != */chat/completions && $model_endpoint != */responses ]] || {
    echo 'The provider endpoint must be an HTTPS API base URL.' >&2; return 2;
  }
  local host=${model_endpoint#https://}
  host=${host%%/*}
  [[ $host =~ ^[a-zA-Z0-9.-]+(:[0-9]+)?$ && $model_name =~ ^[a-zA-Z0-9._:/-]+$ ]] || {
    echo 'Invalid provider host or model name.' >&2; return 2;
  }
}

# -----------------------------------------------------------------------------
# Read-only preflight: collect failures before making the first cluster change
# -----------------------------------------------------------------------------

# Inspect both ZIP layers without extracting arbitrary archive paths. Only the
# fixed scratch filenames are written. The selected certificate/key is private.
demo_manifest() {
  local scratch=$1 entry index=0
  [[ -r $AAP_LICENSE_FILE ]] || return 2
  unzip -p "$AAP_LICENSE_FILE" consumer_export.zip >"$scratch/consumer.zip" 2>/dev/null || return 2
  unzip -Z1 "$scratch/consumer.zip" >"$scratch/entries" 2>/dev/null || return 2
  while IFS= read -r entry; do
    [[ $entry == export/entitlements/* && $entry != */ ]] || continue
    index=$((index + 1))
    unzip -p "$scratch/consumer.zip" "$entry" >"$scratch/entry.json" 2>/dev/null || return 2
    jq -e 'type == "object" and (.pool | type == "object") and
      ((.pool.providedProducts // []) | type == "array" and all(.[]; type == "object")) and
      ((.certificates // []) | type == "array" and all(.[]; type == "object"))' \
      "$scratch/entry.json" >/dev/null 2>&1 || return 2
    if [[ ! -s $scratch/entitlement.pem ]]; then
      jq -r '
        ([.pool.productName] + [.pool.providedProducts[]?.productName]) as $products |
        select(any($products[]; . == "Red Hat Enterprise Linux for x86_64" or . == "Red Hat Enterprise Linux Server")) |
        [.certificates[]? | select(
          (.cert | type == "string" and test("\\S")) and
          (.key | type == "string" and test("\\S")))] | first // empty |
        .cert + "\n" + .key' "$scratch/entry.json" >"$scratch/entitlement.pem" || return 2
    fi
  done <"$scratch/entries"
  (( index > 0 )) && [[ -s $scratch/entitlement.pem ]]
}

demo_check() {
  local name=$1 remediation=$2
  shift 2
  # A subshell prevents failing checks from leaking state into later checks.
  if ( "$@" ) >"$preflight_scratch/check.log" 2>&1; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: %s\n' "$name" "$remediation"
    preflight_failures=$((preflight_failures + 1))
  fi
}

demo_json_check() {
  local filter=$1
  shift
  oc "$@" --request-timeout=30s -o json | jq -e "$filter" >/dev/null
}

demo_preflight() (
  umask 077
  local preflight_scratch preflight_failures=0 tool missing=false
  preflight_scratch=$(mktemp -d)
  trap 'rm -rf -- "$preflight_scratch"' EXIT

  for tool in bash oc kustomize helm yq jq openssl curl git ssh-keygen unzip; do
    if ! command -v "$tool" >/dev/null; then
      printf 'FAIL tool %s: install it and put it on PATH.\n' "$tool"
      preflight_failures=$((preflight_failures + 1))
      missing=true
    fi
  done
  if [[ $missing == true ]]; then
    printf 'Preflight: %s required failure(s); install tools before further checks.\n' "$preflight_failures"
    return 2
  fi
  demo_check 'yq/jq compatibility' 'Install jq-wrapper yq; yq must emit JSON.' \
    bash -c 'printf "check: true\n" | yq . | jq -e ".check == true" >/dev/null'
  demo_check 'model inputs' 'Fill the selected provider inputs in .env.' demo_model_inputs
  demo_check 'demo users' 'Set DEMO_USERS_FILE to valid user metadata; see bootstrap/users.example.json.' \
    demo_identity_validate_users "$(demo_identity_users_file)"
  demo_check 'manifest structure and RHEL material' 'Supply the subscription ZIP with consumer_export.zip and RHEL certificate/key.' \
    demo_manifest "$preflight_scratch"
  demo_check 'KUBECONFIG' 'Export KUBECONFIG or set an explicit path/list in .env.' test -n "${KUBECONFIG:-}"

  if [[ -n ${KUBECONFIG:-} ]] && demo_verify_cluster; then
    demo_check 'cluster-admin permissions' 'Use the intended cluster-admin identity.' \
      bash -c '[[ $(oc auth can-i "*" "*" --all-namespaces --request-timeout=30s) == yes ]]'
    demo_check 'ingress domain' 'Wait for ingress to report its domain.' demo_json_check \
      '.status.domain | type == "string" and length > 0' -n openshift-ingress-operator get ingresscontroller default
    demo_check 'default storage configuration' 'Configure a default RWO StorageClass.' demo_json_check \
      'any(.items[]; .metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true" or
        .metadata.annotations["storageclass.beta.kubernetes.io/is-default-class"] == "true")' get storageclasses
    if [[ -n ${BOOTSTRAP_STORAGE_CLASS:-} ]]; then
      demo_check 'selected storage class' 'Set BOOTSTRAP_STORAGE_CLASS to an existing class.' \
        oc get storageclass "$BOOTSTRAP_STORAGE_CLASS" --request-timeout=30s -o name
    fi
    for name in redhat-operators certified-operators; do
      demo_check "catalog $name" 'Restore a READY catalog in openshift-marketplace.' demo_json_check \
        '.status.connectionState.lastObservedState == "READY"' -n openshift-marketplace get catalogsource "$name"
    done
    demo_check 'internal registry configuration' 'Enable the Managed registry with storage.' demo_json_check \
      '.spec.managementState == "Managed" and (.spec.storage | length > 0)' get config.imageregistry.operator.openshift.io cluster
    demo_check 'internal registry health' 'Restore the image-registry ClusterOperator.' demo_json_check \
      'any(.status.conditions[]; .type == "Available" and .status == "True") and
        any(.status.conditions[]; .type == "Degraded" and .status == "False")' get clusteroperator image-registry
    claim=$(oc get config.imageregistry.operator.openshift.io cluster --request-timeout=30s \
      -o jsonpath='{.spec.storage.pvc.claim}') || claim=
    if [[ -n $claim ]]; then
      demo_check 'registry storage claim' 'Restore the registry PVC.' demo_json_check \
        '.status.phase == "Bound"' -n openshift-image-registry get pvc "$claim"
    fi
    demo_check 'node readiness' 'Resolve unready nodes.' demo_json_check \
      'any(.items[]; any(.status.conditions[]; .type == "Ready" and .status == "True"))' get nodes
    # Check pressure separately to avoid confusing readiness with capacity/KVM.
    demo_check 'node pressure' 'Resolve disk, memory, or PID pressure.' demo_json_check \
      'all(.items[].status.conditions[]; if (.type == "DiskPressure" or .type == "MemoryPressure" or .type == "PIDPressure")
        then .status != "True" else true end)' get nodes
    demo_check 'workshop identity ownership' 'Orphan the old rhbk Application first; see cluster/demojam-keycloak/README.md. Preserve its resources.' \
      demo_identity_legacy_detached
  else
    printf 'FAIL cluster identity: check the kubeconfig and oc authentication.\n'
    preflight_failures=$((preflight_failures + 1))
  fi

  echo 'ADVISORY: ZIP structure does not prove license acceptance, expiry, or CDN access.'
  echo 'ADVISORY: Storage/registry/node metadata does not prove provisioning, image pulls, capacity, or KVM.'
  echo 'ADVISORY: Demo identity is provisioned after GitOps; the existing cluster login provider is independent.'
  printf 'Preflight: %s required failure(s)\n' "$preflight_failures"
  (( preflight_failures == 0 ))
)

# Installed-later APIs must not be required on a fresh cluster's preflight.
demo_readiness() {
  case $1 in
    sandbox)
      oc -n openshift-cnv wait --for=condition=Available hyperconverged/kubevirt-hyperconverged --timeout=15m
      oc -n openshift-cnv wait --for=condition=Available kubevirt/kubevirt-kubevirt-hyperconverged --timeout=15m
      oc wait --for=condition=Ready tektonconfig/config --timeout=15m
      oc wait --for=condition=Established crd/sandboxes.agents.x-k8s.io --timeout=15m
      oc -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=15m
      oc -n agent-sandbox-system rollout status deployment/sandbox-router-deployment --timeout=15m
      oc -n openshift-virtualization-os-images wait --for=condition=Ready datasource/centos-stream10 --timeout=15m
      ;;
    aap)
      oc -n ansible-automation-platform wait --for=condition=Successful ansibleautomationplatform/aap --timeout=15m
      for deployment in aap-gateway aap-controller-web aap-controller-task; do
        oc -n ansible-automation-platform rollout status "deployment/$deployment" --timeout=15m
      done
      oc -n openshift-virtualization-os-images wait --for=condition=Ready datasource/rhel9 --timeout=15m
      ;;
    *) demo_die 'Usage: readiness sandbox|aap' ;;
  esac
}

# -----------------------------------------------------------------------------
# Model and machine authentication
# -----------------------------------------------------------------------------

demo_model_config() (
  demo_model_inputs
  demo_verify_cluster
  agent_name=automation-developer
  agent_file=${agent_name}.yaml
  write_agent_spec() {
    local model=$1
    cat <<EOF
  name: $agent_name
  prompt: |
    AO runs the Backstage feature golden path before launching you. For an
    assigned issue, run demo-goldenpath checkout <number> to check out the
    existing feature/issue-<number> branch and read the issue. Read AGENTS.md.
    Make only the requested change, verify it, and review the final diff before
    committing. Write an accurate PR summary to a file outside the repository,
    then run demo-goldenpath pr <number> --body-file <path>. Report the PR URL.
    Never create the issue branch yourself or run the feature template again.
    Do not merge or push to main. Never print credentials or commit them.
  executor:
    harness: opencode
    model: "demo/$model"
EOF
  }

  umask 077
  scratch=$(mktemp -d)
  trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
  printf '%s' "$model_key" >"$scratch/api-key"
  unset model_key
  # Keep the existing Secret key for in-place upgrades; the selected endpoint is
  # the baseURL below, not the name of this environment variable.
  jq -cn --arg base "$model_endpoint" --arg model "$model_name" \
    --arg npm "$model_npm" '
    {
      "$schema": "https://opencode.ai/config.json",
      model: ("demo/" + $model),
      provider: {
        demo: {
          npm: $npm,
          name: "Demo inference",
          options: {
            baseURL: $base,
            apiKey: "{env:OPENAI_API_KEY}"
          },
          models: {
            ($model): {
              name: $model
            }
          }
        }
      }
    }
  ' | tr -d '\n' >"$scratch/opencode-config.json"

  write_agent_spec "$model_name" >"$scratch/$agent_file"

  model_status=$(oc -n omnigent-sandboxes create secret generic omnigent-model \
    --from-file=OPENAI_API_KEY="$scratch/api-key" \
    --from-file=OPENCODE_CONFIG_CONTENT="$scratch/opencode-config.json" \
    --dry-run=client -o yaml | oc -n omnigent-sandboxes apply -f -)
  agent_status=$(oc -n omnigent create secret generic omnigent-agent \
    --from-file="$agent_file=$scratch/$agent_file" \
    --dry-run=client -o yaml | oc -n omnigent apply -f -)
  printf '%s\n' "$model_status" "$agent_status"
  if [[ $agent_status != *' unchanged' ]] && oc -n omnigent get deployment omnigent >/dev/null 2>&1; then
    oc -n omnigent rollout restart deployment/omnigent
  fi
  echo "Omnigent is configured for ${MODEL_PROVIDER:-opencode-go}: $model_endpoint model $model_name."
)

demo_omnigent_auth() (
  set +x
  umask 077
  scratch=$(mktemp -d)
  trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT

  if oc -n automation-orchestrator get secret \
    omnigent-machine-client-credential >/dev/null 2>&1; then
    oc -n automation-orchestrator get secret omnigent-machine-client-credential \
      -o go-template='{{index .data "username" | base64decode}}' >"$scratch/username"
    oc -n automation-orchestrator get secret omnigent-machine-client-credential \
      -o go-template='{{index .data "password" | base64decode}}' >"$scratch/password"
  else
    printf '%s' automation-orchestrator >"$scratch/username"
    printf '%s' "$(openssl rand -hex 32)" >"$scratch/password"
    oc -n automation-orchestrator create secret generic \
      omnigent-machine-client-credential \
      --from-file=username="$scratch/username" \
      --from-file=password="$scratch/password" \
      --dry-run=client -o yaml | oc apply -f -
  fi

  if [[ $(<"$scratch/username") != automation-orchestrator ]]; then
    echo 'The Omnigent machine credential has an unexpected username.' >&2
    exit 1
  fi
  local cookie_key
  cookie_key=$(oc -n demojam-keycloak get secret identity-credentials \
    -o go-template='{{index .data "omnigent-cookie-secret" | base64decode}}')
  printf '%s' automation-orchestrator >"$scratch/OMNIGENT_MACHINE_CLIENT_ID"
  printf '%s' automation-orchestrator@example.test >"$scratch/OMNIGENT_MACHINE_SUB"
  openssl dgst -sha256 -mac HMAC -macopt "hexkey:$cookie_key" "$scratch/password" |
    awk '{print $NF}' | tr -d '\n' >"$scratch/OMNIGENT_MACHINE_CLIENT_SECRET_HASH"
  unset cookie_key
  oc -n omnigent create secret generic omnigent-machine-auth \
    --from-file=OMNIGENT_MACHINE_CLIENT_ID="$scratch/OMNIGENT_MACHINE_CLIENT_ID" \
    --from-file=OMNIGENT_MACHINE_SUB="$scratch/OMNIGENT_MACHINE_SUB" \
    --from-file=OMNIGENT_MACHINE_CLIENT_SECRET_HASH="$scratch/OMNIGENT_MACHINE_CLIENT_SECRET_HASH" \
    --dry-run=client -o yaml | oc -n omnigent apply -f -
  echo 'Omnigent native machine client-credentials authentication is configured.'
)

# -----------------------------------------------------------------------------
# Forgejo users, fixtures, and application credentials
# -----------------------------------------------------------------------------

forgejo_api() {
  local method=$1 path=$2 body=${3:-} response status
  response=$(mktemp)
  status=$(curl --silent --show-error --connect-timeout 10 --max-time 60 \
    --config <(printf 'header = "Authorization: token %s"\n' "$FORGEJO_TOKEN") \
    -H 'Content-Type: application/json' -X "$method" \
    ${body:+--data-binary @-} -o "$response" -w '%{http_code}' \
    "$FORGEJO_URL/api/v1$path" <<< "$body") || { rm -f "$response"; return 1; }
  if [[ $status != 2* ]]; then
    printf 'Forgejo API %s %s failed (HTTP %s)\n' "$method" "$path" "$status" >&2
    rm -f "$response"
    return 1
  fi
  cat "$response"
  rm -f "$response"
}

# Cache only fetched GitHub content in the ignored render directory. Bootstrap
# also reads AAP's event-stream metadata before Forgejo exists on a fresh cluster.
demo_source_checkout() (
  local name=$1 source branch work
  source=$(jq -er --arg name "$name" '.repositories[] | select(.name == $name) | .source' "$demo_repo_root/cluster/forgejo/seed.json")
  branch=$(jq -er --arg name "$name" '.repositories[] | select(.name == $name) | .source_branch // "main"' "$demo_repo_root/cluster/forgejo/seed.json")
  [[ $source =~ ^https://github.com/aiops-ansible-software-factory-demojam/[a-zA-Z0-9_.-]+\.git$ ]] ||
    demo_die 'Seed sources must be credential-free HTTPS demo GitHub repositories.'
  git check-ref-format --branch "$branch" >/dev/null
  work="$demo_repo_root/.rendered/sources/$name"
  mkdir -p "$demo_repo_root/.rendered/sources"
  if [[ ! -d $work/.git ]]; then
    GIT_ASKPASS='' git clone -q --depth 1 --single-branch --branch "$branch" "$source" "$work"
  else
    git -C "$work" remote set-url origin "$source"
    GIT_ASKPASS='' git -C "$work" fetch -q --depth 1 origin "$branch"
    git -C "$work" reset -q --hard FETCH_HEAD
  fi
  printf '%s\n' "$work"
)

demo_forgejo_seed_repos() (
  root="$demo_repo_root/cluster/forgejo"
  config=${SEED_CONFIG:-$root/seed.json}
  jq -e '.users | length > 0' "$config" >/dev/null
  users='[]'
  page=1
  while :; do
    batch=$(forgejo_api GET "/admin/users?limit=50&page=$page")
    users=$(jq -s 'add' <(printf '%s' "$users") <(printf '%s' "$batch"))
    [[ $(jq length <<< "$batch") == 50 ]] || break
    ((page+=1))
  done
  while IFS= read -r user; do
    name=$(jq -r .username <<< "$user")
    if ! jq -e --arg name "$name" 'any(.[]; .login == $name)' <<< "$users" >/dev/null; then
      body=$(jq --arg password "$name" '. + {password:$password,must_change_password:false,send_notify:false}' <<< "$user")
      forgejo_api POST /admin/users "$body" >/dev/null
    else
      body=$(jq -n --arg name "$name" '{password:$name,must_change_password:false}')
      forgejo_api PATCH "/admin/users/$name" "$body" >/dev/null
    fi
  done < <(jq -c '.users[]' "$config")
  # Git uses an askpass helper: no credentials in clone URLs or persistent remotes.
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/askpass" <<'ASKPASS'
  #!/usr/bin/env bash
  case "$1" in
    *Username*) printf '%s\n' demo-admin ;;
    *) printf '%s\n' "$FORGEJO_TOKEN" ;;
  esac
ASKPASS
  chmod 700 "$tmp/askpass"
  export GIT_ASKPASS="$tmp/askpass" GIT_TERMINAL_PROMPT=0
  while IFS= read -r repo; do
    owner=$(jq -r .owner <<< "$repo")
    name=$(jq -r .name <<< "$repo")
    [[ $owner/$name =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || exit 2
    # Enumerate using the admin's read access, including private repos.
    page=1; found=false
    while :; do
      repos=$(forgejo_api GET "/users/$owner/repos?limit=50&page=$page")
      if jq -e --arg name "$name" 'any(.[]; .name == $name)' <<< "$repos" >/dev/null; then found=true; break; fi
      [[ $(jq length <<< "$repos") == 50 ]] || break
      ((page+=1))
    done
    if [[ $found == false ]]; then
      forgejo_api POST "/admin/users/$owner/repos" "$(jq '{name,description,private:(if has("private") then .private else true end),auto_init:false,default_branch:"main"}' <<< "$repo")" >/dev/null
    fi
    forgejo_api PATCH "/repos/$owner/$name" "$(jq '{private:(if has("private") then .private else true end)}' <<< "$repo")" >/dev/null
    source=$(jq -er '.source' <<< "$repo")
    source_branch=$(jq -er '.source_branch // "main"' <<< "$repo")
    [[ $source =~ ^https://github.com/aiops-ansible-software-factory-demojam/[a-zA-Z0-9_.-]+\.git$ ]] ||
      demo_die 'Seed sources must be credential-free HTTPS demo GitHub repositories.'
    git check-ref-format --branch "$source_branch" >/dev/null
    # GitHub uses the repository-scoped ghapp credential helper. Disable the
    # Forgejo askpass helper for this fetch so credentials cannot cross hosts.
    source_work=$tmp/source-$name
    GIT_ASKPASS='' git clone -q --depth 1 --single-branch --branch "$source_branch" "$source" "$source_work"
    source_revision=$(git -C "$source_work" rev-parse HEAD)
    refs=$(git -c credential.helper= ls-remote "$FORGEJO_URL/$owner/$name.git" refs/heads/main)
    work=$tmp/$name
    if [[ -z $refs ]]; then
      git init -q -b main "$work"
    else
      git -c credential.helper= clone -q --single-branch --branch main "$FORGEJO_URL/$owner/$name.git" "$work"
      find "$work" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf -- {} +
    fi
    # Snapshot contents, not source history; preserve Forgejo branches and PRs.
    git -C "$source_work" archive HEAD | tar -x -C "$work"
    source_url=${source%.git}
    while IFS= read -r -d '' file; do
      sed -i "s|__FORGEJO_URL__|$FORGEJO_URL|g; s|$source_url|$FORGEJO_URL/$owner/$name|g" "$work/$file"
    done < <(git -C "$source_work" ls-files -z)
    git -C "$work" add -A
    if ! git -C "$work" diff --cached --quiet; then
      git -C "$work" -c user.name='Demo Maintainer' -c user.email=owner@example.test \
        commit -qm "Refresh demo baseline from $name ($source_revision)"
      git -C "$work" -c credential.helper= push -q "$FORGEJO_URL/$owner/$name.git" main
    fi
    printf 'Refreshed %s/%s from %s at %s\n' "$owner" "$name" "$source_branch" "$source_revision"
    if [[ $name == ansible-collection-template ]]; then
      forgejo_api PATCH "/repos/$owner/$name" '{"template":true}' >/dev/null
    fi
    while IFS= read -r collaborator; do
      forgejo_api PUT "/repos/$owner/$name/collaborators/$collaborator" '{"permission":"write"}' >/dev/null
    done < <(jq -r '.collaborators[]' <<< "$repo")
  done < <(jq -c '.repositories[]' "$config")
  echo 'Seed complete. Create the trigger issue after the agent integration is ready.'
)

demo_forgejo_issue() (
  root="$demo_repo_root/cluster/forgejo"
  repo=demo-owner/ansible-collection-demo.webapp
  title='Add a test line to the README'
  issues=$(forgejo_api GET "/repos/$repo/issues?state=all&limit=100")
  existing=$(jq -r --arg title "$title" \
    '.[] | select(.title == $title and .pull_request == null) | .html_url' \
    <<<"$issues" | head -1)
  if [[ -n $existing ]]; then
    printf '%s\n' "$existing"
  else
    forgejo_api POST "/repos/$repo/issues" "$(jq -n --arg title "$title" --rawfile body "$root/fixtures/readme-test-issue.md" '{title:$title,body:$body}')" | jq -r .html_url
  fi
)

demo_forgejo_lifecycle() (
  root="$demo_repo_root/cluster/forgejo"
  namespace=forgejo
  : "${FORGEJO_URL:?Set FORGEJO_URL to the public HTTPS URL of this demo instance}"
  : "${DEMO_CLUSTER_SERVER:?Run scripts/feature-demo.sh from the repository root}"
  FORGEJO_URL=${FORGEJO_URL%/}
  host=${FORGEJO_URL#https://}
  [[ $FORGEJO_URL == https://* && $host =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || {
    echo 'FORGEJO_URL must be an HTTPS URL with a DNS hostname and no path or port.' >&2; exit 2;
  }
  export FORGEJO_URL
  state=${FORGEJO_STATE_DIR:-$root/.state}
  umask 077
  mkdir -p "$state"
  cluster() {
    local server
    server=$(oc whoami --show-server)
    oc whoami
    [[ $server == "$DEMO_CLUSTER_SERVER" ]] || {
      echo 'The active cluster changed during this run; restart with the intended kubeconfig.' >&2; exit 2;
    }
  }
  route() {
    local route_host
    route_host=$(oc -n "$namespace" get route forgejo \
      -o jsonpath='{.status.ingress[0].host}')
    [[ $FORGEJO_URL == "https://$route_host" ]] || {
      echo 'FORGEJO_URL does not match the GitOps-managed Route host.' >&2; exit 2;
    }
  }
  bootstrap() {
    # Inspect usernames only; never read Kubernetes Secrets.
    local users
    users=$(oc -n "$namespace" exec deploy/forgejo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user list)
    if ! printf '%s\n' "$users" | awk '{print $2}' | grep -qx demo-admin; then
      oc -n "$namespace" exec deploy/forgejo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user create --username demo-admin --email admin@example.test --password demo-admin --admin --must-change-password=false >/dev/null
    else
      oc -n "$namespace" exec deploy/forgejo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user change-password --username demo-admin --password demo-admin --must-change-password=false >/dev/null
    fi
    if [[ -s $state/admin-token ]]; then
      token_status=$(curl -sS -o /dev/null -w '%{http_code}' \
        -H "Authorization: token $(<"$state/admin-token")" \
        "$FORGEJO_URL/api/v1/admin/users?limit=1")
      if [[ $token_status == 401 || $token_status == 403 ]]; then
        rm -f "$state/admin-token" "$state/agent-token" "$state/rhdh-token"
      fi
    fi
    if [[ ! -s $state/admin-token ]]; then
      oc -n "$namespace" exec deploy/forgejo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user generate-access-token --username demo-admin --token-name "demo-bootstrap-$(date +%s)" --scopes all --raw > "$state/admin-token.tmp"
      mv "$state/admin-token.tmp" "$state/admin-token"
    fi
  }
  wait_for_api() {
    local deadline=$((SECONDS + 300))
    until curl --fail --silent --connect-timeout 5 --max-time 10 \
      "$FORGEJO_URL/api/v1/version" >/dev/null; do
      if (( SECONDS >= deadline )); then
        echo 'Forgejo API did not become ready; inspect its Route and endpoints.' >&2
        return 1
      fi
      sleep 5
    done
  }
  seed() {
    # Pod readiness can precede the public Route accepting API requests.
    wait_for_api
    bootstrap
    FORGEJO_TOKEN=$(cat "$state/admin-token")
    export FORGEJO_TOKEN
    demo_forgejo_seed_repos
    if [[ ! -s $state/agent-token ]]; then
      oc -n "$namespace" exec deploy/forgejo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user generate-access-token --username demo-agent --token-name demo-agent --scopes write:repository,write:issue,read:user --raw > "$state/agent-token.tmp"
      mv "$state/agent-token.tmp" "$state/agent-token"
    fi
    if [[ ! -s $state/rhdh-token ]]; then
      oc -n "$namespace" exec deploy/forgejo -- forgejo --config /var/lib/gitea/custom/conf/app.ini admin user generate-access-token --username demo-agent --token-name demo-rhdh --scopes write:repository,write:user,read:issue --raw > "$state/rhdh-token.tmp"
      mv "$state/rhdh-token.tmp" "$state/rhdh-token"
    fi
  }
  case ${1:-help} in
    seed) cluster; route; seed ;;
    reset)
      [[ ${2:-} == --confirm-forgejo ]] || { echo 'Usage: demo.sh reset --confirm-forgejo (erases demo data)' >&2; exit 2; }
      cluster
      [[ $(oc get namespace "$namespace" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}') == forgejo ]] || exit 2
      route
      [[ $(oc -n openshift-gitops get applications.argoproj.io forgejo -o jsonpath='{.spec.syncPolicy.automated.selfHeal}') == true ]] || {
        echo 'forgejo must have GitOps self-heal enabled for reset.' >&2; exit 2;
      }
      old_uid=$(oc -n "$namespace" get pvc forgejo -o jsonpath='{.metadata.uid}')
      oc -n "$namespace" scale deploy/forgejo --replicas=0
      oc -n "$namespace" wait --for=delete pod -l app=forgejo --timeout=180s
      oc -n "$namespace" delete pvc forgejo --wait=true --timeout=180s
      rm -f "$state/admin-token" "$state/admin-token.tmp" \
        "$state/agent-token" "$state/agent-token.tmp" \
        "$state/rhdh-token" "$state/rhdh-token.tmp"
      new_uid=
      for ((attempt = 0; attempt < 60; attempt++)); do
        new_uid=$(oc -n "$namespace" get pvc forgejo -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
        [[ -n $new_uid && $new_uid != "$old_uid" ]] && break
        sleep 5
      done
      [[ -n $new_uid && $new_uid != "$old_uid" ]] || {
        echo 'GitOps did not recreate the demo PVC within five minutes.' >&2; exit 1;
      }
      oc -n "$namespace" scale deploy/forgejo --replicas=1
      oc -n "$namespace" rollout status deploy/forgejo --timeout=300s
      seed
      ;;
    *) echo 'Usage: demo.sh seed | reset --confirm-forgejo (via scripts/feature-demo.sh)' ;;
  esac
)

demo_hydrate() (
  repo_root="$demo_repo_root"
  action=${1:-}
  case "$action" in
    hydrate) [[ $# -eq 1 ]] ;;
    reset) [[ $# -eq 2 && $2 == --confirm-forgejo ]] ;;
    *) echo 'Usage: feature-demo.sh hydrate | reset --confirm-forgejo' >&2; exit 2 ;;
  esac

  demo_verify_cluster
  ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default \
    -o jsonpath='{.status.domain}')
  [[ -n $ingress_domain ]] || { echo 'Ingress domain is unavailable.' >&2; exit 1; }
  oc -n omnigent-sandboxes get secret omnigent-model >/dev/null
  oc -n forgejo rollout status deployment/forgejo --timeout=10m
  forgejo_host=$(oc -n forgejo get route forgejo \
    -o jsonpath='{.status.ingress[0].host}')
  [[ $forgejo_host == "forgejo.$ingress_domain" ]] || {
    echo 'Forgejo Route does not match this cluster ingress domain.' >&2
    exit 1
  }

  state_dir=${FORGEJO_STATE_DIR:-"$repo_root/cluster/forgejo/.state/$ingress_domain"}
  export FORGEJO_STATE_DIR="$state_dir"
  export FORGEJO_URL="https://$forgejo_host"
  if [[ $action == reset ]]; then
    BACKSTAGE_TOKEN=$(oc -n rhdh get secret backstage-machine-auth -o go-template='{{index .data "BACKSTAGE_TOKEN" | base64decode}}') \
      RHDH_URL="https://rhdh.$ingress_domain" FORGEJO_URL="$FORGEJO_URL" \
      bash "$repo_root/cluster/rhdh/scripts/clear-demo-catalog.sh"
    demo_forgejo_lifecycle reset --confirm-forgejo
  else
    demo_forgejo_lifecycle seed
  fi
  demo_identity_forgejo

  FORGEJO_TOKEN=$(<"$state_dir/admin-token")
  export FORGEJO_TOKEN
  issue_url=$(demo_forgejo_issue)
  unset FORGEJO_TOKEN

  umask 077
  scratch=$(mktemp -d)
  trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
  tr -d '\r\n' <"$state_dir/agent-token" >"$scratch/agent-token"
  oc -n rhdh get secret backstage-machine-auth \
    -o go-template='{{index .data "BACKSTAGE_TOKEN" | base64decode}}' >"$scratch/backstage-token"
  jq -n --rawfile token "$scratch/agent-token" \
    --rawfile backstage_token "$scratch/backstage-token" \
    --arg url 'http://forgejo.forgejo.svc.cluster.local:3000' \
    --arg backstage 'http://backstage-rhdh-developer-hub.rhdh.svc.cluster.local:80' \
    '{stringData:{FORGEJO_TOKEN:$token,FORGEJO_URL:$url,FORGEJO_USERNAME:"demo-agent",BACKSTAGE_URL:$backstage,BACKSTAGE_TOKEN:$backstage_token}}' \
    >"$scratch/forgejo-patch.json"
  oc -n omnigent-sandboxes patch secret omnigent-model --type=merge \
    --patch-file="$scratch/forgejo-patch.json" >/dev/null

  tr -d '\r\n' <"$state_dir/rhdh-token" >"$scratch/rhdh-token"
  endpoints_status=$(oc -n rhdh create configmap rhdh-demo-endpoints \
    --from-literal="FORGEJO_HOST=$forgejo_host" \
    --from-literal="FORGEJO_URL=$FORGEJO_URL" \
    --from-literal="RHDH_URL=https://rhdh.$ingress_domain" \
    --dry-run=client -o yaml | oc -n rhdh apply -f -)
  credentials_status=$(oc -n rhdh create secret generic rhdh-forgejo-credentials \
    --from-file=FORGEJO_TOKEN="$scratch/rhdh-token" \
    --from-literal=FORGEJO_USERNAME=demo-agent \
    --dry-run=client -o yaml | oc -n rhdh apply -f -)
  printf '%s\n' "$endpoints_status" "$credentials_status"
  if [[ $endpoints_status != *' unchanged' ||
        $credentials_status != *' unchanged' ]] &&
     oc -n rhdh get deployment backstage-rhdh-developer-hub >/dev/null 2>&1; then
    oc -n rhdh rollout restart deployment/backstage-rhdh-developer-hub
    oc -n rhdh rollout status deployment/backstage-rhdh-developer-hub --timeout=15m
  fi

  printf 'Forgejo demo ready: %s\n' "$issue_url"
  echo 'New automation-developer sandboxes and Backstage receive current Forgejo credentials.'
)

# -----------------------------------------------------------------------------
# Sandbox image build and Backstage catalog checks
# -----------------------------------------------------------------------------

demo_sandbox_build() (
  sandbox_image=$(demo_sandbox_image)
  demo_verify_cluster
  demo_readiness sandbox
  namespace=omnigent-sandboxes
  active_runs=$(oc -n "$namespace" get pipelineruns -l tekton.dev/pipeline=omnigent-opencode -o json |
    jq '[.items[] | select((.status.conditions[0].status // "Unknown") == "Unknown")] | length')
  [[ $active_runs == 0 ]] || { echo 'A sandbox image build is already active; inspect it before restarting.' >&2; exit 1; }
  # Release caches from terminal runs, preserving the failed logs until this next run.
  while read -r completed; do
    oc -n "$namespace" delete pod,pvc,statefulset -l "tekton.dev/pipelineRun=$completed" --ignore-not-found >/dev/null
  done < <(oc -n "$namespace" get pipelineruns -l tekton.dev/pipeline=omnigent-opencode -o json |
    jq -r '.items[] | select(.status.conditions[0].status == "True" or .status.conditions[0].status == "False") | .metadata.name')
  oc wait nodes --all --for='jsonpath={.status.conditions[?(@.type=="DiskPressure")].status}=False' --timeout=15m
  # One deliberate run; no trigger or automatic CI is installed.
  run=$(yq '.' "$demo_repo_root/bootstrap/sandbox-image-pipelinerun.yaml" |
    jq --arg revision "${SANDBOX_BUILD_REVISION:-$(git -C "$demo_repo_root" rev-parse HEAD)}" \
      --arg image "$sandbox_image" --arg repo "$BOOTSTRAP_REPO_URL" \
      '.spec.params |= map(
        if .name == "REVISION" then .value = $revision
      elif .name == "IMAGE" then .value = $image
      elif .name == "REPO_URL" then .value = $repo
        else . end)' |
    oc -n "$namespace" create -f - -o name)
  echo "Started $run"
  deadline=$((SECONDS + 3600))
  while (( SECONDS < deadline )); do
    if ! status=$(oc -n "$namespace" get "$run" --request-timeout=30s -o json); then
      echo 'Pipeline status is temporarily unavailable; retrying.' >&2
      sleep 10
      continue
    fi
    condition=$(jq -r '.status.conditions[]? | select(.type=="Succeeded") | .status' <<< "$status")
    case "$condition" in
      True)
        jq -r '.status.results[]? | "\(.name)=\(.value)"' <<< "$status"
        oc -n "$namespace" delete pod,pvc,statefulset -l "tekton.dev/pipelineRun=${run##*/}" --ignore-not-found >/dev/null
        echo "$run completed."
        exit ;;
      False)
        jq -r '.status.conditions[] | select(.type=="Succeeded") | .message' <<< "$status" >&2
        echo "Inspect task logs for $run." >&2; exit 1 ;;
    esac
    sleep 10
  done
  echo "Timed out waiting for $run; inspect it before starting another build." >&2
  exit 1
)

demo_verify_goldenpaths() (
  oc whoami --show-server
  oc whoami
  oc -n rhdh rollout status deployment/backstage-rhdh-developer-hub --timeout=15m
  rhdh_host=$(oc -n rhdh get route backstage-rhdh-developer-hub \
    -o jsonpath='{.status.ingress[0].host}')
  [[ -n $rhdh_host ]] || { echo 'RHDH Route has no host.' >&2; exit 1; }
  base_url="https://$rhdh_host"
  token=$(oc -n rhdh get secret backstage-machine-auth \
    -o go-template='{{index .data "BACKSTAGE_TOKEN" | base64decode}}')

  deadline=$((SECONDS + 600))
  while :; do
    if [[ -n $token ]] &&
       curl -fsS --max-time 20 -H "Authorization: Bearer $token" \
         "$base_url/api/scaffolder/v2/actions" 2>/dev/null |
         jq -e 'any(.[]; .id == "http:backstage:request")' >/dev/null 2>&1; then
      ready=true
      for ref in template/default/ansible-collection \
        template/default/ansible-collection-feature \
        component/default/ansible-collection-demo.webapp; do
        if ! curl -fsS --max-time 20 -o /dev/null \
          -H "Authorization: Bearer $token" \
          "$base_url/api/catalog/entities/by-name/$ref" 2>/dev/null; then
          ready=false
          break
        fi
      done
      if [[ $ready == true ]]; then
        echo 'Backstage templates, HTTP action, and example collection are ready.'
        exit 0
      fi
    fi
    if (( SECONDS >= deadline )); then
      echo 'Timed out waiting for the Backstage golden paths.' >&2
      exit 1
    fi
    sleep 5
  done
)

# -----------------------------------------------------------------------------
# Automation Orchestrator workflow reconciliation
# -----------------------------------------------------------------------------

demo_ao_workflow_definition() {
  yq -c . "$1" | jq -c --arg credential_id "$2" --arg agent_id "$3" \
    --slurpfile users "$(demo_identity_users_file)" '
    .nodes |= map(if .id == "authenticate_omnigent" then .parameters.credential_id=$credential_id
      elif .id == "create_session" then .parameters.body.agent_id=$agent_id else . end) |
    ([$users[0].users[] | select(.enabled != false)] | to_entries | map({
      id:("share_session_" + (.key | tostring)),name:("Share session with " + .value.username),type:"http_request",
      position:{x:(900 + .key * 300),y:600},parameters:{method:"PUT",
        url:"http://omnigent.omnigent.svc:8000/v1/sessions/${create_session.body.id}/permissions",
        headers:{"Content-Type":"application/json",Authorization:"Bearer ${authenticate_omnigent.body.access_token}"},
        body:{user_id:.value.email,level:1}},settings:{timeout:30,retry_policy:{max_retries:0}}
    })) as $shares |
    .nodes += $shares |
    .edges |= map(select(.from != "create_session" or .to != "send_task")) |
    (["create_session"] + ($shares | map(.id)) + ["send_task"]) as $chain |
    .edges += [range(0; ($chain | length) - 1) as $i | {from:$chain[$i],to:$chain[$i+1]}]'
}

# These helpers share the authenticated connection and private response file in
# demo_ao_reconcile. Credentials are encrypted by AO, never written to workflows.
demo_ao_credential() {
  local name=$1 type_name=$2 inputs=$3 kind id payload code
  code=$(ao_curl GET "$base_url/credential_types?limit=100" -H "$auth_header")
  ao_require_json 'list credential types' "$code"
  kind=$(jq -er --arg name "$type_name" '.resources[] | select(.name == $name) | .id' "$ao_response")
  code=$(ao_curl GET "$base_url/credentials?limit=100" -H "$auth_header")
  ao_require_json 'list integration credentials' "$code"
  id=$(jq -r --arg name "$name" '.resources[] | select(.name == $name) | .id' "$ao_response")
  payload=$(jq -n --arg name "$name" --arg project "$project_id" --arg kind "$kind" --argjson inputs "$inputs" \
    '{name:$name,project_id:$project,credential_type_id:$kind,inputs:$inputs}')
  if [[ -n $id ]]; then
    payload=$(jq 'del(.project_id,.credential_type_id)' <<<"$payload")
    code=$(ao_curl PATCH "$base_url/credentials/$id" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$payload")
  else
    code=$(ao_curl POST "$base_url/credentials" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$payload")
  fi
  ao_require_json "reconcile credential $name" "$code"
  jq -er '.id' "$ao_response"
}

demo_ao_integration() {
  local name=$1 kind=$2 credential=$3 configuration=$4 id payload code
  code=$(ao_curl GET "$base_url/integrations?limit=100" -H "$auth_header")
  ao_require_json 'list integrations' "$code"
  id=$(jq -r --arg name "$name" '.resources[] | select(.name == $name) | .id' "$ao_response")
  payload=$(jq -n --arg name "$name" --arg kind "$kind" --arg credential "$credential" \
    --argjson configuration "$configuration" \
    '{name:$name,integration_type:$kind,configuration:$configuration,
      management_credential_id:$credential,enabled:true,scope:"global"}')
  if [[ -n $id ]]; then
    payload=$(jq 'del(.integration_type)' <<<"$payload")
    code=$(ao_curl PATCH "$base_url/integrations/$id" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$payload")
  else
    code=$(ao_curl POST "$base_url/integrations" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$payload")
  fi
  ao_require_json "reconcile integration $name" "$code"
  id=$(jq -er '.id' "$ao_response")
  code=$(ao_curl POST "$base_url/integrations/$id/validate" -H "$auth_header" \
    -H 'Content-Type: application/json' --data-binary '{}')
  ao_require_json "validate integration $name" "$code"
  jq -e '.success == true' "$ao_response" >/dev/null || demo_die "AO could not connect to $name."
  printf '%s\n' "$id"
}

# AO 2026.8 uses Chat Completions and cannot set provider headers. LiteLLM's
# maintained bridge translates Responses models and adds Go's routing headers.
# Keep the runtime configuration here rather than a second bootstrap program.
demo_ao_go_proxy() {
  local proxy_model protocol config_status secret_status existing
  existing=$(oc -n "$namespace" get deployment ao-opencode-go --ignore-not-found -o name)
  protocol=${OPENCODE_GO_PROTOCOL:-responses}
  case $protocol in
    responses) proxy_model="openai/responses/$model_name" ;;
    chat) proxy_model="openai/$model_name" ;;
    *) demo_die 'OPENCODE_GO_PROTOCOL must be responses or chat.' ;;
  esac
  printf '%s' "$model_key" >"$omnigent_scratch/go-api-key"
  if [[ -n $(oc -n "$namespace" get secret ao-opencode-go --ignore-not-found -o name) ]]; then
    oc -n "$namespace" get secret ao-opencode-go \
      -o go-template='{{index .data "LITELLM_MASTER_KEY" | base64decode}}' >"$omnigent_scratch/go-proxy-key"
    [[ -s $omnigent_scratch/go-proxy-key ]] || demo_die 'The Go proxy master key is empty.'
  else
    printf 'sk-%s' "$(openssl rand -hex 32)" >"$omnigent_scratch/go-proxy-key"
  fi
  secret_status=$(oc -n "$namespace" create secret generic ao-opencode-go \
    --from-file=OPENCODE_GO_API_KEY="$omnigent_scratch/go-api-key" \
    --from-file=LITELLM_MASTER_KEY="$omnigent_scratch/go-proxy-key" --dry-run=client -o yaml |
    oc -n "$namespace" apply -f -)
  jq -n --arg model "$model_name" --arg backend "$proxy_model" --arg url "$model_endpoint" '
    {model_list:[{model_name:$model,litellm_params:{model:$backend,api_base:$url,
      api_key:"os.environ/OPENCODE_GO_API_KEY"}}],
      general_settings:{master_key:"os.environ/LITELLM_MASTER_KEY"},
      litellm_settings:{callbacks:["go_headers.callback"],num_retries:0}}' |
    yq -y . >"$omnigent_scratch/go-config.yaml"
  cat >"$omnigent_scratch/go_headers.py" <<'PY'
from uuid import uuid4
from litellm.integrations.custom_logger import CustomLogger

class GoHeaders(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        headers = data.setdefault("extra_headers", {})
        # Preserve caller conversation IDs; a single-question AO run is one call.
        metadata = data.get("metadata") or {}
        headers.setdefault("x-opencode-session", str(metadata.get("session_id") or data.get("litellm_call_id") or uuid4()))
        headers["User-Agent"] = "automation-orchestrator-demojam/1.0"
        return data

callback = GoHeaders()
PY
  config_status=$(oc -n "$namespace" create configmap ao-opencode-go \
    --from-file=config.yaml="$omnigent_scratch/go-config.yaml" \
    --from-file=go_headers.py="$omnigent_scratch/go_headers.py" --dry-run=client -o yaml |
    oc -n "$namespace" apply -f -)
  cat <<'YAML' | oc -n "$namespace" apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ao-opencode-go
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ao-opencode-go
  template:
    metadata:
      labels:
        app: ao-opencode-go
    spec:
      automountServiceAccountToken: false
      containers:
        - name: proxy
          image: ghcr.io/berriai/litellm@sha256:f63fb81b831b170ec16851e23c36ac5bf52ef106b271406429524a2ed730bbfd
          args:
            - --config
            - /etc/litellm/config.yaml
            - --port
            - "4000"
          envFrom:
            - secretRef:
                name: ao-opencode-go
          env:
            - name: PYTHONPATH
              value: /etc/litellm
            - name: XDG_CACHE_HOME
              value: /tmp/cache
          ports:
            - containerPort: 4000
          readinessProbe:
            httpGet:
              path: /health/liveliness
              port: 4000
          resources:
            requests:
              cpu: 100m
              memory: 512Mi
            limits:
              memory: 1Gi
          volumeMounts:
            - name: config
              mountPath: /etc/litellm
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: ao-opencode-go
---
apiVersion: v1
kind: Service
metadata:
  name: ao-opencode-go
spec:
  selector:
    app: ao-opencode-go
  ports:
    - port: 4000
      targetPort: 4000
YAML
  if [[ -n $existing && ( $config_status != *' unchanged' || $secret_status != *' unchanged' ) ]]; then
    oc -n "$namespace" rollout restart deployment/ao-opencode-go >/dev/null
  fi
  oc -n "$namespace" rollout status deployment/ao-opencode-go --timeout=10m
  model_endpoint=http://ao-opencode-go.automation-orchestrator.svc:4000/v1
  model_key=$(<"$omnigent_scratch/go-proxy-key")
}

demo_ao_integrations() {
  local configuration inputs allowed_hosts deploy current expected code disabled_models
  demo_model_inputs
  if [[ ${MODEL_PROVIDER:-opencode-go} == opencode-go ]]; then
    demo_ao_go_proxy
  fi
  # The integration policy is checked in backend, worker and background worker.
  # The operator loads this supported ConfigMap in all three processes. Argo
  # ignores this one bootstrap-owned key while retaining the OIDC setting.
  aap_scratch=$omnigent_scratch
  aap_connect
  allowed_hosts=$(jq -cn --arg llm "${model_endpoint#*://}" --arg aap "${aap_host#https://}" \
    '[$llm,$aap] | map(split("/")[0] | split(":")[0]) | unique')
  expected=$(jq -c . <<<"$allowed_hosts")
  oc -n "$namespace" patch configmap automation-orchestrator-admin-settings --type=merge \
    --patch "$(jq -cn --arg hosts "$expected" '{data:{APP_INTEGRATION_URL_ALLOWED_HOSTS:$hosts}}')" >/dev/null
  for deploy in backend worker background-worker; do
    current=$(oc -n "$namespace" exec "deployment/automation-orchestrator-$deploy" -- \
      printenv APP_INTEGRATION_URL_ALLOWED_HOSTS 2>/dev/null || true)
    if [[ $current != "$expected" ]]; then
      oc -n "$namespace" rollout restart "deployment/automation-orchestrator-$deploy" >/dev/null
      oc -n "$namespace" rollout status "deployment/automation-orchestrator-$deploy" --timeout=10m
      [[ $(oc -n "$namespace" exec "deployment/automation-orchestrator-$deploy" -- \
        printenv APP_INTEGRATION_URL_ALLOWED_HOSTS) == "$expected" ]] ||
        demo_die "AO $deploy did not load its integration settings."
    fi
  done
  inputs=$(jq -n --arg key "$model_key" '{api_key:$key}')
  llm_credential_id=$(demo_ao_credential "demo-llm-${MODEL_PROVIDER:-opencode-go}" 'LLM Provider' "$inputs")
  unset model_key inputs
  configuration=$(jq -n --arg url "$model_endpoint" \
    '{integration_type:"llm_provider",base_url:$url,provider_hint:"custom",allow_http:($url|startswith("http://"))}')
  llm_integration_id=$(demo_ao_integration "Demo LLM (${MODEL_PROVIDER:-opencode-go})" llm_provider "$llm_credential_id" "$configuration")
  code=$(ao_curl POST "$base_url/integrations/$llm_integration_id/refresh" -H "$auth_header" \
    -H 'Content-Type: application/json' --data-binary '{}')
  ao_require_json 'discover selected LLM models' "$code"
  code=$(ao_curl GET "$base_url/integrations/$llm_integration_id/models?limit=100" -H "$auth_header")
  ao_require_json 'list selected LLM models' "$code"
  llm_model_id=$(jq -er --arg name "$model_name" \
    '.resources[] | select(.model_id == $name) | .id' "$ao_response")
  disabled_models=$(jq -c --arg id "$llm_model_id" '[.resources[] | select(.id != $id and .enabled == true) | .id]' "$ao_response")
  if [[ $disabled_models != '[]' ]]; then
    code=$(ao_curl PATCH "$base_url/integrations/$llm_integration_id/models/bulk_update" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$(jq -n --argjson ids "$disabled_models" '{model_ids:$ids,enabled:false}')")
    ao_require_json 'disable unselected models' "$code"
  fi
  code=$(ao_curl PATCH "$base_url/integrations/$llm_integration_id/models/$llm_model_id" -H "$auth_header" \
    -H 'Content-Type: application/json' --data-binary '{"enabled":true,"is_default":true}')
  ao_require_json 'enable selected model' "$code"
  inputs=$(jq -n --arg username "$aap_username" \
    --rawfile password "$aap_scratch/password" '{username:$username,password:$password}')
  aap_credential_id=$(demo_ao_credential demo-aap 'Ansible Automation Platform' "$inputs")
  unset inputs
  configuration=$(jq -n --arg url "$aap_host" '{integration_type:"ansible_automation_platform",base_url:$url}')
  aap_integration_id=$(demo_ao_integration 'Demo AAP' ansible_automation_platform "$aap_credential_id" "$configuration")
  printf 'AO integrations are configured; selected model: %s\n' "$model_name"
}

demo_ao_run() {
  local name=$1 input=$2 workflow execution payload code status deadline=$((SECONDS + 1800))
  jq -e 'type == "object"' <<<"$input" >/dev/null || demo_die 'AO input must be a JSON object.'
  code=$(ao_curl GET "$base_url/workflows?limit=100" -H "$auth_header")
  ao_require_json 'list executable workflows' "$code"
  workflow=$(jq -er --arg name "$name" '.resources[] | select(.name == $name and .is_builtin == false) | .id' "$ao_response")
  payload=$(jq -n --arg workflow "$workflow" --argjson input "$input" \
    '{workflow_id:$workflow,trigger_node_id:"start",use_published:true,input_data:$input}')
  # A launch is a single POST. A lost response must not launch a duplicate job.
  code=$(ao_curl POST "$base_url/executions" -H "$auth_header" \
    -H 'Content-Type: application/json' --data-binary "$payload")
  ao_require_json "launch $name" "$code"
  execution=$(jq -er '.id' "$ao_response")
  printf 'AO execution: %s (%s)\n' "$execution" "$name"
  while (( SECONDS < deadline )); do
    code=$(ao_curl GET "$base_url/executions/$execution" -H "$auth_header")
    ao_require_json 'poll workflow execution' "$code"
    status=$(jq -er '.status' "$ao_response")
    case $status in
      completed)
        code=$(ao_curl GET "$base_url/executions/$execution/activities?limit=100" -H "$auth_header")
        ao_require_json 'read workflow results' "$code"
        # Do not print authentication activity outputs (including bearer tokens).
        jq '{status:"completed",results:[.resources[]? |
          select(.activity_name == "ask_model" or .activity_name == "configure_nginx" or .activity_name == "create_session") |
          {node:.activity_name,status,output:(if .activity_name == "ask_model" then
            .output_data.result.content // .output_data else .output_data end)}]}' "$ao_response"
        if [[ $name == omnigent-dispatch ]]; then
          echo 'The agent continues asynchronously. Inspect the session for its PR URL.'
        fi
        return ;;
      failed|cancelled|canceled|timed_out)
        code=$(ao_curl GET "$base_url/executions/$execution/activities?limit=100" -H "$auth_header")
        ao_require_json 'read failed activities' "$code"
        jq '{activities:[.resources[]? | {node:.activity_name,status,error:.error_message}]}' "$ao_response" >&2
        demo_die "AO workflow $name ended with $status." ;;
    esac
    sleep 5
  done
  demo_die "AO execution $execution is still $status; inspect it before another launch."
}

demo_dispatch_issue() {
  local issue=${1:-}
  [[ $# == 1 && $issue =~ ^[1-9][0-9]*$ ]] || demo_die 'Pass a positive Forgejo issue number.'
  demo_verify_cluster
  demo_ao_reconcile run omnigent-dispatch "$(jq -cn --argjson issue "$issue" '{issue_number:$issue}')"
}

demo_ao_reconcile() (
  set +x
  umask 077
  demo_identity_validate_users "$(demo_identity_users_file)" || demo_die 'Invalid DEMO_USERS_FILE.'
  namespace=automation-orchestrator
  script_dir="$demo_repo_root/cluster/automation-orchestrator"
  ao_local_port=${AO_LOCAL_PORT:-18080}

  oc whoami --show-server
  oc whoami

  ao_response=$(mktemp)
  local omnigent_scratch
  omnigent_scratch=$(mktemp -d)
  pf_log=$(mktemp)
  pf_pid=
  trap '[[ -n ${pf_pid:-} ]] && kill "$pf_pid" 2>/dev/null || true
    rm -f "$ao_response" "$pf_log"
    rm -rf -- "$omnigent_scratch"' EXIT

  ao_response_is_json() {
    jq -e . "$ao_response" >/dev/null 2>&1
  }

  ao_curl() {
    local method=$1 url=$2 http_code=000
    shift 2
    http_code=$(curl -sS --connect-timeout 10 --max-time 60 -o "$ao_response" -w '%{http_code}' \
      -X "$method" "$@" "$url" 2>/dev/null) || true
    printf '%s' "${http_code:-000}"
  }

  ao_http_ok() {
    [[ "$1" =~ ^2[0-9][0-9]$ ]]
  }

  ao_fail_response() {
    local action=$1 http_code=$2
    echo "Automation Orchestrator $action failed (HTTP $http_code)." >&2
    # API error bodies may contain credential inputs; inspect them in the UI.
    exit 1
  }

  ao_require_json() {
    local action=$1 http_code=$2
    if ! ao_http_ok "$http_code" || ! ao_response_is_json; then
      ao_fail_response "$action" "$http_code"
    fi
  }

  wait_for_ao_instance() {
    echo 'Waiting for the Automation Orchestrator instance...'
    oc -n "$namespace" wait --for=condition=Ready \
      automationorchestrator/automation-orchestrator --timeout=15m
    oc -n "$namespace" rollout status deployment/backstage-feature-gate \
      --timeout=10m
    for deploy in automation-orchestrator-ui automation-orchestrator-backend; do
      if oc -n "$namespace" get "deployment/$deploy" >/dev/null 2>&1; then
        oc -n "$namespace" rollout status "deployment/$deploy" --timeout=10m
      fi
    done
  }

  resolve_route_base_url() {
    local host
    host=$(oc -n "$namespace" get route automation-orchestrator \
      -o jsonpath='{.status.ingress[0].host}' 2>/dev/null || true)
    if [[ -z "$host" ]]; then
      host=$(oc -n "$namespace" get route -o jsonpath='{.items[0].status.ingress[0].host}' \
        2>/dev/null || true)
    fi
    if [[ -z "$host" ]]; then
      echo 'Automation Orchestrator Route has no assigned host.' >&2
      return 1
    fi
    printf 'https://%s/api/v1' "$host"
  }

  start_port_forward() {
    local svc port deadline http_code
    if ! oc -n "$namespace" get svc automation-orchestrator-ui >/dev/null 2>&1; then
      echo 'Service automation-orchestrator-ui was not found.' >&2
      oc -n "$namespace" get svc -o name >&2 || true
      return 1
    fi
    svc=automation-orchestrator-ui
    port=$(oc -n "$namespace" get svc "$svc" \
      -o jsonpath='{.spec.ports[?(@.name=="http")].port}')
    if [[ -z "$port" ]]; then
      port=$(oc -n "$namespace" get svc "$svc" -o jsonpath='{.spec.ports[0].port}')
    fi
    if [[ -z "$port" ]]; then
      echo "Service $svc has no ports." >&2
      return 1
    fi
    : >"$pf_log"
    oc -n "$namespace" port-forward "svc/$svc" "$ao_local_port:$port" \
      >"$pf_log" 2>&1 &
    pf_pid=$!
    deadline=$((SECONDS + 30))
    until http_code=$(ao_curl GET \
      "http://127.0.0.1:$ao_local_port/api/v1/auth/providers") &&
      [[ "$http_code" != 000 ]]; do
      if ! kill -0 "$pf_pid" 2>/dev/null; then
        echo 'Port-forward exited before the local port was ready.' >&2
        [[ -s "$pf_log" ]] && cat "$pf_log" >&2
        pf_pid=
        return 1
      fi
      if (( SECONDS >= deadline )); then
        kill "$pf_pid" 2>/dev/null || true
        pf_pid=
        echo 'Timed out waiting for the Automation Orchestrator port-forward.' >&2
        [[ -s "$pf_log" ]] && cat "$pf_log" >&2
        return 1
      fi
      sleep 1
    done
    printf 'http://127.0.0.1:%s/api/v1' "$ao_local_port"
  }

  resolve_base_url() {
    if [[ -n ${AO_API_BASE_URL:-} ]]; then
      printf '%s' "$AO_API_BASE_URL"
      return 0
    fi
    if [[ ${AO_USE_PORT_FORWARD:-false} == true ]]; then
      start_port_forward
      return
    fi
    resolve_route_base_url
  }

  wait_for_ao_api() {
    local base_url=$1 deadline=$((SECONDS + 600)) http_code
    echo "Waiting for the Automation Orchestrator API at $base_url ..."
    until http_code=$(ao_curl GET "$base_url/auth/providers") &&
      ao_http_ok "$http_code" && ao_response_is_json &&
      jq -e '(.providers // .resources) | type == "array"' \
        "$ao_response" >/dev/null 2>&1; do
      if [[ -n ${pf_pid:-} ]] && ! kill -0 "$pf_pid" 2>/dev/null; then
        echo 'The Automation Orchestrator port-forward exited early.' >&2
        [[ -s "$pf_log" ]] && cat "$pf_log" >&2
        exit 1
      fi
      if (( SECONDS >= deadline )); then
        echo "Last readiness response from $base_url/auth/providers:" >&2
        ao_fail_response 'readiness check' "${http_code:-000}"
      fi
      sleep 5
    done
  }

  read_admin_password() {
    local secret=$1
    oc -n "$namespace" get secret "$secret" \
      -o go-template='{{index .data "password" | base64decode}}' 2>/dev/null || true
  }

  last_login_code=000
  ao_login() {
    local base_url=$1 password=$2 http_code login_payload
    login_payload=$(jq -n --arg password "$password" \
      '{username:"admin",password:$password}')
    http_code=$(ao_curl POST "$base_url/auth/login" \
      -H 'Content-Type: application/json' --data-binary "$login_payload")
    unset login_payload
    last_login_code=$http_code
    if ao_http_ok "$http_code" && ao_response_is_json &&
       jq -e '.access_token | type == "string" and length > 0' \
         "$ao_response" >/dev/null 2>&1; then
      jq -r '.access_token' "$ao_response"
      return 0
    fi
    return 1
  }

  wait_for_ao_instance
  # envFrom does not reload a newly added ConfigMap in an existing backend pod.
  if [[ $(oc -n "$namespace" exec deployment/automation-orchestrator-backend -- \
    printenv APP_OIDC_ALLOW_PRIVATE_NETWORKS 2>/dev/null || true) != true ]]; then
    echo 'Reloading the AO backend to use the in-cluster OIDC settings...'
    oc -n "$namespace" rollout restart deployment/automation-orchestrator-backend
    oc -n "$namespace" rollout status deployment/automation-orchestrator-backend --timeout=10m
    [[ $(oc -n "$namespace" exec deployment/automation-orchestrator-backend -- \
      printenv APP_OIDC_ALLOW_PRIVATE_NETWORKS) == true ]] ||
      demo_die 'AO did not load automation-orchestrator-admin-settings.'
  fi
  if [[ -n ${AO_API_BASE_URL:-} ]]; then
    base_url=$AO_API_BASE_URL
  elif [[ ${AO_USE_PORT_FORWARD:-false} == true ]]; then
    # Start directly so the owning shell retains pf_pid for its EXIT trap.
    start_port_forward >/dev/null
    base_url="http://127.0.0.1:$ao_local_port/api/v1"
  else
    base_url=$(resolve_route_base_url)
  fi
  wait_for_ao_api "$base_url"

  ao_token=
  for secret in automation-orchestrator-admin-password \
    automation-orchestrator-initial-admin-password; do
    admin_password=$(read_admin_password "$secret")
    if [[ -z "$admin_password" ]]; then
      continue
    fi
    if ao_token=$(ao_login "$base_url" "$admin_password"); then
      unset admin_password
      break
    fi
    unset admin_password
  done
  if [[ -z ${ao_token:-} ]]; then
    echo 'Could not authenticate to the Automation Orchestrator API.' >&2
    echo 'Tried automation-orchestrator-admin-password and' >&2
    echo 'automation-orchestrator-initial-admin-password.' >&2
    ao_fail_response 'login' "$last_login_code"
  fi
  auth_header="Authorization: Bearer $ao_token"
  if [[ ${1:-} == run ]]; then
    local run_input='{}'
    [[ $# -lt 3 ]] || run_input=$3
    demo_ao_run "$2" "$run_input"
    exit 0
  fi

  http_code=$(ao_curl GET "$base_url/groups?limit=100" -H "$auth_header")
  ao_require_json 'list OIDC target groups' "$http_code"
  oidc_users_group=$(jq -er '.resources[] | select(.name == "users") | .id' "$ao_response")
  oidc_admins_group=$(jq -er '.resources[] | select(.name == "admins") | .id' "$ao_response")
  oidc_secret=$(oc -n "$namespace" get secret demo-oidc -o go-template='{{index .data "client-secret" | base64decode}}')
  oidc_issuer=$(oc -n "$namespace" get secret demo-oidc -o go-template='{{index .data "issuer" | base64decode}}')
  oidc_host=$(oc -n "$namespace" get route automation-orchestrator -o jsonpath='{.status.ingress[0].host}')
  oidc_payload=$(demo_identity_ao_payload "$oidc_issuer" "$oidc_secret" \
    "https://$oidc_host/api/v1/auth/oidc/callback" "$oidc_users_group" "$oidc_admins_group")
  http_code=$(ao_curl GET "$base_url/identity_providers?limit=100" -H "$auth_header")
  ao_require_json 'list identity providers' "$http_code"
  oidc_id=$(jq -r '.resources[] | select(.name == "Demojam Keycloak") | .id' "$ao_response")
  if [[ -n $oidc_id ]]; then
    oidc_payload=$(jq '.enabled=true' <<<"$oidc_payload")
    http_code=$(ao_curl PATCH "$base_url/identity_providers/$oidc_id" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$oidc_payload")
  else
    http_code=$(ao_curl POST "$base_url/identity_providers" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$oidc_payload")
  fi
  unset oidc_secret oidc_payload
  ao_require_json 'configure Demojam Keycloak' "$http_code"
  echo 'Automation Orchestrator OIDC and user/admin group mappings are configured.'
  [[ ${1:-workflow} != identity-only ]] || exit 0

  http_code=$(ao_curl GET "$base_url/projects" -H "$auth_header")
  ao_require_json 'list projects' "$http_code"
  project_id=$(jq -r '.resources[] | select(.name == "default") | .id' \
    "$ao_response")
  if [[ -z $project_id || $project_id == null ]]; then
    echo 'The default Automation Orchestrator project was not found.' >&2
    exit 1
  fi

  credential_name=omnigent-machine-client
  http_code=$(ao_curl GET "$base_url/credential_types?limit=100" -H "$auth_header")
  ao_require_json 'list credential types' "$http_code"
  credential_type_id=$(jq -r \
    '.resources[] | select(.name == "HTTP Basic Auth") | .id' "$ao_response")
  if [[ -z $credential_type_id || $credential_type_id == null ]]; then
    echo 'The HTTP Basic Auth credential type was not found.' >&2
    exit 1
  fi

  http_code=$(ao_curl GET "$base_url/credentials?limit=100" -H "$auth_header")
  ao_require_json 'list credentials' "$http_code"
  credential_id=$(jq -r --arg name "$credential_name" \
    '.resources[]? | select(.name == $name) | .id' "$ao_response" | head -1)

  client_id=$(oc -n "$namespace" get secret omnigent-machine-client-credential \
    -o go-template='{{index .data "username" | base64decode}}')
  client_secret=$(oc -n "$namespace" get secret omnigent-machine-client-credential \
    -o go-template='{{index .data "password" | base64decode}}')
  if [[ -z ${credential_id:-} ]]; then
    credential_payload=$(jq -n --arg name "$credential_name" \
      --arg project_id "$project_id" --arg type_id "$credential_type_id" \
      --arg username "$client_id" --arg password "$client_secret" \
      '{name:$name,project_id:$project_id,credential_type_id:$type_id,
        inputs:{username:$username,password:$password}}')
    http_code=$(ao_curl POST "$base_url/credentials" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$credential_payload")
    unset credential_payload
    ao_require_json 'create credential' "$http_code"
    credential_id=$(jq -r '.id' "$ao_response")
  else
    credential_payload=$(jq -n --arg username "$client_id" --arg password "$client_secret" \
      '{inputs:{username:$username,password:$password}}')
    http_code=$(ao_curl PATCH "$base_url/credentials/$credential_id" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$credential_payload")
    unset credential_payload
    ao_require_json 'refresh machine credential' "$http_code"
  fi

  demo_ao_integrations

  omnigent_host=$(oc -n omnigent get route omnigent \
    -o jsonpath='{.status.ingress[0].host}')
  [[ -n "$omnigent_host" ]] || { echo 'Omnigent Route has no assigned host.' >&2; exit 1; }
  omnigent_url="https://$omnigent_host"
  demo_omnigent_connect "$omnigent_scratch" "$omnigent_url"
  http_code=$(ao_curl GET "$omnigent_url/v1/agents" --config "$omnigent_scratch/omnigent.conf")
  unset client_secret
  ao_require_json 'list Omnigent agents' "$http_code"
  agent_id=$(jq -r '.data[] | select(.name == "automation-developer") | .id' "$ao_response")
  if [[ -z ${agent_id:-} || $agent_id == null ]]; then
    echo 'The Omnigent automation-developer agent was not found.' >&2
    exit 1
  fi

  # Inject runtime integration and credential references into portable definitions;
  # only omnigent-dispatch needs its dynamic agent and user-sharing nodes.
  for workflow_file in "$script_dir"/workflows/*.yaml; do
    workflow_name=$(yq -er '.name' "$workflow_file")
    if [[ $workflow_name == omnigent-dispatch ]]; then
      workflow_definition=$(demo_ao_workflow_definition "$workflow_file" "$credential_id" "$agent_id")
    else
      workflow_definition=$(yq -c . "$workflow_file" | jq -c \
        --arg llm_credential "$llm_credential_id" --arg llm_integration "$llm_integration_id" \
        --arg llm_model "$llm_model_id" --arg aap_credential "$aap_credential_id" \
        --arg aap_integration "$aap_integration_id" '
        .nodes |= map(if .type == "agentic" then
          .parameters.credential_id=$llm_credential | .parameters.integration_id=$llm_integration |
          .parameters.llm_model_id=$llm_model
        elif .type == "aap_job_template" then
          .parameters.credential_id=$aap_credential | .parameters.integration_id=$aap_integration
        else . end)')
    fi
    validation_payload=$(jq -n --argjson definition "$workflow_definition" \
      '{workflow_definition: $definition}')
    http_code=$(ao_curl POST "$base_url/workflows/validate" -H "$auth_header" \
      -H 'Content-Type: application/json' --data-binary "$validation_payload")
    if [[ $http_code == 422 ]] && ao_response_is_json; then
      # The workflow contains credential references, never credential values.
      jq -r '.validation_result.findings[]? | "\(.field_path): \(.message)"' "$ao_response" >&2
    fi
    ao_require_json 'validate workflow' "$http_code"
    jq -e '.is_valid == true' "$ao_response" >/dev/null ||
      ao_fail_response 'validate workflow' "$http_code"

    http_code=$(ao_curl GET "$base_url/workflows?limit=100" -H "$auth_header")
    ao_require_json 'list workflows' "$http_code"
    workflow_id=$(jq -r --arg name "$workflow_name" \
      '.resources[]? | select(.name == $name and .is_builtin == false) | .id' \
      "$ao_response" | head -1)
    if [[ -z ${workflow_id:-} ]]; then
      payload=$(jq -n --arg name "$workflow_name" --arg project_id "$project_id" \
        --argjson definition "$workflow_definition" \
        '{name:$name,project_id:$project_id,workflow_definition:$definition}')
      http_code=$(ao_curl POST "$base_url/workflows" -H "$auth_header" \
        -H 'Content-Type: application/json' --data-binary "$payload")
      ao_require_json 'create workflow' "$http_code"
      workflow_id=$(jq -r '.id' "$ao_response")
      workflow_version=$(jq -r '.current_version' "$ao_response")
      publish_needed=true
    else
      http_code=$(ao_curl GET "$base_url/workflows/$workflow_id" -H "$auth_header")
      ao_require_json 'read workflow' "$http_code"
      workflow_version=$(jq -r '.current_version' "$ao_response")
      published_version=$(jq -r '.published_version_number // 0' "$ao_response")
      publish_needed=false
      http_code=$(ao_curl GET \
        "$base_url/workflows/$workflow_id/versions/$workflow_version" \
        -H "$auth_header")
      ao_require_json 'read workflow version' "$http_code"
      current_definition=$(jq -c '.workflow_definition' "$ao_response")
      if [[ $(jq -S -c . <<<"$current_definition") != \
            $(jq -S -c . <<<"$workflow_definition") ]]; then
        payload=$(jq -n --argjson expected_version "$workflow_version" \
          --argjson definition "$workflow_definition" \
          '{expected_version:$expected_version,workflow_definition:$definition}')
        http_code=$(ao_curl PATCH "$base_url/workflows/$workflow_id" \
          -H "$auth_header" -H 'Content-Type: application/json' \
          --data-binary "$payload")
        ao_require_json 'update workflow' "$http_code"
        workflow_version=$(jq -r '.current_version' "$ao_response")
        publish_needed=true
      elif [[ "$published_version" != "$workflow_version" ]]; then
        publish_needed=true
      fi
    fi

    if [[ "$publish_needed" == true ]]; then
      payload=$(jq -n \
        '{publish_name:"GitOps demo",change_description:"Reconciled from openshift-gitops"}')
      http_code=$(ao_curl POST \
        "$base_url/workflows/$workflow_id/versions/$workflow_version/publish" \
        -H "$auth_header" -H 'Content-Type: application/json' \
        --data-binary "$payload")
      ao_require_json 'publish workflow' "$http_code"
    fi
    printf 'Reconciled workflow %s version %s\n' "$workflow_name" "$workflow_version"
  done
)

# -----------------------------------------------------------------------------
# AAP API: minimal foundation; config-as-code owns runtime credentials and demo jobs
# -----------------------------------------------------------------------------

# API response files and curl authentication are private and removed together.
# Only safe GETs retry. A lost write response may mean the operation succeeded;
# in particular, retrying a launch could create a second job.
aap_connect() {
  aap_host=${AAP_HOST:-https://$(oc -n ansible-automation-platform get route aap -o jsonpath='{.status.ingress[0].host}')}
  aap_host=${aap_host%/}
  aap_username=${AAP_USERNAME:-admin}
  printf '%s' "${AAP_PASSWORD:-$(oc -n ansible-automation-platform get secret aap-admin-password \
    -o go-template='{{index .data "password" | base64decode}}')}" >"$aap_scratch/password"
  {
    printf '%s:' "$aap_username"
    cat "$aap_scratch/password"
  } | base64 | tr -d '\n' >"$aap_scratch/basic"
  printf 'header = "Authorization: Basic %s"\n' "$(<"$aap_scratch/basic")" >"$aap_scratch/curl.conf"
}

aap_request() {
  local method=$1 path=$2 body=${3:-} prefix=${4:-/api/controller/v2/}
  local response payload code attempt max_attempts=1
  response=$(mktemp "$aap_scratch/response.XXXXXX")
  payload=$(mktemp "$aap_scratch/payload.XXXXXX")
  printf '%s' "$body" >"$payload"
  local -a data_args=()
  [[ -z $body ]] || data_args=(--data-binary "@$payload")
  [[ $method != GET ]] || max_attempts=3

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    code=$(curl --silent --show-error --connect-timeout 10 --max-time 60 \
      --config "$aap_scratch/curl.conf" -H 'Content-Type: application/json' \
      -X "$method" "${data_args[@]}" -o "$response" -w '%{http_code}' \
      "$aap_host$prefix$path" 2>/dev/null) || code=000
    if [[ $code == 2* ]]; then
      if [[ -s $response ]]; then
        jq -e . "$response" || demo_die "AAP $method ${path%%\?*} returned invalid JSON."
      else
        printf '{}\n'
      fi
      rm -f -- "$response" "$payload"
      return
    fi
    if [[ $method == GET && $code =~ ^(000|502|503|504)$ && $attempt -lt $max_attempts ]]; then
      printf 'AAP GET %s interrupted; retrying.\n' "${path%%\?*}" >&2
      sleep $((attempt * 5))
    else
      demo_die "AAP $method ${path%%\?*} failed (HTTP $code). Inspect AAP before repeating a write with an unknown outcome."
    fi
  done
}

aap_find() {
  local endpoint=$1 name=$2 filters=${3:-'{}'} query
  query=$(jq -rn --arg name "$name" --argjson filters "$filters" \
    '$filters + {name:$name} | to_entries | map((.key|@uri) + "=" + (.value|tostring|@uri)) | join("&")')
  aap_request GET "$endpoint?$query" | jq '.results[0] // null'
}

aap_upsert() {
  local endpoint=$1 name=$2 fields=$3 scope existing id
  scope=$(jq 'with_entries(select(.key == "organization" or .key == "inventory"))' <<<"$fields")
  existing=$(aap_find "$endpoint" "$name" "$scope")
  id=$(jq -r '.id // empty' <<<"$existing")
  if [[ -n $id ]]; then
    if [[ $endpoint == credential_types/ ]] && jq -e --argjson fields "$fields" \
      '. as $existing | all($fields | keys[]; $existing[.] == $fields[.])' <<<"$existing" >/dev/null; then
      printf '%s\n' "$existing"
      return
    fi
    if [[ $endpoint == credentials/ ]] && [[ $(jq .credential_type <<<"$existing") != $(jq .credential_type <<<"$fields") ]]; then
      # Preserve the earlier demo credential-schema migration.
      aap_request DELETE "$endpoint$id/" >/dev/null
    else
      aap_request PATCH "$endpoint$id/" "$fields"
      return
    fi
  fi
  aap_request POST "$endpoint" "$(jq --arg name "$name" '. + {name:$name}' <<<"$fields")"
}

aap_wait() {
  local path=$1 deadline=$((SECONDS + 1800)) job status
  while (( SECONDS < deadline )); do
    job=$(aap_request GET "$path")
    status=$(jq -er .status <<<"$job")
    case $status in
      successful) printf 'AAP %s successful\n' "$path"; return ;;
      failed|error|canceled) demo_die "AAP $path $status; inspect the job in AAP." ;;
    esac
    sleep 5
  done
  demo_die "Timed out waiting for AAP $path."
}

aap_associate() {
  local path=$1 id=$2 attached
  attached=$(aap_request GET "$path?page_size=200")
  if ! jq -e --argjson id "$id" 'any(.results[]; .id == $id)' <<<"$attached" >/dev/null; then
    aap_request POST "$path" "$(jq -n --argjson id "$id" '{id:$id,associate:true}')" >/dev/null
  fi
}

# The shared webhook token is runtime material; GitOps owns its route and alert.
# Reuse it so maintenance runs never invalidate the EDA event stream credential.
demo_alerting_prepare() (
  umask 077
  local scratch domain host uuid
  scratch=$(mktemp -d)
  trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
  domain=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}')
  host=${AAP_HOST:-https://aap-ansible-automation-platform.$domain}
  host=${host%/}
  uuid=$(yq -er '.demo_eda_event_stream.uuid' \
    "$(demo_source_checkout demojam-ansible)/group_vars/aap/eda.yml")
  oc apply --server-side --field-manager=demo-bootstrap \
    -f "$demo_repo_root/cluster/user-workload-monitoring/blackbox-exporter/blackbox-exporter-namespace.yaml"
  if [[ -n $(oc -n blackbox-exporter get secret webapp-eda-webhook --ignore-not-found -o name) ]]; then
    oc -n blackbox-exporter get secret webapp-eda-webhook \
      -o go-template='{{index .data "token" | base64decode}}' >"$scratch/token"
    [[ -s $scratch/token ]] || demo_die 'The existing EDA webhook Secret has no token.'
  else
    openssl rand -hex 32 | tr -d '\n' >"$scratch/token"
  fi
  printf '%s/eda-event-streams/api/eda/v1/external_event_stream/%s/post/' \
    "$host" "$uuid" >"$scratch/url"
  oc -n blackbox-exporter create secret generic webapp-eda-webhook \
    --from-file=token="$scratch/token" --from-file=url="$scratch/url" --dry-run=client -o yaml |
    oc apply --server-side --field-manager=demo-bootstrap -f -
)

aap_credentials() {
  local namespace=ansible-automation-platform org config galaxy community oidc_issuer
  demo_manifest "$aap_scratch" || demo_die 'The subscription ZIP must contain valid RHEL entitlement material.'

  # Persistent token and SSH identity survive ordinary reruns and demo resets.
  cat <<'YAML' | oc -n "$namespace" apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: aap-vm-admin-token
  namespace: ansible-automation-platform
  annotations:
    kubernetes.io/service-account.name: aap-vm-admin
type: kubernetes.io/service-account-token
YAML
  local deadline=$((SECONDS + 120))
  until oc -n "$namespace" get secret aap-vm-admin-token -o json |
    jq -er '.data.token | select(length > 0) | @base64d' >"$aap_scratch/vm-token"; do
    (( SECONDS < deadline )) || demo_die 'Service account token was not populated.'
    sleep 2
  done
  oc -n "$namespace" get secret aap-vm-admin-token \
    -o go-template='{{index .data "ca.crt" | base64decode}}' >"$aap_scratch/ca.crt"

  if [[ -z $(oc -n "$namespace" get secret aap-webapp-ssh --ignore-not-found -o name) ]]; then
    ssh-keygen -q -t ed25519 -N '' -C aap-webapp -f "$aap_scratch/id_ed25519"
    oc -n "$namespace" create secret generic aap-webapp-ssh \
      --from-file=private-key="$aap_scratch/id_ed25519" --from-file=public-key="$aap_scratch/id_ed25519.pub"
  fi
  oc -n "$namespace" get secret aap-webapp-ssh \
    -o go-template='{{index .data "private-key" | base64decode}}' >"$aap_scratch/ssh-private"
  oc -n "$namespace" get secret aap-webapp-ssh \
    -o go-template='{{index .data "public-key" | base64decode}}' >"$aap_scratch/ssh-public"

  org=$(aap_upsert organizations/ demo '{"description":"Disposable automation demo"}' | jq -er .id)
  config=$(aap_upsert credential_types/ 'Demo AAP configuration v2' \
    "$(yq . "$demo_repo_root/bootstrap/aap-dispatch-credential-type.yaml")" | jq -er .id)
  oc -n demojam-keycloak get secret identity-credentials \
    -o go-template='{{index .data "aap-client-secret" | base64decode}}' >"$aap_scratch/oidc-secret"
  oidc_issuer="https://$(oc -n demojam-keycloak get route keycloak -o jsonpath='{.status.ingress[0].host}')/realms/demo"
  oc -n blackbox-exporter get secret webapp-eda-webhook \
    -o go-template='{{index .data "token" | base64decode}}' >"$aap_scratch/eda-token"
  oc -n omnigent-sandboxes get secret omnigent-model \
    -o go-template='{{index .data "FORGEJO_TOKEN" | base64decode}}' >"$aap_scratch/forgejo-token"
  [[ -s $aap_scratch/eda-token && -s $aap_scratch/forgejo-token ]] ||
    demo_die 'Hydrate Forgejo and prepare the EDA webhook before configuring AAP.'
  aap_upsert credentials/ demo-aap-dispatch "$(jq -n --argjson org "$org" --argjson kind "$config" \
    --arg host "$aap_host" --arg username "$aap_username" --rawfile password "$aap_scratch/password" \
    --arg issuer "$oidc_issuer" --rawfile oidc_secret "$aap_scratch/oidc-secret" \
    --arg ee_image "$AAP_EE_IMAGE" --arg vm_host "$DEMO_CLUSTER_SERVER" --rawfile vm_token "$aap_scratch/vm-token" \
    --rawfile vm_ca "$aap_scratch/ca.crt" --rawfile ssh_private "$aap_scratch/ssh-private" \
    --rawfile ssh_public "$aap_scratch/ssh-public" --rawfile entitlement "$aap_scratch/entitlement.pem" \
    --rawfile eda_token "$aap_scratch/eda-token" --rawfile forgejo_token "$aap_scratch/forgejo-token" \
    '{organization:$org,credential_type:$kind,inputs:{host:$host,username:$username,password:$password,
      oidc_issuer:$issuer,oidc_secret:$oidc_secret,ee_image:$ee_image,vm_host:$vm_host,vm_token:($vm_token|rtrimstr("\n")),
      vm_ca:$vm_ca,ssh_private:$ssh_private,ssh_public:($ssh_public|rtrimstr("\n")),entitlement:$entitlement,
      eda_token:$eda_token,forgejo_token:$forgejo_token}}')" >/dev/null
  galaxy=$(aap_find credential_types/ 'Ansible Galaxy/Automation Hub API Token' | jq -er .id)
  community=$(aap_upsert credentials/ demo-galaxy "$(jq -n --argjson org "$org" --argjson kind "$galaxy" \
    '{organization:$org,credential_type:$kind,inputs:{url:"https://galaxy.ansible.com/"}}')" | jq -er .id)
  aap_associate "organizations/$org/galaxy_credentials/" "$community"

  base64 <"$AAP_LICENSE_FILE" | tr -d '\n' >"$aap_scratch/manifest.b64"
  aap_request POST config/ "$(jq -n --rawfile manifest "$aap_scratch/manifest.b64" '{manifest:$manifest}')" >/dev/null
  echo 'AAP license, persistent key material, and configuration credential are ready.'
}

aap_launch() {
  local name=$1 extra=${2:-'{}'} reset=${3:-false} org template result
  case $name in
    webapp_vm|webapp_nginx|aap_configure_all) ;;
    openshift_virtualization_machine) [[ $reset == true ]] || demo_die 'Only seeded demo templates may be launched.' ;;
    *) demo_die 'Only seeded demo templates may be launched.' ;;
  esac
  org=$(aap_find organizations/ demo | jq -er .id)
  template=$(aap_find job_templates/ "$name" "$(jq -n --argjson org "$org" '{organization:$org}')" | jq -er .id)
  result=$(aap_request POST "job_templates/$template/launch/" "$(jq -n --argjson extra "$extra" '{extra_vars:$extra}')")
  local job
  job=$(jq -er .job <<<"$result")
  printf 'Launched %s: job %s\n' "$name" "$job"
  aap_wait "jobs/$job/"
}

aap_reset_vms() {
  local org scope name template project inventory jobs job
  org=$(aap_find organizations/ demo | jq -er .id)
  scope=$(jq -n --argjson org "$org" '{organization:$org}')
  for name in webapp_vm openshift_virtualization_machine; do
    template=$(aap_find job_templates/ "$name" "$scope")
    local playbook=playbooks/openshift_virtualization/webapp-launch.yml
    [[ $name != openshift_virtualization_machine ]] || playbook=playbooks/openshift_virtualization/virtualmachine-manage.yml
    jq -e --arg playbook "$playbook" '.id != null and .playbook == $playbook' <<<"$template" >/dev/null ||
      demo_die "Reset requires the seeded $name template."
    project=$(aap_request GET "projects/$(jq -er .project <<<"$template")/")
    inventory=$(aap_request GET "inventories/$(jq -er .inventory <<<"$template")/")
    [[ $(jq -r .name <<<"$project") == demojam-ansible && $(jq -r .name <<<"$inventory") == demo-inventory ]] ||
      demo_die "Reset refused unexpected project/inventory for $name."
    jobs=$(aap_request GET "jobs/?job_template=$(jq -er .id <<<"$template")&page_size=200")
    while read -r job; do aap_wait "jobs/$job/"; done < <(jq -r '.results[] |
      select(.status == "new" or .status == "pending" or .status == "waiting" or .status == "running") | .id' <<<"$jobs")
  done
  # Both templates are validated before either destructive operation.
  aap_launch webapp_vm '{"host":"demo_cluster","vm_state":"absent"}' true
  aap_launch openshift_virtualization_machine '{"host":"demo_cluster","vm_state":"absent","vm_name":"automation-demo"}' true
}

aap_dispatch() {
  # Bootstrap exclusively owns the objects required to run config-as-code.
  # Keep them out of group_vars/aap; dispatch owns everything downstream.
  local org scope inventory project project_record ee template credential host group update
  org=$(aap_find organizations/ demo | jq -er .id)
  scope=$(jq -n --argjson org "$org" '{organization:$org}')
  ee=$(aap_upsert execution_environments/ demo-aap-ee "$(jq -n --argjson org "$org" --arg image "$AAP_EE_IMAGE" \
    '{organization:$org,image:$image,pull:"always"}')" | jq -er .id)
  project_record=$(aap_upsert projects/ demojam-ansible "$(jq -n --argjson org "$org" '{
    organization:$org,scm_type:"git",scm_url:"http://forgejo.forgejo.svc.cluster.local:3000/demo-owner/demojam-ansible.git",
    scm_branch:"main",credential:null,scm_update_on_launch:true,scm_update_cache_timeout:30}')")
  project=$(jq -er .id <<<"$project_record")
  if jq -e '.current_update != null' <<<"$project_record" >/dev/null; then
    aap_wait "project_updates/$(jq -er .current_update <<<"$project_record")/"
  fi
  update=$(aap_request POST "projects/$project/update/" '{}')
  aap_wait "project_updates/$(jq -er .id <<<"$update")/"
  inventory=$(aap_upsert inventories/ demo-inventory "$scope" | jq -er .id)
  host=$(aap_upsert hosts/ aap_demo "$(jq -n --argjson inventory "$inventory" \
    '{inventory:$inventory,variables:({ansible_connection:"local"}|tojson)}')" | jq -er .id)
  group=$(aap_upsert groups/ aap "$(jq -n --argjson inventory "$inventory" '{inventory:$inventory}')" | jq -er .id)
  aap_associate "groups/$group/hosts/" "$host"
  credential=$(aap_find credentials/ demo-aap-dispatch "$scope" | jq -er .id)
  template=$(aap_upsert job_templates/ aap_configure_all "$(jq -n \
    --argjson inventory "$inventory" --argjson project "$project" --argjson ee "$ee" \
    '{inventory:$inventory,project:$project,execution_environment:$ee,job_type:"run",
      playbook:"playbooks/aap/configure-aap.yml",ask_variables_on_launch:false,extra_vars:"{}",
      description:"Sync all demo AAP configuration from Forgejo"}')" | jq -er .id)
  aap_associate "job_templates/$template/credentials/" "$credential"
  aap_launch aap_configure_all
  aap_wait_eda
}

# An enabled activation record does not prove that its rulebook is running.
aap_wait_eda() {
  local name query status previous='' deadline=$((SECONDS + 600))
  name=$(yq -er '.demo_eda_activation.name' \
    "$(demo_source_checkout demojam-ansible)/group_vars/aap/eda.yml")
  query=$(jq -rn --arg name "$name" '$name | @uri')
  while (( SECONDS < deadline )); do
    status=$(aap_request GET "activations/?name=$query" '' /api/eda/v1/ |
      jq -er '.results[0].status // "absent"')
    [[ $status != running ]] || { printf 'EDA activation %s is running.\n' "$name"; return; }
    [[ $status == "$previous" ]] || printf 'Waiting for EDA activation %s: %s\n' "$name" "$status"
    previous=$status
    sleep 10
  done
  demo_die "Timed out waiting for EDA activation $name ($status); inspect its logs in AAP."
}

# Retire only the three legacy bootstrap CRs. No finalizer means deleting the
# Kubernetes records cannot request deletion of their existing AAP objects.
aap_retire_resource_crs() {
  local resource object
  for resource in jobtemplate/aap-configure-all ansibleproject/demojam-ansible ansibleinventory/demo-inventory; do
    object=$(oc -n ansible-automation-platform get "$resource" --ignore-not-found -o json)
    [[ -n $object ]] || continue
    jq -e '(.metadata.finalizers // [] | length) == 0 and
      .spec.connection_secret == "aap-resource-connection" and (.spec.state // "present") == "present"' <<<"$object" >/dev/null ||
      demo_die "Refusing to retire unexpected or finalized Resource Operator object $resource."
    oc -n ansible-automation-platform delete "$resource" --wait=true
  done
}

# All AAP actions share one private session and the same supported EE selection.
demo_aap() (
  umask 077
  local aap_scratch aap_host aap_username
  aap_scratch=$(mktemp -d)
  trap 'rm -rf -- "$aap_scratch"' EXIT
  aap_connect
  case $1 in
    credentials) aap_credentials ;;
    dispatch) aap_dispatch ;;
    reset-vms) aap_reset_vms ;;
    launch) shift; aap_launch "$@" ;;
    *) demo_die 'Unknown AAP action.' ;;
  esac
)

demo_aap_configure() {
  demo_verify_cluster
  demo_wait_for_api
  demo_readiness aap
  aap_retire_resource_crs
  demo_alerting_prepare
  demo_aap credentials

  demo_aap dispatch
  demo_identity_aap_callback
  echo 'AAP configuration from Forgejo completed.'
}

demo_webapp() {
  demo_verify_cluster
  demo_wait_for_api
  case $1 in
    create) demo_readiness aap; demo_aap launch webapp_vm ;;
    nginx) demo_aap launch webapp_nginx ;;
    delete) demo_aap launch webapp_vm '{"vm_state":"absent"}' ;;
    sync) demo_aap launch aap_configure_all ;;
    verify)
      local host pod metrics login_redirect ingress_domain
      oc -n webapp-vms wait --for=condition=Ready vm/webapp --timeout=15m
      host=$(oc -n webapp-vms get route webapp -o jsonpath='{.status.ingress[0].host}')
      ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default -o jsonpath='{.status.domain}')
      login_redirect=$(curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
        --write-out '%{http_code}\n%{redirect_url}' --output /dev/null "https://$host/")
      [[ $login_redirect == $'302\n'"https://demojam-keycloak.$ingress_domain/realms/demo/protocol/openid-connect/auth?"* ]] ||
        demo_die 'Webapp did not redirect an unauthenticated browser to demojam-keycloak.'
      pod=$(oc -n blackbox-exporter get pods -l app=blackbox-exporter -o jsonpath='{.items[0].metadata.name}')
      metrics=$(oc -n blackbox-exporter exec "$pod" -- wget -qO- \
        'http://127.0.0.1:9115/probe?module=http_2xx&target=http%3A%2F%2Fwebapp.webapp-vms.svc.cluster.local%2F')
      [[ $metrics == *'probe_success 1'* ]] || demo_die 'Webapp blackbox probe failed.'
      printf 'RHEL webapp and blackbox probe are healthy: https://%s/\n' "$host"
      ;;
    *) demo_die 'Usage: webapp create|nginx|delete|sync|verify' ;;
  esac
}

# -----------------------------------------------------------------------------
# GitOps rollout: overrides belong to Argo, so self-heal retains operator inputs
# -----------------------------------------------------------------------------

demo_root_application() {
  local monitoring storage=$1
  monitoring=$(yq -r '.data."config.yaml"' "$demo_repo_root/cluster/user-workload-monitoring/user-workload-monitoring-config-configmap.yaml" |
    yq -y --arg storage "$storage" '(.prometheus,.thanosRuler,.alertmanager).volumeClaimTemplate.spec.storageClassName = $storage')
  yq . "$demo_repo_root/bootstrap/config/root-application.yaml" |
    jq --arg branch "$gitops_branch" --arg repo "$gitops_repo" --arg storage "$storage" --arg monitoring "$monitoring" '
      def patch($target; $operations): {target:$target,patch:($operations|tojson)};
      .spec.source.repoURL = $repo |
      .spec.source.targetRevision = $branch |
      .spec.source.kustomize.patches = [
        patch({group:"argoproj.io",version:"v1alpha1",kind:"Application"}; [
          {op:"replace",path:"/spec/source/targetRevision",value:$branch},
          {op:"replace",path:"/spec/source/repoURL",value:$repo}
        ]),
        patch({group:"argoproj.io",version:"v1alpha1",kind:"AppProject",name:"cluster-config"}; [
          {op:"replace",path:"/spec/sourceRepos",value:[$repo]}
        ]),
        patch({group:"argoproj.io",version:"v1alpha1",kind:"Application",name:"ansible-automation-platform"}; [
          {op:"add",path:"/spec/source/kustomize",value:{patches:[
            patch({group:"aap.ansible.com",kind:"AnsibleAutomationPlatform",name:"aap"}; [
              {op:"replace",path:"/spec/database/postgres_storage_class",value:$storage}
            ])
          ]}}
        ]),
        patch({group:"argoproj.io",version:"v1alpha1",kind:"Application",name:"user-workload-monitoring"}; [
          {op:"add",path:"/spec/source/kustomize",value:{patches:[
            patch({version:"v1",kind:"ConfigMap",name:"user-workload-monitoring-config"}; [
              {op:"replace",path:"/data/config.yaml",value:$monitoring}
            ])
          ]}}
        ])
      ]'
}

demo_bootstrap() (
  local bootstrap_dir="$demo_repo_root/bootstrap" repo_root="$demo_repo_root"
  local operator_namespace=openshift-gitops-operator gitops_namespace=openshift-gitops
  demo_step 'Check operator inputs and cluster prerequisites'
  demo_preflight
  local sandbox_image
  sandbox_image=$(demo_sandbox_image)
  demo_verify_cluster

  # A demo branch can be tracked without committing branch-specific defaults.
  # The branch must already contain the checked-out commit on origin.
  gitops_branch=${BOOTSTRAP_BRANCH:-main}
  gitops_repo=$BOOTSTRAP_REPO_URL
  git check-ref-format --branch "$gitops_branch" >/dev/null
  target_revision=$(git -C "$repo_root" rev-parse HEAD)
  git -C "$repo_root" diff --quiet HEAD -- bootstrap cluster .helm ||
    demo_die 'Commit and publish the bootstrap/manifests before rollout; local inputs must match GitOps.'
  published_revision=$(git -C "$repo_root" ls-remote "$gitops_repo" "refs/heads/$gitops_branch" | cut -f1)
  [[ $published_revision == "$target_revision" ]] || {
    echo "Publish the checked-out revision to origin/$gitops_branch before bootstrap." >&2; exit 1;
  }
  echo "Tracking GitOps branch $gitops_branch."
  storage_class=${BOOTSTRAP_STORAGE_CLASS:-$(oc get storageclasses -o json | jq -er '
    [.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true" or
      .metadata.annotations["storageclass.beta.kubernetes.io/is-default-class"] == "true")] |
    sort_by(.metadata.creationTimestamp) | last | .metadata.name')}

  # The Route manifests request stable subdomains from this cluster's ingress
  # controller. Forgejo also needs its public URL for links and callbacks.
  ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default \
    -o jsonpath='{.status.domain}')
  [[ -n "$ingress_domain" ]] || {
    echo 'The default ingress controller has no domain.' >&2
    exit 1
  }

  # Follow the Red Hat CLI installation flow: namespace, OperatorGroup, then
  # Subscription. Create our own instance with native OIDC from its first start.
  demo_step 'Install OpenShift GitOps'
  oc apply -f "$bootstrap_dir/openshift-gitops-operator-namespace.yaml"
  oc apply -f "$bootstrap_dir/openshift-gitops-operator-operatorgroup.yaml"
  oc apply -f "$bootstrap_dir/openshift-gitops-namespace.yaml"
  local legacy_argo=''
  if [[ -n $(oc get crd argocds.argoproj.io --ignore-not-found -o name) ]]; then
    legacy_argo=$(oc -n "$gitops_namespace" get argocd openshift-gitops --ignore-not-found -o name)
  fi
  # Disabling the default instance deletes its controllers, not the Applications
  # or their workloads. The operator uses shared settings names per namespace,
  # so finish removing the old instance before creating the replacement.
  oc apply -f "$bootstrap_dir/openshift-gitops-operator-subscription.yaml"
  if [[ -n $legacy_argo ]]; then
    oc -n "$gitops_namespace" wait --for=delete argocd/openshift-gitops --timeout=15m
    oc -n "$gitops_namespace" wait --for=delete \
      deployment/openshift-gitops-server statefulset/openshift-gitops-application-controller \
      configmap/argocd-cm configmap/argocd-rbac-cm secret/argocd-secret --timeout=15m
  fi

  echo 'Waiting for the OpenShift GitOps operator installation...'
  deadline=$((SECONDS + 900))
  until installed_csv=$(oc -n "$operator_namespace" get subscription openshift-gitops-operator \
    -o jsonpath='{.status.installedCSV}' 2>/dev/null) && [[ -n "$installed_csv" ]]; do
    (( SECONDS < deadline )) || demo_die 'Timed out waiting for the GitOps installed CSV.'
    sleep 5
  done
  oc -n "$operator_namespace" wait --for=jsonpath='{.status.phase}'=Succeeded \
    "clusterserviceversion/$installed_csv" --timeout=15m
  operator_deployments=$(oc -n "$operator_namespace" get \
    "clusterserviceversion/$installed_csv" \
    -o jsonpath='{.spec.install.spec.deployments[*].name}')
  for deployment in $operator_deployments; do
    oc -n "$operator_namespace" rollout status "deployment/$deployment" --timeout=10m
  done

  demo_step 'Prepare demo identity credentials and user catalog'
  demo_identity_prepare
  demo_homepage_prepare
  demo_alerting_prepare
  yq . "$bootstrap_dir/config/openshift-gitops-argocd.yaml" |
    jq --arg issuer "https://demojam-keycloak.$ingress_domain/realms/demo" \
      '.spec.oidcConfig |= gsub("__DEMO_OIDC_ISSUER__"; $issuer)' |
    oc apply --server-side --field-manager=demo-bootstrap -f -
  oc apply -f "$bootstrap_dir/config/openshift-gitops-cluster-permissions.yaml"
  oc -n "$gitops_namespace" wait --for=jsonpath='{.status.phase}'=Available \
    argocd/demojam-gitops --timeout=15m
  oc -n "$gitops_namespace" rollout status deployment/demojam-gitops-server --timeout=15m
  # Pod-wide waits capture terminating replicas during an operator rollout and
  # can wait on deleted pods. Follow the stable workload controllers instead.
  local gitops_workloads gitops_workload
  gitops_workloads=$(oc -n "$gitops_namespace" get deployments,statefulsets -o json |
    jq -r '.items[] | select(.metadata.deletionTimestamp == null) | (.kind | ascii_downcase) + "/" + .metadata.name')
  while IFS= read -r gitops_workload; do
    oc -n "$gitops_namespace" rollout status "$gitops_workload" --timeout=15m
  done <<<"$gitops_workloads"

  echo 'Waiting for the Argo CD cluster permissions...'
  deadline=$((SECONDS + 300))
  until oc get clusterrolebinding openshift-gitops-demo-manager >/dev/null 2>&1; do
    (( SECONDS < deadline )) || demo_die 'Timed out waiting for Argo CD permissions.'
    sleep 5
  done
  # Identity preparation created the consumer namespaces. The sandbox runner
  # also needs its namespace before the first child sync can mount its Secrets.
  oc apply --server-side --field-manager=demo-bootstrap -f "$repo_root/cluster/omnigent/omnigent-sandboxes-namespace.yaml"
  if ! oc -n rhdh get secret rhdh-pg-credentials >/dev/null 2>&1; then
    umask 077
    db_password_file=$(mktemp)
    trap '[[ -z ${db_password_file:-} ]] || rm -f "$db_password_file"' EXIT
    openssl rand -hex 32 | tr -d '\n' > "$db_password_file"
    oc -n rhdh create secret generic rhdh-pg-credentials \
      --from-literal=username=backstage \
      --from-file=password="$db_password_file"
    rm -f "$db_password_file"
    db_password_file=
  fi
  oc -n forgejo create configmap forgejo-url \
    --from-literal="root-url=https://forgejo.$ingress_domain/" \
    --dry-run=client -o yaml | oc -n forgejo apply -f -
  demo_model_config
  demo_omnigent_auth

  echo 'OpenShift GitOps is healthy; starting the app-of-apps rollout...'
  # Native Argo Kustomize patches override child refs only on this cluster.
  # Checked-in defaults remain main and are safe to merge.
  demo_step 'Roll out applications and hydrate Forgejo'
  demo_root_application "$storage_class" | oc -n "$gitops_namespace" apply -f -
  oc -n "$gitops_namespace" annotate application cluster \
    argocd.argoproj.io/refresh=hard --overwrite

  echo 'Waiting for Argo CD to refresh the root application...'
  deadline=$((SECONDS + 300))
  local rollout_previous='' rollout_snapshot
  until [[ $(oc -n "$gitops_namespace" get application cluster \
    -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/refresh}') != hard ]]; do
    (( SECONDS < deadline )) || demo_die 'Timed out waiting for the root application refresh.'
    sleep 2
  done

  deadline=$((SECONDS + 3600))
  demo_step 'Provision demo identity before application OIDC discovery'
  demo_identity_configure
  demo_identity_openshift
  for app in demojam-keycloak forgejo rhdh omnigent automation-orchestrator; do
    until oc -n "$gitops_namespace" get application "$app" >/dev/null 2>&1; do
      if (( SECONDS >= deadline )); then
        echo "Timed out waiting for the $app Application." >&2
        exit 1
      fi
      sleep 5
    done
    oc -n "$gitops_namespace" annotate application "$app" \
      argocd.argoproj.io/refresh=hard --overwrite
    until [[ $(oc -n "$gitops_namespace" get application "$app" \
      -o jsonpath='{.status.sync.revision}') == "$target_revision" ]]; do
      if (( SECONDS >= deadline )); then
        echo "Timed out waiting for $app to read $target_revision." >&2
        exit 1
      fi
      sleep 5
    done
    if [[ $app == forgejo ]]; then
      until oc -n forgejo get deployment forgejo >/dev/null 2>&1; do
        if (( SECONDS >= deadline )); then
          echo 'Timed out waiting for the Forgejo Deployment.' >&2
          exit 1
        fi
        sleep 5
      done
      demo_hydrate hydrate
    fi
  done
  for route_ref in demojam-keycloak/keycloak forgejo/forgejo \
    omnigent/omnigent \
    automation-orchestrator/automation-orchestrator; do
    route_namespace=${route_ref%%/*}
    route_name=${route_ref#*/}
    until route_json=$(oc -n "$route_namespace" get route "$route_name" \
      -o json 2>/dev/null) && \
      assigned_host=$(jq -r '.status.ingress[0].host // ""' <<<"$route_json") && \
      [[ "$assigned_host" == *".$ingress_domain" ]]; do
      if (( SECONDS >= deadline )); then
        echo "Timed out waiting for $route_ref on $ingress_domain." >&2
        exit 1
      fi
      sleep 5
    done
  done
  until [[ $(oc -n "$gitops_namespace" get application cluster \
    -o jsonpath='{.status.sync.status}') == Synced ]] && \
    [[ $(oc -n "$gitops_namespace" get application cluster \
    -o jsonpath='{.status.health.status}') == Healthy ]] && \
    [[ $(oc -n "$gitops_namespace" get application cluster \
    -o jsonpath='{.status.sync.revision}') == "$target_revision" ]]; do
    rollout_snapshot=$(oc -n "$gitops_namespace" get applications \
      -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status)
    if [[ $rollout_snapshot != "$rollout_previous" ]]; then
      printf '%s\n' "$rollout_snapshot"
      rollout_previous=$rollout_snapshot
    fi
    if (( SECONDS >= deadline )); then
      echo 'Timed out waiting for the app-of-apps rollout.' >&2
      exit 1
    fi
    sleep 10
  done

  oc -n "$gitops_namespace" get applications \
    -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status

  for app in openshift-pipelines agent-sandbox-operator openshift-virtualization omnigent automation-orchestrator ansible-automation-platform webapp-vms user-workload-monitoring homepage; do
    oc -n "$gitops_namespace" annotate application "$app" \
      argocd.argoproj.io/refresh=hard --overwrite
    deadline=$((SECONDS + 1800))
    until [[ $(oc -n "$gitops_namespace" get application "$app" \
      -o jsonpath='{.status.sync.revision}') == "$target_revision" ]] && \
      [[ $(oc -n "$gitops_namespace" get application "$app" \
      -o jsonpath='{.status.sync.status}') == Synced ]] && \
      [[ $(oc -n "$gitops_namespace" get application "$app" \
      -o jsonpath='{.status.health.status}') == Healthy ]]; do
      if (( SECONDS >= deadline )); then
        echo "Timed out waiting for $app to sync $target_revision." >&2
        exit 1
      fi
      sleep 10
    done
  done

  # Operator health does not prove guest images or workload controllers are ready.
  # AO's generated Route is now available; register its exact OIDC callback.
  demo_identity_configure
  demo_readiness sandbox
  demo_readiness aap

  # Build only after the operator rollout, keeping image storage on a PVC.
  demo_step 'Build or reuse the OpenCode sandbox image'
  sandbox_image_current() {
    local built_revision
    built_revision=$(oc -n omnigent-sandboxes get pipelineruns -l tekton.dev/pipeline=omnigent-opencode \
      -o json | jq -r --arg image "$sandbox_image" '[.items[] |
        select(any(.status.conditions[]?; .type == "Succeeded" and .status == "True")) |
        select(any(.status.results[]?; .name == "IMAGE" and .value == $image))] |
        sort_by(.metadata.creationTimestamp) | last | .status.results[]? |
        select(.name == "SOURCE_COMMIT") | .value')
    [[ "$built_revision" =~ ^[0-9a-f]{40}$ ]] &&
      git -C "$repo_root" diff --quiet "$built_revision" HEAD -- cluster/omnigent/image
  }
  if [[ ${BOOTSTRAP_FORCE_SANDBOX_BUILD:-false} == true ]] ||
     ! oc -n omnigent-sandboxes get imagestreamtag "${sandbox_image##*/}" >/dev/null 2>&1 ||
     ! sandbox_image_current; then
    echo 'Building the OpenCode sandbox image from the current Git revision...'
    SANDBOX_BUILD_REVISION="$target_revision" demo_sandbox_build
  fi
  sandbox_image_current
  oc get crd sandboxes.agents.x-k8s.io
  oc -n omnigent rollout status deployment/omnigent --timeout=10m
  desired_sandbox_image=$(yq -r '.data."config.yaml"' \
    "$repo_root/cluster/omnigent/omnigent-sandbox-config-configmap.yaml" |
    yq -r '.sandbox.kubernetes.image')
  mounted_sandbox_image=$(oc -n omnigent exec deployment/omnigent -c omnigent -- \
    cat /etc/omnigent/config.yaml | yq -r '.sandbox.kubernetes.image')
  desired_agent_path=$(yq -r '.data.OMNIGENT_BUILTIN_AGENT_DIRS' \
    "$repo_root/cluster/omnigent/omnigent-config-configmap.yaml")
  mounted_agent_path=$(oc -n omnigent exec deployment/omnigent -c omnigent -- \
    printenv OMNIGENT_BUILTIN_AGENT_DIRS)
  if [[ "$mounted_sandbox_image" != "$desired_sandbox_image" ||
        "$mounted_agent_path" != "$desired_agent_path" ]]; then
    echo 'Reloading Omnigent to use the current sandbox image and agent...'
    oc -n omnigent rollout restart deployment/omnigent
    oc -n omnigent rollout status deployment/omnigent --timeout=10m
  fi
  demo_verify_goldenpaths
  # The Argo CD health check only requires the AutomationOrchestrator Ready
  # condition. Wait for the UI and backend Deployments before publishing the
  # dispatch workflow so the Route has endpoints.
  for deploy in automation-orchestrator-ui automation-orchestrator-backend; do
    if oc -n automation-orchestrator get "deployment/$deploy" >/dev/null 2>&1; then
      oc -n automation-orchestrator rollout status "deployment/$deploy" --timeout=10m
    fi
  done
  oc -n omnigent delete secret omnigent-auth omnigent-machine-client \
    --ignore-not-found
  demo_step 'Configure AAP through its Controller'
  demo_aap_configure
  if [[ ${BOOTSTRAP_RECONCILE_WORKFLOW:-true} == true ]]; then
    demo_step 'Validate and publish the AO workflow'
    demo_ao_reconcile
  else
    demo_ao_reconcile identity-only
  fi
  demo_step 'Provision the RHEL webapp through AAP'
  demo_webapp create
  demo_step 'Install nginx through AAP'
  demo_webapp nginx
  demo_step 'Verify the webapp and monitoring probe'
  demo_webapp verify
  demo_step 'Populate and verify Homepage navigation and dashboard'
  demo_homepage_configure bootstrap

  printf '\nBootstrap completed on %s at %s.\n' "$gitops_branch" "$target_revision"
  for ref in homepage/homepage demojam-keycloak/keycloak forgejo/forgejo rhdh/backstage-rhdh-developer-hub \
    omnigent/omnigent automation-orchestrator/automation-orchestrator ansible-automation-platform/aap; do
    host=$(oc -n "${ref%%/*}" get route "${ref#*/}" -o jsonpath='{.status.ingress[0].host}')
    printf '%-30s https://%s\n' "${ref%%/*}" "$host"
  done
  echo 'Initial user passwords: Secret demojam-keycloak/demo-user-passwords (passwords.json).'
)

# -----------------------------------------------------------------------------
# Full removal keeps controllers running until their operands have finalized.
# The durable, secret-free inventory also supports resuming interrupted removal.
demo_teardown() (
  [[ $# == 1 && $1 == --confirm-demo-teardown ]] ||
    demo_die 'Usage: teardown --confirm-demo-teardown (deletes demo data and operators).'
  demo_verify_cluster
  local state="$demo_repo_root/.rendered/demo-teardown.json" scratch app namespace kind group name resource csv crd
  local -a namespaces=(homepage blackbox-exporter webapp-vms automation-vms molecule-tests
    omnigent-sandboxes omnigent forgejo rhdh demojam-keycloak automation-orchestrator
    ansible-automation-platform agent-sandbox-system openshift-virtualization-os-images
    openshift-cnv openshift-pipelines cloudnative-pg openshift-gitops openshift-gitops-operator)
  umask 077
  scratch=$(mktemp -d)
  trap 'find "$scratch" -type f -delete; rmdir "$scratch"' EXIT
  mkdir -p "$demo_repo_root/.rendered"
  if [[ -n $(oc get crd applications.argoproj.io --ignore-not-found -o name) ]]; then
    oc -n openshift-gitops get applications -o json >"$scratch/apps.json"
  else
    printf '{"items":[]}' >"$scratch/apps.json"
  fi
  jq -e --arg repo "$BOOTSTRAP_REPO_URL" 'all(.items[]; .spec.source.repoURL == $repo)' "$scratch/apps.json" >/dev/null ||
    demo_die 'Unexpected GitOps applications found; refusing to remove another stack.'
  if [[ $(jq '.items|length' "$scratch/apps.json") != 0 || ! -f $state ]]; then
    yq -s . "$demo_repo_root"/cluster/*/*subscription.yaml "$demo_repo_root"/bootstrap/*subscription.yaml |
      jq '[.[] | {name:.metadata.name,namespace:.metadata.namespace}]' >"$scratch/subscriptions.json"
    oc get subscriptions.operators.coreos.com -A -o json >"$scratch/live-subscriptions.json"
    oc get clusterserviceversions.operators.coreos.com -A -o json |
      jq --slurpfile subscriptions "$scratch/subscriptions.json" --slurpfile live "$scratch/live-subscriptions.json" '
      [.items[] as $csv | select(any($subscriptions[0][]; . as $wanted |
        any($live[0].items[]; .metadata.name == $wanted.name and .metadata.namespace == $wanted.namespace and
          .status.installedCSV == $csv.metadata.name and .metadata.namespace == $csv.metadata.namespace))) |
        {name:$csv.metadata.name,namespace:$csv.metadata.namespace,
          crds:[$csv.spec.customresourcedefinitions.owned[]?.name]}]' >"$scratch/csvs.json"
    oc get crd -o json | jq '[.items[] | select(.spec.group | test("(^|\\.)(kubevirt\\.io|tekton\\.dev)$")) | .metadata.name]' >"$scratch/operand-crds.json"
    jq -n --arg server "$DEMO_CLUSTER_SERVER" --arg repo "$BOOTSTRAP_REPO_URL" \
      --slurpfile apps "$scratch/apps.json" --slurpfile subscriptions "$scratch/subscriptions.json" \
      --slurpfile csvs "$scratch/csvs.json" --slurpfile operands "$scratch/operand-crds.json" \
      '{server:$server,repo:$repo,apps:[$apps[0].items[].metadata.name],
        resources:([$apps[0].items[].status.resources[]?] | unique_by([.group,.kind,.namespace,.name])),
        subscriptions:$subscriptions[0],csvs:$csvs[0],crds:([$csvs[0][].crds[]]+$operands[0]|unique)}' >"$state"
  fi
  jq -e --arg server "$DEMO_CLUSTER_SERVER" --arg repo "$BOOTSTRAP_REPO_URL" \
    '.server == $server and .repo == $repo' "$state" >/dev/null || demo_die 'Teardown inventory belongs to a different cluster or repository.'

  demo_step 'Stop demo GitOps reconciliation'
  # Root first: it must not recreate children while they are being detached.
  while IFS= read -r app; do
    if [[ -n $(oc -n openshift-gitops get application "$app" --ignore-not-found -o name 2>/dev/null) ]]; then
      oc -n openshift-gitops patch application "$app" --type=merge \
        --patch '{"metadata":{"finalizers":[]},"spec":{"syncPolicy":{"automated":null}},"operation":null}' >/dev/null
      oc -n openshift-gitops delete application "$app" --wait=true --timeout=2m
    fi
  done < <(jq -r '.apps | (["cluster"] + map(select(. != "cluster")))[]' "$state")

  demo_step 'Remove demo OpenShift identity integration'
  oc get oauth cluster -o json | jq '{spec:{identityProviders:(.spec.identityProviders // [] | map(select(.name != "demojam-keycloak")))}}' >"$scratch/oauth-patch.json"
  oc patch oauth cluster --type=merge --patch-file "$scratch/oauth-patch.json" >/dev/null
  oc -n openshift-config delete secret demojam-keycloak-oidc --ignore-not-found
  oc delete group demojam-admins --ignore-not-found

  demo_step 'Remove agent sandboxes and demo virtual machines'
  if [[ -n $(oc -n omnigent get deployment omnigent --ignore-not-found -o name 2>/dev/null) ]]; then
    oc -n omnigent scale deployment omnigent --replicas=0
  fi
  if [[ -n $(oc get crd sandboxes.agents.x-k8s.io --ignore-not-found -o name) ]]; then
    oc -n omnigent-sandboxes delete sandboxes --all --ignore-not-found --wait=true --timeout=10m
  fi
  if [[ -n $(oc get crd virtualmachines.kubevirt.io --ignore-not-found -o name) ]]; then
    for namespace in webapp-vms automation-vms molecule-tests; do
      oc -n "$namespace" delete virtualmachines --all --ignore-not-found --wait=true --timeout=10m
      oc -n "$namespace" delete virtualmachineinstances --all --ignore-not-found --wait=true --timeout=10m
      oc -n "$namespace" delete datavolumes --all --ignore-not-found --wait=true --timeout=10m
    done
  fi

  demo_step 'Remove demo application resources while operators are available'
  # Instances before Services/RBAC; databases before PostgreSQL clusters.
  while IFS=$'\t' read -r kind group namespace name; do
    resource=$kind
    [[ $group == - ]] || resource="$kind.$group"
    local -a scope=()
    [[ $namespace == - ]] || scope=(-n "$namespace")
    if oc "${scope[@]}" get "$resource" "$name" -o name >/dev/null 2>&1; then
      oc "${scope[@]}" delete "$resource" "$name" --ignore-not-found --wait=true --timeout=15m
    fi
  done < <(jq -r '.resources | map(select(.kind != "Namespace" and .kind != "Subscription" and
    .kind != "OperatorGroup" and .kind != "Application" and .kind != "AppProject" and
    .kind != "PersistentVolumeClaim" and .name != "cluster-monitoring-config")) |
    sort_by(if .kind == "AnsibleAutomationPlatform" or .kind == "AutomationOrchestrator" or .kind == "Backstage" then 0
      elif .kind == "Database" then 1 elif .kind == "Cluster" then 2 elif .kind == "HyperConverged" then 3 else 4 end)[] |
    [.kind,(.group // "" | if . == "" then "-" else . end),(.namespace // "" | if . == "" then "-" else . end),.name] | @tsv' "$state")
  if [[ -n $(oc get crd tektonconfigs.operator.tekton.dev --ignore-not-found -o name) ]]; then
    oc delete tektonconfig config --ignore-not-found --wait=true --timeout=15m
  fi
  if [[ -n $(oc get crd argocds.argoproj.io --ignore-not-found -o name) ]]; then
    oc -n openshift-gitops delete argocd demojam-gitops --ignore-not-found --wait=true --timeout=10m
  fi

  demo_step 'Disable demo user workload monitoring and remove its storage'
  if [[ -n $(oc -n openshift-monitoring get configmap cluster-monitoring-config --ignore-not-found -o name) ]]; then
    oc -n openshift-monitoring get configmap cluster-monitoring-config -o json >"$scratch/monitoring.json"
    jq -r '.data."config.yaml" // "{}"' "$scratch/monitoring.json" | yq -y 'del(.enableUserWorkload)' >"$scratch/monitoring.yaml"
    if [[ $(yq 'length' "$scratch/monitoring.yaml") == 0 ]]; then
      oc -n openshift-monitoring delete configmap cluster-monitoring-config --ignore-not-found
    else
      jq -n --rawfile config "$scratch/monitoring.yaml" '{data:{"config.yaml":$config}}' >"$scratch/monitoring-patch.json"
      oc -n openshift-monitoring patch configmap cluster-monitoring-config --type=merge --patch-file "$scratch/monitoring-patch.json"
    fi
  fi
  if [[ -n $(oc -n openshift-user-workload-monitoring get pods -o name) ]]; then
    oc -n openshift-user-workload-monitoring wait --for=delete pod --all --timeout=10m
  fi
  while IFS= read -r name; do
    [[ -z $name ]] || oc -n openshift-user-workload-monitoring delete pvc "$name" --wait=true --timeout=10m
  done < <(oc -n openshift-user-workload-monitoring get pvc -o json | jq -r '.items[] | select(.metadata.name | test("^(prometheus|thanos-ruler|alertmanager)-user-workload-")) | .metadata.name')

  demo_step 'Remove installed demo operator APIs and subscriptions'
  # Stop automatic OLM reinstallation before removing APIs. Other subscriptions
  # (workshop Keycloak, cert-manager and storage) are deliberately outside this list.
  while IFS=$'\t' read -r namespace name; do
    oc -n "$namespace" delete subscription "$name" --ignore-not-found --wait=true --timeout=2m
  done < <(jq -r '.subscriptions[] | [.namespace,.name] | @tsv' "$state")
  while IFS= read -r crd; do
    # Refuse to erase custom resources belonging to namespaces outside this demo.
    local instances
    if instances=$(oc get "$crd" -A -o json 2>/dev/null); then
      jq -e --argjson namespaces "$(printf '%s\n' "${namespaces[@]}" | jq -R . | jq -s .)" \
        'all(.items[]; .metadata.namespace == null or (.metadata.namespace as $ns | $namespaces | index($ns)))' <<<"$instances" >/dev/null ||
        demo_die "API $crd has non-demo instances; refusing to uninstall its operator."
    fi
    oc delete crd "$crd" --ignore-not-found --wait=true --timeout=15m
  done < <(jq -r '.crds[]' "$state")
  while IFS=$'\t' read -r namespace csv; do
    oc -n "$namespace" delete clusterserviceversion "$csv" --ignore-not-found --wait=true --timeout=5m
    oc delete clusterrole,clusterrolebinding -l "olm.owner=$csv,olm.owner.namespace=$namespace" --ignore-not-found
  done < <(jq -r '.csvs[] | [.namespace,.name] | @tsv' "$state")
  oc delete -f "$demo_repo_root/bootstrap/config/openshift-gitops-cluster-permissions.yaml" --ignore-not-found

  demo_step 'Remove demo namespaces and persistent data'
  for namespace in "${namespaces[@]}"; do
    oc delete namespace "$namespace" --ignore-not-found --wait=false
  done
  for namespace in "${namespaces[@]}"; do
    if [[ -n $(oc get namespace "$namespace" --ignore-not-found -o name) ]]; then
      oc wait --for=delete "namespace/$namespace" --timeout=15m
    fi
  done
  oc wait clusteroperator/authentication --for=condition=Available=True --timeout=10m
  oc wait clusteroperator/authentication --for=condition=Progressing=False --timeout=10m
  local remaining
  remaining=$(oc get pv -o json | jq -r --argjson namespaces "$(printf '%s\n' "${namespaces[@]}" | jq -R . | jq -s .)" \
    '.items[] | .spec.claimRef.namespace as $ns | select($namespaces | index($ns)) | .metadata.name')
  [[ -z $remaining ]] || demo_die "Demo PVs are still being reclaimed: $remaining. Inspect storage before reinstalling."
  echo 'Demo teardown completed: applications, operators, APIs, identity integration and persistent data removed.'
)

# Command entry point. Help is local and does not load .env.
# -----------------------------------------------------------------------------

demo_main() {
  local command=${1:-bootstrap}
  if [[ $command == help || $command == --help || $command == -h ]]; then
    cat <<'HELP'
Usage: bash bootstrap/bootstrap.sh [COMMAND]

  bootstrap          Install/configure the platform, create the RHEL VM, install nginx, verify
  teardown --confirm-demo-teardown Remove the entire demo stack, operators and persistent data
  preflight          Read-only input and pre-install cluster checks (also --check)
  sandbox-build      Build the configured :latest sandbox image
  model-config       Apply the selected model/agent configuration
  identity           Reconcile demo users, clients and application login
  homepage-refresh   Refresh Homepage links, repositories and environment details
  hydrate            Seed Forgejo and refresh Backstage/agent credentials
  ao-configure      Reconcile AO LLM/AAP integrations and publish all demo workflows
  ao-run NAME [JSON] Execute a published workflow and print its result
  reconcile-workflow Alias for ao-configure
  aap-configure      Prepare AAP credentials/license and run config-as-code
  webapp ACTION      create | nginx | verify | delete | sync
  aap ACTION         credentials | wait-project | dispatch | reset-vms | launch TEMPLATE [JSON]
  readiness TARGET   sandbox | aap

Populate .env first. An inherited KUBECONFIG takes precedence over .env.
Default bootstrap includes the complete webapp; issue-to-PR dispatch is separate.
HELP
    return
  fi
  shift $(( $# > 0 ? 1 : 0 ))
  set -Eeuo pipefail
  set +x
  umask 077
  demo_current_step=$command
  trap 'printf "ERROR: %s failed at line %s. Inspect the resource before retrying a launch.\n" "${demo_current_step:-command}" "$LINENO" >&2' ERR
  demo_load_env
  case $command in
    bootstrap) [[ $# == 0 ]] || demo_die 'bootstrap takes no arguments'; demo_bootstrap ;;
    teardown) demo_teardown "$@" ;;
    homepage-refresh) [[ $# == 0 ]] || demo_die 'homepage-refresh takes no arguments'; demo_verify_cluster; demo_homepage_configure ;;
    identity)
      [[ $# == 0 ]] || demo_die 'identity takes no arguments'
      demo_verify_cluster
      ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default -o jsonpath='{.status.domain}')
      demo_identity_prepare
      demo_identity_configure
      demo_identity_openshift
      demo_omnigent_auth
      demo_identity_forgejo
      demo_ao_reconcile
      demo_identity_aap_callback
      ;;
    preflight|--check) [[ $# == 0 ]] || demo_die 'preflight takes no arguments'; demo_preflight ;;
    sandbox-build) demo_sandbox_build ;;
    model-config)
      demo_model_config
      if [[ -n $(oc -n automation-orchestrator get automationorchestrator automation-orchestrator --ignore-not-found -o name 2>/dev/null) ]]; then
        demo_ao_reconcile
      fi ;;

    omnigent-auth) demo_verify_cluster; demo_omnigent_auth ;;
    verify-goldenpaths) demo_verify_cluster; demo_verify_goldenpaths ;;
    hydrate) demo_hydrate hydrate ;;
    forgejo-reset) demo_hydrate reset "$@" ;;
    reconcile-workflow|ao-configure) demo_verify_cluster; demo_ao_reconcile ;;
    dispatch-issue) demo_dispatch_issue "$@" ;;
    ao-run) [[ $# -ge 1 && $# -le 2 ]] || demo_die 'ao-run requires WORKFLOW [INPUT_JSON]'; demo_verify_cluster; demo_ao_reconcile run "$@" ;;
    aap-configure) demo_aap_configure ;;
    webapp) [[ $# == 1 ]] || demo_die 'webapp requires one action'; demo_webapp "$@" ;;
    aap) [[ $# -gt 0 ]] || demo_die 'aap requires an action'; demo_verify_cluster; demo_aap "$@" ;;
    readiness) [[ $# == 1 ]] || demo_die 'readiness requires sandbox or aap'; demo_verify_cluster; demo_readiness "$@" ;;
    forgejo-seed) demo_forgejo_lifecycle seed ;;
    forgejo-repos) demo_forgejo_seed_repos ;;
    forgejo-issue) demo_forgejo_issue ;;
    *) demo_die "Unknown command: $command (use --help)." ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  demo_main "$@"
fi
