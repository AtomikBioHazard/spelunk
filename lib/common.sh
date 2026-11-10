# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Shared helpers for spelunk shell scripts. Source this file; do not execute it.

readonly ROOT_USER_ID=0

print_error() { printf 'ERROR: %s\n' "$1" >&2; }

is_root_user() { [[ "$(id -u)" -eq "$ROOT_USER_ID" ]]; }
