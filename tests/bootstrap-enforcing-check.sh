#!/usr/bin/env bash
# Observe delayed AAP result events without rerunning the guest command.
set -Eeuo pipefail
test_repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$test_repo_root/bootstrap/bootstrap.sh"
test_scratch=$(mktemp -d)
trap 'rm -rf -- "$test_scratch"' EXIT

aap_find() { printf '{"id":1}\n'; }
aap_wait() { return 0; }
sleep() { SECONDS=$((SECONDS + 31)); }
aap_request() {
  case "$1 $2" in
    'POST ad_hoc_commands/')
      printf 'launch\n' >>"$test_scratch/calls"
      printf '{"id":123}\n' ;;
    'GET ad_hoc_commands/123/events/?event=runner_on_ok&page_size=200')
      printf 'event\n' >>"$test_scratch/calls"
      local reads
      reads=$(awk '$0 == "event" {n++} END {print n+0}' "$test_scratch/calls")
      if [[ $scenario == absent || ( $scenario == delayed && $reads == 1 ) ]]; then
        printf '{"count":0,"results":[]}\n'
      else
        jq -cn --arg mode "$test_mode" '{count:1,results:[{event_data:{res:{rc:0,stdout:$mode}}}]}'
      fi ;;
    *) printf 'Unexpected AAP call\n' >&2; return 1 ;;
  esac
}

for scenario in immediate delayed wrong-mode absent; do
  : >"$test_scratch/calls"
  test_mode=Enforcing
  [[ $scenario != wrong-mode ]] || test_mode=Permissive
  if ( aap_verify_enforcing ) >"$test_scratch/output" 2>&1; then
    [[ $scenario == immediate || $scenario == delayed ]]
  else
    [[ $scenario == wrong-mode || $scenario == absent ]]
    if [[ $scenario == wrong-mode ]]; then
      [[ $(awk '$0 == "event" {n++} END {print n+0}' "$test_scratch/calls") == 1 ]]
    else
      [[ $(<"$test_scratch/output") == *'result event is not available'* ]]
    fi
  fi
  [[ $(awk '$0 == "launch" {n++} END {print n+0}' "$test_scratch/calls") == 1 ]]
  printf 'PASS %s keeps one guest command and rejects actual verification failures\n' "$scenario"
done
