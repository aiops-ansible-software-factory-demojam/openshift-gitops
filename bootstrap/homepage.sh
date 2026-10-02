#!/usr/bin/env bash
# Render navigation from actual Routes; provision dedicated read-only dashboard accounts.

demo_homepage_prepare() (
  set +x
  umask 077
  local scratch
  scratch=$(mktemp -d)
  trap 'rm -rf -- "$scratch"' EXIT
  : "${ingress_domain:?Discover the ingress domain before Homepage preparation}"
  oc -n homepage create configmap homepage-endpoints \
    --from-literal="allowed-hosts=homepage.$ingress_domain" --dry-run=client -o yaml |
    oc -n homepage apply -f - >/dev/null
  if ! oc -n homepage get configmap homepage-links >/dev/null 2>&1; then
    oc -n homepage create configmap homepage-links --from-literal='services.yaml=[]' --save-config >/dev/null
  fi
  if ! oc -n homepage get configmap homepage-environment >/dev/null 2>&1; then
    oc -n homepage create configmap homepage-environment --from-literal='environment.json={}' --save-config >/dev/null
  fi
  if ! oc -n homepage get secret homepage-dashboard-credentials >/dev/null 2>&1; then
    openssl rand -hex 32 | tr -d '\n' >"$scratch/aap-password"
    { printf 'Aa1!'; openssl rand -hex 32 | tr -d '\n'; } >"$scratch/ao-password"
    oc -n homepage create secret generic homepage-dashboard-credentials \
      --from-file="$scratch/aap-password" --from-file="$scratch/ao-password" >/dev/null
  fi
)

demo_homepage_accounts() (
  set +x
  umask 077
  local aap_scratch reader role assignments base token groups user payload
  aap_scratch=$(mktemp -d)
  trap 'rm -rf -- "$aap_scratch"' EXIT
  oc -n homepage get secret homepage-dashboard-credentials -o json |
    jq -er '.data."aap-password" | @base64d' >"$aap_scratch/aap-password"
  oc -n homepage get secret homepage-dashboard-credentials -o json |
    jq -er '.data."ao-password" | @base64d' >"$aap_scratch/ao-password"

  aap_connect
  reader=$(aap_request GET 'users/?username=homepage-reader' '' /api/gateway/v1/ | jq -r '.results[0].id // empty')
  if [[ -z $reader ]]; then
    payload=$(jq -n --rawfile password "$aap_scratch/aap-password" \
      '{username:"homepage-reader",password:($password|rtrimstr("\n")),is_superuser:false}')
    reader=$(aap_request POST users/ "$payload" /api/gateway/v1/ | jq -er .id)
  fi
  role=$(aap_request GET 'role_definitions/?name=Platform%20Auditor' '' /api/gateway/v1/ | jq -er '.results[0].id')
  assignments=$(aap_request GET "role_user_assignments/?user=$reader&role_definition=$role" '' /api/gateway/v1/)
  if [[ $(jq .count <<<"$assignments") == 0 ]]; then
    aap_request POST role_user_assignments/ "$(jq -n --argjson user "$reader" --argjson role "$role" \
      '{user:$user,role_definition:$role} ')" /api/gateway/v1/ >/dev/null
  fi

  base="https://$(oc -n automation-orchestrator get route automation-orchestrator -o jsonpath='{.spec.host}')/api/v1"
  # Curl receives private payload/config files, never credentials on its command line.
  oc -n automation-orchestrator get secret automation-orchestrator-admin-password -o json |
    jq -er '.data.password | @base64d' >"$aap_scratch/admin-password"
  jq -n --rawfile password "$aap_scratch/admin-password" \
    '{username:"admin",password:($password|rtrimstr("\n"))}' >"$aap_scratch/login.json"
  curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
    -H 'Content-Type: application/json' --data-binary "@$aap_scratch/login.json" \
    "$base/auth/login" >"$aap_scratch/login-response.json"
  token=$(jq -er .access_token "$aap_scratch/login-response.json")
  printf 'header = "Authorization: Bearer %s"\n' "$token" >"$aap_scratch/ao.conf"
  curl --fail --silent --show-error --connect-timeout 10 --max-time 30 --config "$aap_scratch/ao.conf" \
    "$base/users?username=homepage-reader" >"$aap_scratch/users.json"
  user=$(jq -r '.resources[0].id // empty' "$aap_scratch/users.json")
  if [[ -z $user ]]; then
    jq -n --rawfile password "$aap_scratch/ao-password" \
      '{username:"homepage-reader",password:($password|rtrimstr("\n")),group_names:["auditors"]}' >"$aap_scratch/user.json"
    curl --fail --silent --show-error --connect-timeout 10 --max-time 30 --config "$aap_scratch/ao.conf" \
      -H 'Content-Type: application/json' --data-binary "@$aap_scratch/user.json" "$base/users" >"$aap_scratch/user-response.json"
    user=$(jq -er .id "$aap_scratch/user-response.json")
  fi
  curl --fail --silent --show-error --connect-timeout 10 --max-time 30 --config "$aap_scratch/ao.conf" \
    "$base/groups?name=auditors" >"$aap_scratch/groups.json"
  groups=$(jq -c '[.resources[] | select(.name == "auditors") | .id]' "$aap_scratch/groups.json")
  [[ $(jq length <<<"$groups") == 1 ]] || demo_die 'AO auditors group was not found.'
  curl --fail --silent --show-error --connect-timeout 10 --max-time 30 --config "$aap_scratch/ao.conf" \
    "$base/users/$user/groups" >"$aap_scratch/memberships.json"
  if ! jq -e --arg id "$(jq -r '.[0]' <<<"$groups")" \
    '.resources | map(select(.name != "authenticated")) | length == 1 and any(.[]; .id == $id)' \
    "$aap_scratch/memberships.json" >/dev/null; then
    jq -n --argjson groups "$groups" '{group_ids:$groups}' >"$aap_scratch/memberships-request.json"
    curl --fail --silent --show-error --connect-timeout 10 --max-time 30 --config "$aap_scratch/ao.conf" \
      -X PUT -H 'Content-Type: application/json' --data-binary "@$aap_scratch/memberships-request.json" \
      "$base/users/$user/groups" >/dev/null
  fi
  echo 'Homepage AAP Platform Auditor and AO auditor accounts are ready.'
)

demo_homepage_configure() (
  set +x
  umask 077
  local scratch previous desired host issuer response deadline console forgejo aap ao source revision branch completed
  scratch=$(mktemp -d)
  trap 'rm -rf -- "$scratch"' EXIT
  ingress_domain=$(oc -n openshift-ingress-operator get ingresscontroller default -o jsonpath='{.status.domain}')
  demo_homepage_prepare
  demo_homepage_accounts
  oc get routes --all-namespaces -o json >"$scratch/routes.json"
  route_url() {
    jq -er --arg ns "$1" --arg name "$2" '.items[] | select(.metadata.namespace == $ns and .metadata.name == $name) |
      "https://" + (.status.ingress[0].host // .spec.host)' "$scratch/routes.json"
  }
  console=$(route_url openshift-console console)
  forgejo=$(route_url forgejo forgejo)
  aap=$(route_url ansible-automation-platform aap)
  ao=$(route_url automation-orchestrator automation-orchestrator)
  oc -n openshift-gitops get application cluster -o json >"$scratch/cluster.json"
  source=$(jq -r '.spec.source.repoURL | sub("\\.git$"; "")' "$scratch/cluster.json")
  revision=$(jq -r '.status.sync.revision // "Unknown"' "$scratch/cluster.json")
  branch=$(jq -r .spec.source.targetRevision "$scratch/cluster.json")
  completed=$(oc -n homepage get configmap homepage-environment -o json | jq -r '.data."environment.json" | fromjson | .bootstrapCompleted // "Not recorded"')
  jq -n --arg server "$DEMO_CLUSTER_SERVER" --arg domain "$ingress_domain" --arg revision "$revision" \
    --arg branch "$branch" --arg completed "$completed" --arg aap "$aap" --arg ao "$ao" \
    '{cluster:($server|sub("^https://api\\."; "")|split(".")[0]),ingress:$domain,revision:$revision,branch:$branch,
      bootstrapCompleted:$completed,aapUrl:$aap,aoUrl:$ao}' >"$scratch/environment.json"

  # Discover repositories visible to the demo agent, including golden-path output.
  oc -n omnigent-sandboxes get secret omnigent-model -o json |
    jq -er '.data.FORGEJO_TOKEN | @base64d' >"$scratch/forgejo-token"
  printf 'header = "Authorization: token %s"\n' "$(<"$scratch/forgejo-token")" >"$scratch/forgejo.conf"
  local page=1 count
  printf '[]\n' >"$scratch/repositories.json"
  while true; do
    curl --fail --silent --show-error --connect-timeout 10 --max-time 30 --config "$scratch/forgejo.conf" \
      "$forgejo/api/v1/user/repos?limit=50&page=$page" >"$scratch/repo-page.json"
    count=$(jq length "$scratch/repo-page.json")
    jq -s '.[0] + .[1]' "$scratch/repositories.json" "$scratch/repo-page.json" >"$scratch/repos-next.json"
    mv "$scratch/repos-next.json" "$scratch/repositories.json"
    (( count == 50 )) || break
    page=$((page + 1))
  done
  oc -n openshift-gitops get applications -o json | jq '[.items[].spec.source.repoURL // empty] | unique |
    map({name:(split("/")[-1]|sub("\\.git$"; "")),href:sub("\\.git$"; ""),description:"GitOps source repository"})' >"$scratch/gitops-repos.json"
  jq -n --arg forgejo "$forgejo" --slurpfile repos "$scratch/repositories.json" --slurpfile gitops "$scratch/gitops-repos.json" \
    '$gitops[0] + ($repos[0] | map({name:.full_name,href:($forgejo + "/" + .full_name),description:(.description // "Demo source repository")})) |
     unique_by(.href)' >"$scratch/repo-links.json"

  jq '
    def known:
      {
        "rhdh": {name:"Developer Hub",group:"Demo applications",icon:"backstage",description:"Software catalog and golden paths"},
        "forgejo": {name:"Forgejo",group:"Demo applications",icon:"forgejo",description:"Demo source, issues and pull requests"},
        "omnigent": {name:"Omnigent",group:"Demo applications",icon:"mdi-robot",description:"Agent sessions and activity"},
        "automation-orchestrator": {name:"Automation Orchestrator",group:"Automation",icon:"mdi-sitemap",description:"Issue-to-PR workflow"},
        "ansible-automation-platform": {name:"Ansible Automation Platform",group:"Automation",icon:"ansible",description:"Automation jobs and configuration"},
        "webapp-vms": {name:"Webapp",group:"Demo applications",icon:"nginx",description:"RHEL web application"},
        "openshift-gitops": {name:"Argo CD",group:"Platform",icon:"argo-cd",description:"GitOps application health"},
        "openshift-console": {name:"OpenShift Console",group:"Platform",icon:"openshift",description:"Cluster resources and workloads"},
        "demojam-keycloak": {name:"Keycloak Admin",group:"Platform",icon:"keycloak",description:"Manage the demo realm",suffix:"/admin/demo/console/"}
      };
    [.items[] | .metadata.namespace as $ns | known[$ns] as $info |
      select($info != null) | (.status.ingress[0].host // .spec.host // "") as $host |
      select($ns != "openshift-console" or .metadata.name == "console") |
      select($host != "") |
      $info + {namespace:$ns, route:.metadata.name,href:("https://" + $host + ($info.suffix // ""))}] |
    sort_by(.group,.name,.route) |
    group_by(.namespace) | map(if length == 1 then . else map(.name += (" (" + .route + ")")) end) | flatten |
    . + ([.[] | select(.namespace == "openshift-console" and .route == "console") |
      {name:"Monitoring",group:"Platform",icon:"prometheus",description:"Metrics and alerts",href:(.href + "/monitoring") }]) |
    sort_by(.group,.name) | group_by(.group) |
    map({(.[0].group):map({(.name):{href:.href,icon:.icon,description:.description}})})
  ' "$scratch/routes.json" >"$scratch/routes-services.json"
  # shellcheck disable=SC2154 # The entry point supplies demo_repo_root.
  jq -n --arg console "$console" --arg forgejo "$forgejo" --arg aap "$aap" --arg ao "$ao" \
    --arg source "$source" --arg branch "$branch" --arg rhdh "$(route_url rhdh backstage-rhdh-developer-hub)" \
    --arg omnigent "$(route_url omnigent omnigent)" --slurpfile routes "$scratch/routes-services.json" \
    --slurpfile repos "$scratch/repo-links.json" -f "$demo_repo_root/bootstrap/homepage-services.jq" |
    yq -y . >"$scratch/services.yaml"
  previous=$(oc -n homepage get configmap homepage-links -o json | jq -r '.data."services.yaml"')
  desired=$(cat "$scratch/services.yaml")
  oc -n homepage create configmap homepage-environment --from-file="$scratch/environment.json" \
    --dry-run=client -o yaml | oc -n homepage apply -f - >/dev/null
  oc -n homepage create configmap homepage-links --from-file="$scratch/services.yaml" \
    --dry-run=client -o yaml | oc -n homepage apply -f - >/dev/null
  if [[ $previous != "$desired" ]]; then
    # A rollout also removes Homepage caches after projected config updates.
    oc -n homepage rollout restart deployment/homepage
  fi
  oc -n homepage rollout status deployment/homepage --timeout=10m
  host=$(oc -n homepage get route homepage -o jsonpath='{.status.ingress[0].host}')
  issuer=$(oc -n homepage get secret demo-oidc -o json | jq -r '.data.issuer | @base64d')
  deadline=$((SECONDS + 120))
  while true; do
    response=$(curl --silent --show-error --connect-timeout 5 --max-time 15 \
      -o /dev/null -w '%{http_code} %{redirect_url}' "https://$host") || response=
    if [[ ${response%% *} == 302 && ${response#* } == "$issuer/protocol/openid-connect/auth"* ]]; then
      break
    fi
    (( SECONDS < deadline )) || demo_die 'Homepage did not redirect an anonymous browser to the demo Keycloak realm.'
    sleep 5
  done
  deadline=$((SECONDS + 1200))
  while ! oc -n homepage exec deployment/homepage -c dashboard -- node -e '
    fetch("http://127.0.0.1:3001/status").then(r=>r.json()).then(s=>{
      const names=["gitops","cluster","monitoring","aap","eda","orchestrator"];
      const failed=names.filter(n=>!s[n]?.available);
      if(failed.length){console.log("Waiting for dashboard sources: "+failed.join(", "));process.exit(1);}
    }).catch(()=>process.exit(1));'; do
    (( SECONDS < deadline )) || demo_die 'Homepage data sources did not become ready; inspect the dashboard container logs.'
    sleep 10
  done
  if [[ ${1:-refresh} == bootstrap ]]; then
    jq --arg completed "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" '.bootstrapCompleted=$completed' \
      "$scratch/environment.json" >"$scratch/environment-next.json"
    mv "$scratch/environment-next.json" "$scratch/environment.json"
    oc -n homepage create configmap homepage-environment --from-file="$scratch/environment.json" \
      --dry-run=client -o yaml | oc -n homepage apply -f - >/dev/null
  fi
  printf 'Homepage navigation, live widgets and OIDC redirect verified: https://%s\n' "$host"
)
