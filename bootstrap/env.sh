#!/usr/bin/env bash
# Shared configuration for demo entry points, without duplicating bootstrap logic.
# shellcheck source=bootstrap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/bootstrap.sh"
demo_load_env
