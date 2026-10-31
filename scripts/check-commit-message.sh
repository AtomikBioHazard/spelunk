#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# commit-msg hook: rejects commit messages that have a body (single-line messages only).
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIRECTORY}/../lib/common.sh"

readonly MAX_CONTENT_LINES=1
readonly IGNORED_LINE_PATTERN='^(#|[[:space:]]*$)'

message_file="${1:-}"
if [[ -z "$message_file" || ! -r "$message_file" ]]; then
  print_error "Usage: check-commit-message.sh <commit-message-file>"
  exit 1
fi

content_line_count="$(grep -cvE "$IGNORED_LINE_PATTERN" "$message_file" || true)"
if ((content_line_count > MAX_CONTENT_LINES)); then
  print_error "Commit messages must be a single line without a body (found ${content_line_count} lines)."
  exit 1
fi
