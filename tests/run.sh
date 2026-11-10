#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Runs every tests/test_*.sh file and fails if any of them fails.
set -euo pipefail

TESTS_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TESTS_DIRECTORY

overall_status=0
for test_file in "${TESTS_DIRECTORY}"/test_*.sh; do
  printf '\n== %s\n' "$(basename "$test_file")"
  bash "$test_file" || overall_status=1
done

exit "$overall_status"
