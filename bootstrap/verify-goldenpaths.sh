#!/usr/bin/env bash
set -euo pipefail

oc whoami --show-server
oc whoami
oc -n rhdh rollout status deployment/backstage-rhdh-developer-hub --timeout=15m
rhdh_host=$(oc -n rhdh get route backstage-rhdh-developer-hub \
  -o jsonpath='{.status.ingress[0].host}')
[[ -n $rhdh_host ]] || { echo 'RHDH Route has no host.' >&2; exit 1; }
base_url="https://$rhdh_host"

deadline=$((SECONDS + 600))
while :; do
  token=$(curl -fsS --max-time 20 -X POST \
    -H 'Content-Type: application/json' -d '{}' \
    "$base_url/api/auth/guest/refresh" 2>/dev/null |
    jq -er '.backstageIdentity.token' 2>/dev/null) || token=
  if [[ -n $token ]] &&
     curl -fsS --max-time 20 -H "Authorization: Bearer $token" \
       "$base_url/api/scaffolder/v2/actions" 2>/dev/null |
       jq -e 'any(.[]; .id == "http:backstage:request")' >/dev/null 2>&1; then
    ready=true
    for ref in template/default/ansible-collection \
      template/default/ansible-collection-feature \
      component/default/ansible-collection-demo; do
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
