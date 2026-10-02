#!/usr/bin/env bash
# Demo identity provisioning. Sourcing this file performs no cluster operations.

demo_identity_users_file() {
  local file=${DEMO_USERS_FILE:-$demo_repo_root/bootstrap/users.example.json}
  [[ $file == /* ]] || file="$demo_repo_root/$file"
  printf '%s\n' "$file"
}

demo_identity_validate_users() {
  jq -e '
    type == "object" and (.users | type == "array" and length > 0) and
    ([.users[].username] | length == (unique | length)) and
    ([.users[].email | ascii_downcase] | length == (unique | length)) and
    all(.users[];
      (.username | type == "string" and test("^[a-z][a-z0-9_-]{0,39}$")) and
      (.username != "demo-admin" and .username != "demo-agent" and .username != "demo-owner" and .username != "demo-reviewer" and .username != "bootstrap-admin" and .username != "automation-orchestrator") and
      ((.email | ascii_downcase) != "automation-orchestrator@example.test") and
      (.email | type == "string" and test("^[^[:space:]@]+@[^[:space:]@]+$")) and
      ((.firstName // "") | type == "string") and
      ((.lastName // "") | type == "string") and
      (if has("enabled") then (.enabled | type == "boolean") else true end) and
      ((.groups // ["demo-users"]) | type == "array" and length > 0 and
        all(.[]; . == "demo-users" or . == "demo-admins")) and
      (has("password") | not)
    )' "$1" >/dev/null 2>&1
}

demo_identity_catalog() {
  jq -r '.users[] | select(.enabled != false) | {
    apiVersion:"backstage.io/v1alpha1",kind:"User",
    metadata:{name:.username},
    spec:{profile:{displayName:([.firstName // "",.lastName // ""] | join(" ") | ltrimstr(" ") | rtrimstr(" ")),email:.email},memberOf:[]}
  } | "---\n" + (tojson)' "$1" | yq -y .
}

demo_identity_legacy_detached() {
  local crd application
  crd=$(oc get crd applications.argoproj.io --ignore-not-found -o name) || return
  [[ -n $crd ]] || return 0
  application=$(oc -n openshift-gitops get application rhbk --ignore-not-found -o json) || return
  [[ -n $application ]] || return 0
  jq -e '.spec.source.path != "cluster/rhbk"' <<<"$application" >/dev/null
}

demo_identity_prepare() (
  set +x
  umask 077
  local scratch users_file namespace namespace_file client key
  local -a args
  : "${ingress_domain:?Discover the ingress domain before identity preparation}"
  scratch=$(mktemp -d)
  trap 'rm -rf -- "$scratch"' EXIT
  users_file=$(demo_identity_users_file)
  demo_identity_validate_users "$users_file" || demo_die 'Invalid DEMO_USERS_FILE; use bootstrap/users.example.json (unique names/emails, demo-users/demo-admins groups, no passwords).'

  for namespace in demojam-keycloak forgejo rhdh automation-orchestrator omnigent webapp-vms homepage; do
    namespace_file="$demo_repo_root/cluster/$namespace/$namespace-namespace.yaml"
    [[ $namespace != demojam-keycloak ]] || namespace_file="$demo_repo_root/cluster/demojam-keycloak/demojam-keycloak-namespace.yaml"
    oc apply --server-side --field-manager=demo-bootstrap -f "$namespace_file" >/dev/null
  done
  if ! oc -n demojam-keycloak get secret identity-credentials >/dev/null 2>&1; then
    for key in admin-password backstage-token argocd-client-secret rhdh-client-secret rhdh-session-secret \
      forgejo-client-secret aap-client-secret orchestrator-client-secret omnigent-client-secret openshift-client-secret webapp-client-secret homepage-client-secret omnigent-cookie-secret; do
      openssl rand -hex 32 | tr -d '\n' >"$scratch/$key"
    done
    openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n' >"$scratch/webapp-cookie-secret"
    openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n' >"$scratch/homepage-cookie-secret"
    oc -n demojam-keycloak create secret generic identity-credentials --from-file="$scratch" >/dev/null
  fi
  # New consumers can be added to an installed stack without rotating keys
  # already in use. Only keys introduced by these additions are filled here.
  oc -n demojam-keycloak get secret identity-credentials -o json >"$scratch/root.json"
  for key in rhdh-session-secret homepage-client-secret homepage-cookie-secret; do
    if ! jq -e --arg key "$key" '.data[$key] | type == "string" and length > 0' "$scratch/root.json" >/dev/null; then
      if [[ $key == homepage-cookie-secret ]]; then
        openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n' >"$scratch/new-key"
      else
        openssl rand -hex 32 | tr -d '\n' >"$scratch/new-key"
      fi
      jq -n --arg key "$key" --rawfile value "$scratch/new-key" '{data:{($key):($value | @base64)}}' >"$scratch/key-patch.json"
      oc -n demojam-keycloak patch secret identity-credentials --type=merge --patch-file="$scratch/key-patch.json" >/dev/null
    fi
  done
  # OAuth2 Proxy decodes URL-safe base64. Canonicalize older standard-base64
  # values without changing their underlying random bytes or client secrets.
  oc -n demojam-keycloak get secret identity-credentials -o json |
    jq '{data:(.data | with_entries(select(.key == "webapp-cookie-secret" or .key == "homepage-cookie-secret") |
      .value |= (@base64d | gsub("\\+";"-") | gsub("/";"_") | @base64)))}' >"$scratch/cookie-patch.json"
  oc -n demojam-keycloak patch secret identity-credentials --type=merge --patch-file="$scratch/cookie-patch.json" >/dev/null
  oc -n demojam-keycloak get secret identity-credentials -o json |
    jq '.data | with_entries(.value |= @base64d)' >"$scratch/credentials.json"
  jq -e '. as $credentials | all(["admin-password","backstage-token","argocd-client-secret","rhdh-client-secret","rhdh-session-secret",
    "forgejo-client-secret","aap-client-secret","orchestrator-client-secret","omnigent-client-secret","openshift-client-secret","webapp-client-secret","homepage-client-secret","homepage-cookie-secret","omnigent-cookie-secret","webapp-cookie-secret"][];
    $credentials[.] | type == "string" and length > 0)' "$scratch/credentials.json" >/dev/null ||
    demo_die 'The demojam-keycloak identity-credentials Secret is incomplete; restore its original keys before retrying.'
  # RHDH needs named environment keys below; AAP receives its secret through CaC.
  for client in argocd forgejo orchestrator omnigent webapp homepage; do
    namespace=$client
    case $client in
      argocd) namespace=openshift-gitops ;;
      orchestrator) namespace=automation-orchestrator ;;
      webapp) namespace=webapp-vms ;;
    esac
    jq -rj --arg key "$client-client-secret" '.[$key]' "$scratch/credentials.json" >"$scratch/client-secret"
    printf '%s' "$client" >"$scratch/client-id"
    printf 'https://demojam-keycloak.%s/realms/demo' "$ingress_domain" >"$scratch/issuer"
    args=(--from-file=client-id="$scratch/client-id" --from-file=client-secret="$scratch/client-secret" --from-file=issuer="$scratch/issuer")
    if [[ $client == omnigent || $client == webapp || $client == homepage ]]; then
      jq -rj --arg key "$client-cookie-secret" '.[$key]' "$scratch/credentials.json" >"$scratch/cookie-secret"
      printf 'https://%s.%s/%s' "$client" "$ingress_domain" "$([[ $client == omnigent ]] && printf auth/callback || printf oauth2/callback)" >"$scratch/redirect-url"
      args+=(--from-file=cookie-secret="$scratch/cookie-secret" --from-file=redirect-url="$scratch/redirect-url")
    fi
    oc -n "$namespace" create secret generic demo-oidc "${args[@]}" --dry-run=client -o json |
      jq '.metadata.labels = {"app.kubernetes.io/part-of":"argocd"}' |
      oc -n "$namespace" apply -f - >/dev/null
  done
  jq -rj '."openshift-client-secret"' "$scratch/credentials.json" >"$scratch/clientSecret"
  oc -n openshift-config create secret generic demojam-keycloak-oidc \
    --from-file=clientSecret="$scratch/clientSecret" --dry-run=client -o yaml |
    oc -n openshift-config apply -f - >/dev/null
  jq -r '.users[] | select(.enabled != false) | select((.groups // ["demo-users"]) | index("demo-admins")) | .email' \
    "$users_file" >"$scratch/admins"
  oc -n omnigent create configmap omnigent-identity --from-file=admins="$scratch/admins" \
    --dry-run=client -o yaml | oc -n omnigent apply -f - >/dev/null
  jq -rj '."backstage-token"' "$scratch/credentials.json" >"$scratch/BACKSTAGE_TOKEN"
  jq -rj '."rhdh-client-secret"' "$scratch/credentials.json" >"$scratch/DEMO_OIDC_CLIENT_SECRET"
  jq -rj '."rhdh-session-secret"' "$scratch/credentials.json" >"$scratch/DEMO_OIDC_SESSION_SECRET"
  printf rhdh >"$scratch/DEMO_OIDC_CLIENT_ID"
  cp "$scratch/issuer" "$scratch/DEMO_OIDC_ISSUER"
  oc -n rhdh create secret generic rhdh-oidc-env \
    --from-file=DEMO_OIDC_SESSION_SECRET="$scratch/DEMO_OIDC_SESSION_SECRET" \
    --from-file=DEMO_OIDC_CLIENT_SECRET="$scratch/DEMO_OIDC_CLIENT_SECRET" \
    --from-file=DEMO_OIDC_CLIENT_ID="$scratch/DEMO_OIDC_CLIENT_ID" \
    --from-file=DEMO_OIDC_ISSUER="$scratch/DEMO_OIDC_ISSUER" --dry-run=client -o yaml |
    oc -n rhdh apply -f - >/dev/null
  for namespace in rhdh automation-orchestrator; do
    oc -n "$namespace" create secret generic backstage-machine-auth \
      --from-file=BACKSTAGE_TOKEN="$scratch/BACKSTAGE_TOKEN" --dry-run=client -o yaml |
      oc -n "$namespace" apply -f - >/dev/null
  done
  oc -n demojam-keycloak create configmap demojam-keycloak-endpoints \
    --from-literal="keycloak-url=https://demojam-keycloak.$ingress_domain" --dry-run=client -o yaml |
    oc -n demojam-keycloak apply -f - >/dev/null
  demo_identity_catalog "$users_file" >"$scratch/demo-users.yaml"
  oc -n rhdh create configmap demo-users-catalog --from-file="$scratch/demo-users.yaml" \
    --dry-run=client -o yaml | oc -n rhdh apply -f - >/dev/null
  # OpenShift does not synchronize OIDC group claims into its Group objects.
  # This group is owned by bootstrap; GitOps owns its cluster-admin binding.
  jq '{apiVersion:"user.openshift.io/v1",kind:"Group",
    metadata:{name:"demojam-admins",labels:{"app.kubernetes.io/part-of":"demojam-keycloak"}},
    users:[.users[] | select(.enabled != false) |
      select((.groups // ["demo-users"]) | index("demo-admins")) | .username]}' \
    "$users_file" | oc apply -f - >/dev/null
)

demo_identity_clients() {
  # Endpoints are actual application Routes, not workshop-specific hostnames.
  jq -n --argjson endpoints "$1" --slurpfile credentials "$2" '
    $endpoints | to_entries | map({
      clientId:.key,protocol:"openid-connect",enabled:true,publicClient:false,
      clientAuthenticatorType:"client-secret",secret:$credentials[0][(.key + "-client-secret")],
      standardFlowEnabled:true,directAccessGrantsEnabled:false,serviceAccountsEnabled:false,
      redirectUris:.value,webOrigins:[],
      attributes:{"post.logout.redirect.uris":"+"},
      defaultClientScopes:["profile","email","roles"],
      protocolMappers:[{name:"groups",protocol:"openid-connect",
        protocolMapper:"oidc-group-membership-mapper",config:{
          "claim.name":"groups","full.path":"false","id.token.claim":"true",
          "access.token.claim":"true","userinfo.token.claim":"true"}}]
    })'
}

demo_identity_connect() {
  identity_base="https://$(oc -n demojam-keycloak get route keycloak -o jsonpath='{.status.ingress[0].host}')"
  oc -n demojam-keycloak get secret identity-credentials -o json |
    jq '.data | with_entries(.value |= @base64d)' >"$identity_scratch/credentials.json"
  jq -rj '."admin-password"' "$identity_scratch/credentials.json" >"$identity_scratch/password"
  curl -fsS --connect-timeout 10 --max-time 30 -X POST \
    --data-urlencode client_id=admin-cli --data-urlencode grant_type=password \
    --data-urlencode username=bootstrap-admin --data-urlencode "password@$identity_scratch/password" \
    "$identity_base/realms/master/protocol/openid-connect/token" >"$identity_scratch/token.json" ||
    demo_die 'Could not authenticate to the demo Keycloak administration API.'
  jq -er '.access_token' "$identity_scratch/token.json" >"$identity_scratch/token"
  printf '%s' "$((SECONDS + $(jq -er '.expires_in' "$identity_scratch/token.json") - 10))" >"$identity_scratch/token-deadline"
  printf 'header = "Authorization: Bearer %s"\n' "$(<"$identity_scratch/token")" >"$identity_scratch/curl.conf"
}

demo_identity_request() {
  local method=$1 path=$2 payload=${3:-} code
  if (( SECONDS >= $(<"$identity_scratch/token-deadline") )); then
    demo_identity_connect
  fi
  printf '%s' "$payload" >"$identity_scratch/payload.json"
  local -a args=()
  [[ -z $payload ]] || args=(--data-binary "@$identity_scratch/payload.json")
  code=$(curl --silent --show-error --connect-timeout 10 --max-time 60 \
    --config "$identity_scratch/curl.conf" -H 'Content-Type: application/json' \
    -X "$method" "${args[@]}" -o "$identity_scratch/response.json" -w '%{http_code}' \
    "$identity_base/admin$path") || demo_die 'Demo Keycloak API transport failed.'
  [[ $code == 2* ]] || demo_die "Demo Keycloak API $method failed (HTTP $code); response omitted to protect credentials."
  if [[ -s $identity_scratch/response.json ]]; then
    cat "$identity_scratch/response.json"
  else
    printf '{}\n'
  fi
}

demo_identity_upsert_client() {
  local body=$1 client id
  client=$(jq -r .clientId <<<"$body")
  id=$(demo_identity_request GET "/realms/demo/clients?clientId=$client" | jq -r '.[0].id // empty')
  if [[ -n $id ]]; then
    demo_identity_request PUT "/realms/demo/clients/$id" "$body" >/dev/null
  else
    demo_identity_request POST /realms/demo/clients "$body" >/dev/null
  fi
}

demo_identity_configure() (
  set +x
  umask 077
  local identity_scratch identity_base users_file name user id group group_id password body endpoints argocd_host ao_host oauth_host management_client
  identity_scratch=$(mktemp -d)
  trap 'rm -rf -- "$identity_scratch"' EXIT
  users_file=$(demo_identity_users_file)
  demo_identity_validate_users "$users_file" || demo_die 'Invalid DEMO_USERS_FILE.'
  deadline=$((SECONDS + 900))
  until oc -n demojam-keycloak get cluster.postgresql.cnpg.io/keycloak-pg >/dev/null 2>&1 &&
    oc -n demojam-keycloak get deployment/keycloak >/dev/null 2>&1; do
    (( SECONDS < deadline )) || demo_die 'Demo identity resources were not created by GitOps.'
    sleep 5
  done
  oc -n demojam-keycloak wait --for=condition=Ready cluster.postgresql.cnpg.io/keycloak-pg --timeout=15m
  oc -n demojam-keycloak rollout status deployment/keycloak --timeout=15m
  # Deployment readiness does not prove the public Route is accepting requests.
  identity_base="https://$(oc -n demojam-keycloak get route keycloak -o jsonpath='{.status.ingress[0].host}')"
  deadline=$((SECONDS + 300))
  until curl -fsS --connect-timeout 5 --max-time 10 "$identity_base/realms/master/.well-known/openid-configuration" >/dev/null 2>&1; do
    (( SECONDS < deadline )) || demo_die 'Demo Keycloak Route did not become ready.'
    sleep 5
  done
  demo_identity_connect
  if ! demo_identity_request GET /realms | jq -e 'any(.[]; .realm == "demo")' >/dev/null; then
    demo_identity_request POST /realms '{"realm":"demo","enabled":true,"registrationAllowed":false}' >/dev/null
  fi
  demo_identity_request PUT /realms/demo '{"enabled":true,"registrationAllowed":false,"resetPasswordAllowed":false,"rememberMe":true}' >/dev/null
  groups=$(demo_identity_request GET /realms/demo/groups)
  for group in demo-users demo-admins; do
    if ! jq -e --arg group "$group" 'any(.[]; .name == $group)' <<<"$groups" >/dev/null; then
      demo_identity_request POST /realms/demo/groups "$(jq -n --arg name "$group" '{name:$name}')" >/dev/null
    fi
  done
  groups=$(demo_identity_request GET /realms/demo/groups)
  management_client=$(demo_identity_request GET '/realms/demo/clients?clientId=realm-management' | jq -er '.[0].id')
  group_id=$(jq -er '.[] | select(.name == "demo-admins") | .id' <<<"$groups")
  body=$(demo_identity_request GET "/realms/demo/clients/$management_client/roles/realm-admin" | jq '[.]')
  demo_identity_request POST "/realms/demo/groups/$group_id/role-mappings/clients/$management_client" "$body" >/dev/null
  if oc -n demojam-keycloak get secret demo-user-passwords >/dev/null 2>&1; then
    oc -n demojam-keycloak get secret demo-user-passwords -o go-template='{{index .data "passwords.json" | base64decode}}' >"$identity_scratch/passwords.json"
  else
    printf '{}\n' >"$identity_scratch/passwords.json"
  fi
  while IFS= read -r user; do
    name=$(jq -r .username <<<"$user")
    id=$(demo_identity_request GET "/realms/demo/users?username=$name&exact=true" | jq -r '.[0].id // empty')
    body=$(jq '{username,email,firstName:(.firstName // ""),lastName:(.lastName // ""),enabled:(if has("enabled") then .enabled else true end),emailVerified:true}' <<<"$user")
    if [[ -z $id ]]; then
      password=$(jq -r --arg name "$name" '.[$name] // empty' "$identity_scratch/passwords.json")
      [[ -n $password ]] || password=${DEMO_USER_PASSWORD:-changeme}
      jq --arg name "$name" --arg password "$password" '.[$name] = $password' "$identity_scratch/passwords.json" >"$identity_scratch/passwords.tmp"
      mv "$identity_scratch/passwords.tmp" "$identity_scratch/passwords.json"
      body=$(jq --arg password "$password" '.credentials=[{type:"password",value:$password,temporary:false}]' <<<"$body")
      # Persist before the API write: an interrupted response may still create
      # the user, and retrying must retain that account's initial password.
      oc -n demojam-keycloak create secret generic demo-user-passwords --from-file="$identity_scratch/passwords.json" \
        --dry-run=client -o yaml | oc -n demojam-keycloak apply -f - >/dev/null
      demo_identity_request POST /realms/demo/users "$body" >/dev/null
      id=$(demo_identity_request GET "/realms/demo/users?username=$name&exact=true" | jq -er '.[0].id')
    else
      demo_identity_request PUT "/realms/demo/users/$id" "$body" >/dev/null
    fi
    for group in demo-users demo-admins; do
      group_id=$(jq -er --arg group "$group" '.[] | select(.name == $group) | .id' <<<"$groups")
      if jq -e --arg group "$group" '(.groups // ["demo-users"]) | index($group) != null' <<<"$user" >/dev/null; then
        demo_identity_request PUT "/realms/demo/users/$id/groups/$group_id" >/dev/null
      else
        demo_identity_request DELETE "/realms/demo/users/$id/groups/$group_id" >/dev/null
      fi
    done
  done < <(jq -c '.users[]' "$users_file")
  argocd_host=$(oc -n openshift-gitops get route demojam-gitops-server -o jsonpath='{.status.ingress[0].host}')
  ao_host=$(oc -n automation-orchestrator get route automation-orchestrator -o jsonpath='{.status.ingress[0].host}' 2>/dev/null) || ao_host=
  oauth_host=$(oc -n openshift-authentication get route oauth-openshift -o jsonpath='{.status.ingress[0].host}')
  [[ -n $oauth_host ]] || demo_die 'OpenShift OAuth Route has no assigned host.'
  endpoints=$(jq -n --arg oauth "$oauth_host" --arg domain "$ingress_domain" --arg argocd "$argocd_host" --arg ao "$ao_host" '{
    argocd:[("https://" + $argocd + "/auth/callback")],
    rhdh:[("https://rhdh." + $domain + "/api/auth/oidc/handler/frame")],
    forgejo:[("https://forgejo." + $domain + "/user/oauth2/demojam-keycloak/callback")],
    omnigent:[("https://omnigent." + $domain + "/auth/callback")],
    webapp:[("https://webapp." + $domain + "/oauth2/callback")],
    homepage:[("https://homepage." + $domain + "/oauth2/callback")],
    openshift:[("https://" + $oauth + "/oauth2callback/demojam-keycloak")]
  } + (if $ao == "" then {} else {orchestrator:[("https://" + $ao + "/api/v1/auth/oidc/callback")]} end)')
  while IFS= read -r body; do
    demo_identity_upsert_client "$body"
  done < <(demo_identity_clients "$endpoints" "$identity_scratch/credentials.json" | jq -c '.[]')
  curl -fsS --max-time 30 "$identity_base/realms/demo/.well-known/openid-configuration" |
    jq -e --arg issuer "$identity_base/realms/demo" '.issuer == $issuer' >/dev/null
  echo 'Demo realm, users, group memberships, and OIDC clients are configured.'
)

demo_identity_forgejo() {
  # shellcheck disable=SC2016
  oc -n forgejo exec deploy/forgejo -- sh -eu -c '
    config=/var/lib/gitea/custom/conf/app.ini
    id=$(forgejo --config "$config" admin auth list | awk '\''$2 == "demojam-keycloak" {print $1}'\'')
    set -- --name demojam-keycloak --provider openidConnect --key forgejo \
      --secret "$(cat /etc/demo-oidc/client-secret)" \
      --auto-discover-url "$(cat /etc/demo-oidc/issuer)/.well-known/openid-configuration" \
      --scopes openid --scopes profile --scopes email \
      --group-claim-name groups --admin-group demo-admins
    if test -n "$id"; then
      forgejo --config "$config" admin auth update-oauth --id "$id" "$@"
    else
      forgejo --config "$config" admin auth add-oauth "$@"
    fi
  ' >/dev/null
}

demo_identity_aap_callback() (
  set +x
  umask 077
  local aap_scratch identity_scratch identity_base callback endpoints
  aap_scratch=$(mktemp -d)
  identity_scratch=$(mktemp -d)
  trap 'rm -rf -- "$aap_scratch" "$identity_scratch"' EXIT
  aap_connect
  : "${aap_host:?AAP connection must resolve its public URL}"
  callback=$(aap_request GET 'authenticators/?name=Demojam%20Keycloak' '' /api/gateway/v1/ |
    jq -er '.results[0].configuration.CALLBACK_URL')
  [[ $callback == "$aap_host/api/gateway/social/complete/"* &&
    ${callback#"$aap_host"} =~ ^/api/gateway/social/complete/[a-zA-Z0-9_-]+/$ ]] ||
    demo_die 'AAP returned an unexpected OIDC callback URL.'
  demo_identity_connect
  endpoints=$(jq -n --arg callback "$callback" '{aap:[$callback]}')
  demo_identity_upsert_client "$(demo_identity_clients "$endpoints" "$identity_scratch/credentials.json" | jq '.[0]')"
  echo 'AAP OIDC client uses the exact callback generated by the gateway.'
)

demo_identity_ao_payload() {
  jq -n --arg issuer "$1" --arg secret "$2" --arg callback "$3" --arg users "$4" --arg admins "$5" '{
    name:"Demojam Keycloak",configuration:{provider_type:"oidc",idp_type:"custom",auto_discovery:true,
      issuer_url:$issuer,client_id:"orchestrator",client_secret:$secret,redirect_uri:$callback,
      scopes:"openid profile email",group_jmespath_expression:"groups[*]",
      allow_all_authenticated:false,disable_tls_verify:false,enable_rp_initiated_logout:false,
      group_mapping_entries:[{idp_group_value:"demo-users",mapped_group_id:$users},
        {idp_group_value:"demo-admins",mapped_group_id:$admins}]}
  }'
}

demo_identity_openshift() (
  set +x
  umask 077
  local scratch oauth_host redirect_uri location deadline
  scratch=$(mktemp -d)
  trap 'rm -rf -- "$scratch"' EXIT
  # OAuth is a cluster singleton: preserve every provider other than ours.
  oc get oauth cluster -o json >"$scratch/oauth.json"
  yq -c . "$demo_repo_root/bootstrap/config/demojam-keycloak-identity-provider.yaml" |
    jq --arg issuer "https://demojam-keycloak.$ingress_domain/realms/demo" \
      '.openID.issuer=$issuer' >"$scratch/provider.json"
  jq --slurpfile provider "$scratch/provider.json" \
    '{spec:{identityProviders:((.spec.identityProviders // [] | map(select(.name != $provider[0].name))) + $provider)}}' \
    "$scratch/oauth.json" >"$scratch/patch.json"
  oc patch oauth cluster --type=merge --patch-file "$scratch/patch.json" >/dev/null
  oauth_host=$(oc -n openshift-authentication get route oauth-openshift -o jsonpath='{.status.ingress[0].host}')
  redirect_uri=$(oc get oauthclient openshift-browser-client -o jsonpath='{.redirectURIs[0]}')
  [[ -n $oauth_host && -n $redirect_uri ]] || demo_die 'OpenShift browser OAuth client is unavailable.'
  # An immediate operator wait could observe the previous healthy generation.
  # First prove that the public endpoint has loaded our provider.
  deadline=$((SECONDS + 600))
  while :; do
    location=$(curl -fsS --connect-timeout 5 --max-time 15 --get \
      --data-urlencode client_id=openshift-browser-client --data-urlencode response_type=code \
      --data-urlencode idp=demojam-keycloak --data-urlencode "redirect_uri=$redirect_uri" \
      --output /dev/null --write-out '%{redirect_url}' "https://$oauth_host/oauth/authorize" 2>/dev/null) || location=
    [[ $location == "https://demojam-keycloak.$ingress_domain/realms/demo/protocol/openid-connect/auth?"* ]] && break
    (( SECONDS < deadline )) || demo_die 'OpenShift login did not redirect to demojam-keycloak.'
    sleep 5
  done
  oc wait clusteroperator/authentication --for=condition=Available=True --timeout=10m
  oc wait clusteroperator/authentication --for=condition=Progressing=False --timeout=10m
  oc wait clusteroperator/authentication --for=condition=Degraded=False --timeout=10m
  echo 'OpenShift login is configured with demojam-keycloak; existing providers are retained.'
)

# Curl credentials stay in a caller-owned private directory. Both workflow
# reconciliation and reset use the same native machine token endpoint.
demo_omnigent_connect() {
  local scratch=$1 base=$2 client_id client_secret
  client_id=$(oc -n automation-orchestrator get secret omnigent-machine-client-credential \
    -o go-template='{{index .data "username" | base64decode}}')
  client_secret=$(oc -n automation-orchestrator get secret omnigent-machine-client-credential \
    -o go-template='{{index .data "password" | base64decode}}')
  printf 'header = "Authorization: Basic %s"\n' \
    "$(printf '%s:%s' "$client_id" "$client_secret" | base64 | tr -d '\n')" >"$scratch/omnigent-client.conf"
  unset client_secret
  curl -fsS --connect-timeout 10 --max-time 30 --config "$scratch/omnigent-client.conf" \
    --data grant_type=client_credentials "$base/oauth/token" >"$scratch/omnigent-token.json" ||
    demo_die 'Could not obtain an Omnigent machine access token.'
  jq -er '.access_token | select(type == "string" and length > 0)' "$scratch/omnigent-token.json" >"$scratch/omnigent-token"
  printf 'header = "Authorization: Bearer %s"\n' "$(<"$scratch/omnigent-token")" >"$scratch/omnigent.conf"
  rm -f -- "$scratch/omnigent-client.conf" "$scratch/omnigent-token.json" "$scratch/omnigent-token"
}
