#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behaviour tests for scripts/install-dev-deps.sh. apt-get and sudo are stubbed, and the script runs
# from a copy of the repository tree whose os-release path points at a test file.
set -euo pipefail

# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

readonly RUNTIME_PACKAGES_FILE="${REPO_ROOT}/packaging/runtime-packages.txt"
readonly DEVELOPMENT_PACKAGES="lintian pre-commit"
readonly ROOT_USER_ID=0

create_sandbox() {
  SANDBOX="$(mktemp -d)"
  trap 'rm -rf "$SANDBOX"' EXIT
  mkdir -p "${SANDBOX}/stubs" "${SANDBOX}/tree/scripts" "${SANDBOX}/tree/lib" "${SANDBOX}/tree/packaging"
  cp "${REPO_ROOT}/scripts/install-dev-deps.sh" "${SANDBOX}/tree/scripts/"
  cp "${REPO_ROOT}/lib/common.sh" "${SANDBOX}/tree/lib/"
  cp "$RUNTIME_PACKAGES_FILE" "${SANDBOX}/tree/packaging/"
  sed -i "s|/etc/os-release|${SANDBOX}/os-release|" "${SANDBOX}/tree/scripts/install-dev-deps.sh"
  printf 'ID=pop\n' >"${SANDBOX}/os-release"
  PACKAGE_LIST="${SANDBOX}/tree/packaging/runtime-packages.txt"
  APT_CALLS="${SANDBOX}/apt-calls"
  SUDO_CALLS="${SANDBOX}/sudo-calls"

  write_stub sudo <<STUB
echo "\$*" >> "${SUDO_CALLS}"
exec "\$@"
STUB
  write_stub apt-get <<STUB
echo "\$*" >> "${APT_CALLS}"
STUB
  write_stub id <<'STUB'
echo "${FAKE_USER_ID:-1000}"
STUB
}

run_installer() {
  installer_exit_code=0
  installer_output="$(PATH="${SANDBOX}/stubs:${TEST_BASE_PATH:-$PATH}" bash "${SANDBOX}/tree/scripts/install-dev-deps.sh" 2>&1)" || installer_exit_code=$?
}

expected_install_call() {
  local runtime_packages
  runtime_packages="$(paste -sd' ' "$PACKAGE_LIST")"
  printf 'install -y %s %s' "$runtime_packages" "$DEVELOPMENT_PACKAGES"
}

test_the_runtime_list_and_the_development_tools_are_installed() {
  create_sandbox
  run_installer
  assert_equals 0 "$installer_exit_code" "installer succeeds: ${installer_output}"
  assert_equals "update" "$(sed -n 1p "$APT_CALLS")" "the package index is refreshed first"
  assert_equals "$(expected_install_call)" "$(sed -n 2p "$APT_CALLS")" "every listed package is installed"
  assert_equals 2 "$(wc -l <"$SUDO_CALLS")" "both apt calls go through sudo"
}

test_a_package_added_to_the_list_is_installed() {
  create_sandbox
  printf 'extra-package\n' >>"$PACKAGE_LIST"
  run_installer
  assert_contains "$(sed -n 2p "$APT_CALLS")" "extra-package" "the list is the single source"
}

test_a_last_line_without_a_newline_is_still_read() {
  create_sandbox
  printf 'recoll\nxdg-utils' >"$PACKAGE_LIST"
  run_installer
  assert_equals "install -y recoll xdg-utils ${DEVELOPMENT_PACKAGES}" "$(sed -n 2p "$APT_CALLS")" "the final package is not dropped"
}

test_root_installs_without_sudo() {
  create_sandbox
  export FAKE_USER_ID="$ROOT_USER_ID"
  run_installer
  assert_equals 0 "$installer_exit_code" "installer succeeds"
  assert_file_exists "$APT_CALLS" "apt-get ran"
  assert_file_missing "$SUDO_CALLS" "sudo was not used"
}

test_a_missing_sudo_is_reported() {
  create_sandbox
  rm "${SANDBOX}/stubs/sudo"
  TEST_BASE_PATH="$(create_path_without sudo)"
  export TEST_BASE_PATH
  run_installer
  assert_equals 1 "$installer_exit_code" "installer fails"
  assert_contains "$installer_output" "sudo is required" "names the problem"
  assert_file_missing "$APT_CALLS" "nothing was installed"
}

test_an_unsupported_system_is_rejected() {
  create_sandbox
  printf 'ID=ubuntu\n' >"${SANDBOX}/os-release"
  run_installer
  assert_equals 1 "$installer_exit_code" "installer fails"
  assert_contains "$installer_output" "Unsupported system 'ubuntu'" "names the system"
  assert_file_missing "$APT_CALLS" "nothing was installed"
}

test_an_unreadable_os_release_is_reported() {
  create_sandbox
  rm "${SANDBOX}/os-release"
  run_installer
  assert_equals 1 "$installer_exit_code" "installer fails"
  assert_contains "$installer_output" "Cannot read" "names the problem"
  assert_file_missing "$APT_CALLS" "nothing was installed"
}

test_a_missing_package_list_is_reported() {
  create_sandbox
  rm "$PACKAGE_LIST"
  run_installer
  assert_equals 1 "$installer_exit_code" "installer fails"
  assert_contains "$installer_output" "Cannot read the runtime package list" "names the problem"
  assert_file_missing "$APT_CALLS" "nothing was installed"
}

test_an_empty_package_list_is_rejected() {
  create_sandbox
  : >"$PACKAGE_LIST"
  run_installer
  assert_equals 1 "$installer_exit_code" "installer fails"
  assert_file_missing "$APT_CALLS" "nothing was installed"
}

test_an_invalid_package_name_is_rejected_before_apt_runs() {
  create_sandbox
  printf 'recoll\nBad Name\n' >"$PACKAGE_LIST"
  run_installer
  assert_equals 1 "$installer_exit_code" "installer fails"
  assert_contains "$installer_output" "Invalid package name 'Bad Name'" "names the bad entry"
  assert_file_missing "$APT_CALLS" "not even the package index was refreshed"
}

run_test test_the_runtime_list_and_the_development_tools_are_installed
run_test test_a_package_added_to_the_list_is_installed
run_test test_a_last_line_without_a_newline_is_still_read
run_test test_root_installs_without_sudo
run_test test_a_missing_sudo_is_reported
run_test test_an_unsupported_system_is_rejected
run_test test_an_unreadable_os_release_is_reported
run_test test_a_missing_package_list_is_reported
run_test test_an_empty_package_list_is_rejected
run_test test_an_invalid_package_name_is_rejected_before_apt_runs
finish_tests
