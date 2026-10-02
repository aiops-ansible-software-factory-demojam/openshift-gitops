#!/usr/bin/env bash
set -euo pipefail
bootstrap="$(dirname -- "${BASH_SOURCE[0]}")/../bootstrap/bootstrap.sh"
case ${1:-} in
  hydrate) [[ $# == 1 ]] || exit 2; exec bash "$bootstrap" hydrate ;;
  reset) [[ $# == 2 && $2 == --confirm-forgejo ]] || exit 2; exec bash "$bootstrap" forgejo-reset "$2" ;;
  *) echo 'Usage: feature-demo.sh hydrate | reset --confirm-forgejo' >&2; exit 2 ;;
esac
