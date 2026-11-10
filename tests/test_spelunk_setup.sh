#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behaviour tests for bin/spelunk-setup.sh. Every external tool it depends on is stubbed,
# and each test runs in a temporary home, so nothing here touches your real account.
set -euo pipefail

# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

readonly SETUP_SCRIPT="${REPO_ROOT}/bin/spelunk-setup.sh"
readonly CONFIG_TEMPLATE="${REPO_ROOT}/data/recoll.conf.template"
readonly AUTOSTART_TEMPLATE="${REPO_ROOT}/data/recollindex.desktop"
readonly PRIVATE_DIRECTORY_MODE=700
readonly PRIVATE_FILE_MODE=600
readonly ROOT_USER_ID=0

write_stub() {
  local stub_path="${SANDBOX}/stubs/$1"
  {
    printf '#!/bin/sh\n'
    cat
  } >"$stub_path"
  chmod +x "$stub_path"
}

create_sandbox() {
  SANDBOX="$(mktemp -d)"
  trap 'rm -rf "$SANDBOX"' EXIT
  mkdir -p "${SANDBOX}/stubs" "${SANDBOX}/home"
  export HOME="${SANDBOX}/home"
  export XDG_STATE_HOME="${SANDBOX}/state"

  write_stub recollindex <<STUB
echo "\$*" >> "${SANDBOX}/indexer-calls"
[ -z "\${FAKE_INDEXER_CRASHES:-}" ] || exit 1
touch "${SANDBOX}/indexer-running"
STUB
  write_stub pgrep <<STUB
[ -f "${SANDBOX}/indexer-running" ]
STUB
  write_stub id <<'STUB'
echo "${FAKE_USER_ID:-1000}"
STUB
  write_stub python3 <<<'exit 0'
}

run_setup() {
  setup_exit_code=0
  setup_output="$(PATH="${SANDBOX}/stubs:${TEST_BASE_PATH:-$PATH}" bash "$SETUP_SCRIPT" "$@" 2>&1)" || setup_exit_code=$?
}

expected_indexer_arguments() {
  local exec_line
  exec_line="$(grep -m1 '^Exec=' "$AUTOSTART_TEMPLATE")"
  printf '%s' "${exec_line#Exec=recollindex }"
}

write_user_config() {
  mkdir -p "${HOME}/.recoll"
  printf '%s\n' "$1" >"${HOME}/.recoll/recoll.conf"
}

test_help_exits_successfully() {
  create_sandbox
  run_setup --help
  assert_equals 0 "$setup_exit_code" "help exits successfully"
  assert_contains "$setup_output" "Usage: spelunk-setup" "help shows usage"
}

test_unknown_options_are_rejected() {
  create_sandbox
  run_setup --bogus
  assert_equals 1 "$setup_exit_code" "unknown option fails"
  assert_contains "$setup_output" "Unknown option: --bogus" "names the bad option"
  run_setup ""
  assert_equals 1 "$setup_exit_code" "empty option fails"
  assert_contains "$setup_output" "Unknown option:" "reports the empty option"
}

test_refuses_to_run_as_root() {
  create_sandbox
  export FAKE_USER_ID="$ROOT_USER_ID"
  run_setup
  assert_equals 1 "$setup_exit_code" "root is refused"
  assert_contains "$setup_output" "not as root" "explains why"
  assert_file_missing "${HOME}/.recoll" "nothing is written for root"
}

test_fresh_account_gets_full_setup() {
  create_sandbox
  run_setup
  assert_equals 0 "$setup_exit_code" "setup succeeds: ${setup_output}"
  assert_files_identical "$CONFIG_TEMPLATE" "${HOME}/.recoll/recoll.conf" "template is installed"
  assert_file_mode "${HOME}/.recoll/recoll.conf" "$PRIVATE_FILE_MODE" "config is private"
  assert_file_mode "${HOME}/.recoll" "$PRIVATE_DIRECTORY_MODE" "recoll directory is private"
  assert_file_mode "${XDG_STATE_HOME}/spelunk" "$PRIVATE_DIRECTORY_MODE" "log directory is private"
  assert_files_identical "$AUTOSTART_TEMPLATE" "${HOME}/.config/autostart/recollindex.desktop" "autostart entry is installed"
  assert_equals "$(expected_indexer_arguments)" "$(cat "${SANDBOX}/indexer-calls")" "indexer starts with the autostart arguments"
  assert_contains "$(cat "${SANDBOX}/indexer-calls")" "-x" "indexer keeps running without an X11 session"
  assert_contains "$setup_output" "pkill -x cosmic-launcher" "tells the user how to restart the launcher"
  assert_not_contains "$setup_output" "WARNING" "template config produces no warning"
}

test_existing_settings_are_kept_and_hidden_entries_warned_about() {
  create_sandbox
  write_user_config "topdirs = ~/notes"
  run_setup --no-indexer --no-autostart
  assert_equals 0 "$setup_exit_code" "setup succeeds"
  assert_equals "topdirs = ~/notes" "$(cat "${HOME}/.recoll/recoll.conf")" "existing config is untouched"
  assert_contains "$setup_output" "does not exclude hidden files" "warns about hidden entries"
}

test_hidden_entries_excluded_on_a_continuation_line_gives_no_warning() {
  create_sandbox
  write_user_config 'skippedPaths =
skippedNames+ = .local .* Trash \
build dist'
  run_setup --no-indexer --no-autostart
  assert_not_contains "$setup_output" "WARNING" "no warning when .* is excluded"
}

test_a_pattern_that_only_ends_in_wildcard_does_not_count_as_hidden_entries() {
  create_sandbox
  write_user_config 'skippedNames+ = .config.* .cache'
  run_setup --no-indexer --no-autostart
  assert_contains "$setup_output" "does not exclude hidden files" "still warns"
}

test_removing_hidden_entries_from_the_defaults_does_not_count_as_excluding_them() {
  create_sandbox
  write_user_config 'skippedNames- = .*'
  run_setup --no-indexer --no-autostart
  assert_contains "$setup_output" "does not exclude hidden files" "still warns"
}

test_comment_only_config_is_replaced_by_the_template() {
  create_sandbox
  write_user_config '# Recoll default configuration, nothing set'
  run_setup --no-indexer --no-autostart
  assert_files_identical "$CONFIG_TEMPLATE" "${HOME}/.recoll/recoll.conf" "template replaces an empty config"
}

test_loose_directory_permissions_are_tightened() {
  create_sandbox
  mkdir -p "${HOME}/.recoll"
  chmod 755 "${HOME}/.recoll"
  run_setup --no-indexer --no-autostart
  assert_file_mode "${HOME}/.recoll" "$PRIVATE_DIRECTORY_MODE" "directory is restricted"
  assert_contains "$setup_output" "Restricted" "the change is reported"
}

test_second_run_changes_nothing() {
  create_sandbox
  run_setup
  run_setup
  assert_equals 0 "$setup_exit_code" "second run succeeds"
  assert_contains "$setup_output" "Keeping your existing Recoll configuration" "config is kept"
  assert_contains "$setup_output" "Keeping your existing autostart entry" "autostart is kept"
  assert_contains "$setup_output" "Indexer is already running" "no second indexer"
  assert_equals 1 "$(wc -l <"${SANDBOX}/indexer-calls")" "indexer was started exactly once"
}

test_flags_disable_autostart_and_indexer() {
  create_sandbox
  run_setup --no-autostart --no-indexer
  assert_equals 0 "$setup_exit_code" "setup succeeds"
  assert_file_missing "${HOME}/.config/autostart/recollindex.desktop" "no autostart entry"
  assert_file_missing "${SANDBOX}/indexer-calls" "indexer was not started"
  assert_file_exists "${HOME}/.recoll/recoll.conf" "config is still installed"
}

test_missing_python_module_is_reported() {
  create_sandbox
  write_stub python3 <<<'exit 1'
  run_setup
  assert_equals 1 "$setup_exit_code" "setup fails"
  assert_contains "$setup_output" "Python Recoll module is missing" "names the problem"
  assert_file_missing "${HOME}/.recoll" "nothing is written"
}

test_missing_recollindex_is_reported() {
  create_sandbox
  rm "${SANDBOX}/stubs/recollindex"
  mkdir "${SANDBOX}/filtered-bin"
  ln -s /usr/bin/* "${SANDBOX}/filtered-bin/"
  rm -f "${SANDBOX}/filtered-bin/recollindex"
  export TEST_BASE_PATH="${SANDBOX}/filtered-bin"
  run_setup
  assert_equals 1 "$setup_exit_code" "setup fails"
  assert_contains "$setup_output" "Recoll is not installed" "names the problem"
  assert_file_missing "${HOME}/.recoll" "nothing is written"
}

test_an_indexer_that_dies_immediately_is_reported() {
  create_sandbox
  export FAKE_INDEXER_CRASHES=1
  run_setup
  assert_equals 1 "$setup_exit_code" "setup fails"
  assert_contains "$setup_output" "stopped right after starting" "names the problem"
  assert_contains "$setup_output" "indexer.log" "points to the log"
}

run_test test_help_exits_successfully
run_test test_unknown_options_are_rejected
run_test test_refuses_to_run_as_root
run_test test_fresh_account_gets_full_setup
run_test test_existing_settings_are_kept_and_hidden_entries_warned_about
run_test test_hidden_entries_excluded_on_a_continuation_line_gives_no_warning
run_test test_a_pattern_that_only_ends_in_wildcard_does_not_count_as_hidden_entries
run_test test_removing_hidden_entries_from_the_defaults_does_not_count_as_excluding_them
run_test test_comment_only_config_is_replaced_by_the_template
run_test test_loose_directory_permissions_are_tightened
run_test test_second_run_changes_nothing
run_test test_flags_disable_autostart_and_indexer
run_test test_missing_python_module_is_reported
run_test test_missing_recollindex_is_reported
run_test test_an_indexer_that_dies_immediately_is_reported
finish_tests
