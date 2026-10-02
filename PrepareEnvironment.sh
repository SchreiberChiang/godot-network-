#!/usr/bin/env bash
# check is read-only; prepare downloads/imports only the tested Linux tools.
exec bash "$(dirname "$0")/tools/prepare_environment.sh" "$@"
