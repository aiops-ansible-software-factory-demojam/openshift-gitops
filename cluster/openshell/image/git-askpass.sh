#!/usr/bin/env sh
case "$1" in
  *Username*) printf '%s\n' "${FORGEJO_USERNAME:-demo-agent}" ;;
  *) printf '%s\n' "$FORGEJO_TOKEN" ;;
esac
