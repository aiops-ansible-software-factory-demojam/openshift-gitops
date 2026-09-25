#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/api.sh"
root=$(cd -- "$(dirname "$0")/.." && pwd)
repo=demo-owner/ansible-collection-demo
title='Allow configuring the nginx worker UID'
issues=$(api GET "/repos/$repo/issues?state=all&limit=100")
existing=$(jq -r --arg title "$title" \
  '.[] | select(.title == $title and .pull_request == null) | .html_url' \
  <<<"$issues" | head -1)
if [[ -n $existing ]]; then
  printf '%s\n' "$existing"
else
  "$root/scripts/issue.sh" "$repo" "$title" "$root/fixtures/nginx-uid-issue.md"
fi
