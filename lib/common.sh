# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Shared helpers for spelunk shell scripts. Source this file; do not execute it.

print_error() { printf 'ERROR: %s\n' "$1" >&2; }
