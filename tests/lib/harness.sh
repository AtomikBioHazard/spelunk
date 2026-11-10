# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Minimal test harness for spelunk shell tests. Source this file; do not execute it.
# Each test runs in its own subshell; the first failed assertion ends that test.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT
readonly REPO_ROOT

tests_run=0
tests_failed=0

fail_test() {
  printf '    assertion failed: %s\n' "$1" >&2
  exit 1
}

assert_equals() {
  local expected="$1" actual="$2" description="$3"
  if [[ "$expected" != "$actual" ]]; then
    fail_test "${description} (expected '${expected}', got '${actual}')"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" description="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail_test "${description} (missing '${needle}' in: ${haystack})"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" description="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail_test "${description} (unexpected '${needle}' in: ${haystack})"
  fi
}

assert_file_exists() {
  local path="$1" description="$2"
  if [[ ! -e "$path" ]]; then
    fail_test "${description} (missing ${path})"
  fi
}

assert_file_missing() {
  local path="$1" description="$2"
  if [[ -e "$path" ]]; then
    fail_test "${description} (unexpected ${path})"
  fi
}

assert_file_mode() {
  local path="$1" expected_mode="$2" description="$3"
  assert_equals "$expected_mode" "$(stat -c '%a' "$path")" "$description"
}

assert_files_identical() {
  local expected_path="$1" actual_path="$2" description="$3"
  if ! cmp -s "$expected_path" "$actual_path"; then
    fail_test "${description} (${actual_path} differs from ${expected_path})"
  fi
}

run_test() {
  local test_name="$1"
  tests_run=$((tests_run + 1))
  if ("$test_name"); then
    printf 'ok    %s\n' "$test_name"
    return 0
  fi
  printf 'FAIL  %s\n' "$test_name"
  tests_failed=$((tests_failed + 1))
}

finish_tests() {
  printf '\n%d tests, %d failed\n' "$tests_run" "$tests_failed"
  [[ "$tests_failed" -eq 0 ]]
}
