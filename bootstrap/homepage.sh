#!/usr/bin/env bash
# Render public navigation from the cluster's actual Routes. No API tokens enter Homepage.

demo_homepage_prepare() {
  : "${ingress_domain:?Discover the ingress domain before Homepage preparation}"
  oc -n homepage create configmap homepage-endpoints \
    --from-literal="allowed-hosts=homepage.$ingress_domain" --dry-run=client -o yaml |
    oc -n homepage apply -f - >/dev/null
  if ! oc -n homepage get configmap homepage-links >/dev/null 2>&1; then
    oc -n homepage create configmap homepage-links --from-literal='services.yaml=[]' --save-config >/dev/null
  fi
}

demo_homepage_configure() (
  local scratch previous desired host issuer response deadline
  scratch=$(mktemp -d)
  trap 'rm -rf -- "$scratch"' EXIT
  oc get routes --all-namespaces -o json | jq '
    def known:
      {
        "rhdh": {name:"Developer Hub",group:"Demo applications",icon:"backstage",description:"Software catalog and golden paths"},
        "forgejo": {name:"Forgejo",group:"Demo applications",icon:"forgejo",description:"Demo source, issues and pull requests"},
        "omnigent": {name:"Omnigent",group:"Demo applications",icon:"mdi-robot",description:"Agent sessions and activity"},
        "automation-orchestrator": {name:"Automation Orchestrator",group:"Demo applications",icon:"mdi-sitemap",description:"Issue-to-PR workflow"},
        "ansible-automation-platform": {name:"Ansible Automation Platform",group:"Demo applications",icon:"ansible",description:"Automation jobs and configuration"},
        "webapp-vms": {name:"Webapp",group:"Demo applications",icon:"nginx",description:"RHEL web application"},
        "openshift-gitops": {name:"Argo CD",group:"Platform",icon:"argo-cd",description:"GitOps application health"},
        "openshift-console": {name:"OpenShift Console",group:"Platform",icon:"openshift",description:"Cluster resources and workloads"},
        "demojam-keycloak": {name:"My Keycloak account",group:"Identity",icon:"keycloak",description:"Demo account and password",suffix:"/realms/demo/account/"}
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
    . + ([.[] | select(.namespace == "demojam-keycloak") |
      {name:"Keycloak Admin",group:"Identity",icon:"keycloak",description:"Manage the demo realm",href:(.href | sub("/realms/demo/account/$"; "/admin/demo/console/"))}]) |
    sort_by(.group,.name) | group_by(.group) |
    map({(.[0].group):map({(.name):{href:.href,icon:.icon,description:.description}})})
  ' | yq -y . >"$scratch/services.yaml"
  previous=$(oc -n homepage get configmap homepage-links -o json | jq -r '.data."services.yaml"')
  desired=$(cat "$scratch/services.yaml")
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
  printf 'Homepage navigation and OIDC redirect verified: https://%s\n' "$host"
)
