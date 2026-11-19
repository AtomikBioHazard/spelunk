#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Tests for the .deb produced by scripts/build-deb.sh. They inspect the finished package, not the
# build script: contents, modes, metadata, reproducibility, the installed layout and lintian.
set -euo pipefail

# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

readonly BUILD_SCRIPT="${REPO_ROOT}/scripts/build-deb.sh"
readonly RUNTIME_PACKAGES_FILE="${REPO_ROOT}/packaging/runtime-packages.txt"
readonly PACKAGE_NAME="spelunk"
readonly VERSION_SUFFIX="~dev.abc1234"
readonly MAX_CHANGELOG_LINE_LENGTH=78
readonly EXPECTED_FILES=(
  "-rwxr-xr-x ./usr/lib/spelunk/bin/spelunk-setup.sh"
  "-rw-r--r-- ./usr/lib/spelunk/lib/common.sh"
  "-rw-r--r-- ./usr/lib/spelunk/data/recoll.conf.template"
  "-rw-r--r-- ./usr/lib/spelunk/data/recollindex.desktop"
  "-rw-r--r-- ./usr/lib/pop-launcher/plugins/spelunk/plugin.ron"
  "-rwxr-xr-x ./usr/lib/pop-launcher/plugins/spelunk/search_bridge.py"
  "-rw-r--r-- ./usr/share/doc/spelunk/README.md"
  "-rw-r--r-- ./usr/share/doc/spelunk/PREREQUISITES.md"
  "-rw-r--r-- ./usr/share/doc/spelunk/copyright"
  "-rw-r--r-- ./usr/share/doc/spelunk/changelog.gz"
  "-rw-r--r-- ./usr/share/man/man1/spelunk-setup.1.gz"
  "lrwxrwxrwx ./usr/bin/spelunk-setup"
)

BASE_VERSION="$(tr -d '[:space:]' <"${REPO_ROOT}/VERSION")"
BUILD_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIRECTORY"' EXIT
bash "$BUILD_SCRIPT" --output-directory "$BUILD_DIRECTORY" >/dev/null
PACKAGE_FILE="${BUILD_DIRECTORY}/${PACKAGE_NAME}_${BASE_VERSION}_all.deb"

package_entries() { dpkg-deb --contents "$PACKAGE_FILE"; }

extract_package() {
  local target="$1"
  dpkg-deb --extract "$PACKAGE_FILE" "$target"
  dpkg-deb --control "$PACKAGE_FILE" "${target}/DEBIAN"
}

read_packaged_file() { dpkg-deb --fsys-tarfile "$PACKAGE_FILE" | tar -xO "$1"; }

create_scratch_directory() {
  SCRATCH="$(mktemp -d)"
  trap 'rm -rf "$SCRATCH"' EXIT
}

test_the_package_contains_exactly_the_expected_files() {
  local expected actual
  expected="$(printf '%s\n' "${EXPECTED_FILES[@]}" | sort)"
  actual="$(package_entries | awk '$1 !~ /^d/ { print $1, $6 }' | sort)"
  assert_equals "$expected" "$actual" "files and modes match the documented layout"
}

test_everything_is_owned_by_root_and_lives_under_usr() {
  assert_equals "" "$(package_entries | awk '$2 != "root/root"')" "no entry is owned by anyone else"
  assert_equals "" "$(package_entries | awk '$6 != "./" && $6 !~ /^\.\/usr\//')" "nothing outside /usr"
}

test_directories_are_readable_but_not_writable_by_others() {
  assert_equals "" "$(package_entries | awk '$1 ~ /^d/ && $1 != "drwxr-xr-x"')" "every directory is drwxr-xr-x"
}

test_the_command_is_a_relative_link_to_the_setup_script() {
  assert_contains "$(package_entries)" "./usr/bin/spelunk-setup -> ../lib/spelunk/bin/spelunk-setup.sh" "relative link"
}

test_the_control_metadata_is_complete_and_matches_the_sources() {
  local expected_dependencies size
  expected_dependencies="$(paste -sd',' "$RUNTIME_PACKAGES_FILE" | sed 's/,/, /g')"
  assert_equals "$PACKAGE_NAME" "$(dpkg-deb --field "$PACKAGE_FILE" Package)" "package name"
  assert_equals "$BASE_VERSION" "$(dpkg-deb --field "$PACKAGE_FILE" Version)" "version comes from the VERSION file"
  assert_equals "all" "$(dpkg-deb --field "$PACKAGE_FILE" Architecture)" "architecture"
  assert_equals "$expected_dependencies" "$(dpkg-deb --field "$PACKAGE_FILE" Depends)" "dependencies come from the runtime package list"
  assert_contains "$(dpkg-deb --field "$PACKAGE_FILE" Maintainer)" "<atomikbiohazard@gmail.com>" "maintainer"
  assert_contains "$(dpkg-deb --field "$PACKAGE_FILE" Homepage)" "github.com/AtomikBioHazard/spelunk" "homepage"
  size="$(dpkg-deb --field "$PACKAGE_FILE" Installed-Size)"
  if [[ ! "$size" =~ ^[0-9]+$ ]] || ((size == 0)); then
    fail_test "Installed-Size is '${size}'"
  fi
}

test_a_version_suffix_is_applied() {
  create_scratch_directory
  bash "$BUILD_SCRIPT" --version-suffix "$VERSION_SUFFIX" --output-directory "$SCRATCH" >/dev/null
  local suffixed_file="${SCRATCH}/${PACKAGE_NAME}_${BASE_VERSION}${VERSION_SUFFIX}_all.deb"
  assert_file_exists "$suffixed_file" "the file name carries the suffix"
  assert_equals "${BASE_VERSION}${VERSION_SUFFIX}" "$(dpkg-deb --field "$suffixed_file" Version)" "the version carries the suffix"
}

test_invalid_arguments_are_rejected() {
  create_scratch_directory
  local output exit_code=0
  output="$(bash "$BUILD_SCRIPT" --bogus 2>&1)" || exit_code=$?
  assert_equals 1 "$exit_code" "unknown option fails"
  assert_contains "$output" "Unknown option: --bogus" "names the option"
  exit_code=0
  output="$(bash "$BUILD_SCRIPT" --version-suffix 2>&1)" || exit_code=$?
  assert_equals 1 "$exit_code" "missing value fails"
  assert_contains "$output" "needs a value" "explains"
  exit_code=0
  output="$(bash "$BUILD_SCRIPT" --version-suffix "bad suffix" --output-directory "$SCRATCH" 2>&1)" || exit_code=$?
  assert_equals 1 "$exit_code" "invalid suffix fails"
  assert_contains "$output" "Invalid --version-suffix" "explains"
  assert_equals "" "$(ls -A "$SCRATCH")" "nothing was built"
}

test_the_build_is_reproducible() {
  create_scratch_directory
  bash "$BUILD_SCRIPT" --output-directory "$SCRATCH" >/dev/null
  assert_files_identical "$PACKAGE_FILE" "${SCRATCH}/${PACKAGE_NAME}_${BASE_VERSION}_all.deb" "two builds of the same commit are byte-identical"
}

test_the_post_install_script_prints_the_next_step_and_leaves_the_home_alone() {
  create_scratch_directory
  extract_package "${SCRATCH}/root"
  mkdir "${SCRATCH}/home"
  local output
  output="$(HOME="${SCRATCH}/home" sh "${SCRATCH}/root/DEBIAN/postinst" configure)"
  assert_contains "$output" "spelunk-setup" "tells the user what to run next"
  assert_equals "" "$(ls -A "${SCRATCH}/home")" "no per-user state is created"
  assert_equals "" "$(HOME="${SCRATCH}/home" sh "${SCRATCH}/root/DEBIAN/postinst" abort-upgrade)" "silent for other actions"
}

test_the_installed_layout_works_from_the_package() {
  create_scratch_directory
  extract_package "${SCRATCH}/root"
  mkdir "${SCRATCH}/home"
  local output
  output="$("${SCRATCH}/root/usr/bin/spelunk-setup" --help)"
  assert_contains "$output" "Usage: spelunk-setup" "the link resolves and the script finds its library"
  output="$(HOME="${SCRATCH}/home" XDG_STATE_HOME="${SCRATCH}/state" "${SCRATCH}/root/usr/bin/spelunk-setup" --no-indexer --no-autostart 2>&1)" || fail_test "setup from the package failed: ${output}"
  assert_files_identical "${SCRATCH}/root/usr/lib/spelunk/data/recoll.conf.template" "${SCRATCH}/home/.recoll/recoll.conf" "the packaged template is what gets installed"
  assert_files_identical "${REPO_ROOT}/data/recoll.conf.template" "${SCRATCH}/home/.recoll/recoll.conf" "and it is the template from the repository"
}

test_the_packaged_plugin_is_the_source_plugin() {
  create_scratch_directory
  extract_package "${SCRATCH}/root"
  local plugin_directory="${SCRATCH}/root/usr/lib/pop-launcher/plugins/${PACKAGE_NAME}"
  assert_files_identical "${REPO_ROOT}/plugin/plugin.ron" "${plugin_directory}/plugin.ron" "manifest"
  assert_files_identical "${REPO_ROOT}/plugin/search_bridge.py" "${plugin_directory}/search_bridge.py" "script"
  if [[ ! -x "${plugin_directory}/search_bridge.py" ]]; then
    fail_test "the plugin entry point is not executable"
  fi
}

test_the_man_page_documents_every_option_of_the_command() {
  local options option man_text
  create_scratch_directory
  extract_package "${SCRATCH}/root"
  options="$("${SCRATCH}/root/usr/bin/spelunk-setup" --help | grep -oE '^ +--[a-z-]+' | tr -d ' ')"
  man_text="$(read_packaged_file ./usr/share/man/man1/spelunk-setup.1.gz | gzip -dc)"
  assert_contains "$options" "--help" "the options were read from the command"
  while IFS= read -r option; do
    if ! grep -Fxq ".B ${option//-/\\-}" <<<"$man_text"; then
      fail_test "the OPTIONS section of the man page does not document ${option}"
    fi
  done <<<"$options"
}

test_the_changelog_is_a_valid_debian_entry() {
  local changelog line
  changelog="$(read_packaged_file ./usr/share/doc/spelunk/changelog.gz | gzip -dc)"
  assert_equals "${PACKAGE_NAME} (${BASE_VERSION}) unstable; urgency=medium" "$(head -1 <<<"$changelog")" "header line"
  assert_contains "$changelog" "  * Added:" "entries are converted from CHANGELOG.md"
  if ! grep -qE '^ -- .+ <.+>  [A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9:]{8} \+0000$' <<<"$changelog"; then
    fail_test "the trailer line is not a valid Debian signature"
  fi
  while IFS= read -r line; do
    if ((${#line} > MAX_CHANGELOG_LINE_LENGTH)); then
      fail_test "changelog line longer than ${MAX_CHANGELOG_LINE_LENGTH}: ${line}"
    fi
  done <<<"$changelog"
}

test_lintian_finds_nothing_to_report() {
  local report
  report="$(lintian --tag-display-limit 0 "$PACKAGE_FILE" 2>&1)" || fail_test "lintian failed: ${report}"
  assert_equals "" "$report" "lintian has no warnings, errors or notes, and no override is used"
}

run_test test_the_package_contains_exactly_the_expected_files
run_test test_everything_is_owned_by_root_and_lives_under_usr
run_test test_directories_are_readable_but_not_writable_by_others
run_test test_the_command_is_a_relative_link_to_the_setup_script
run_test test_the_control_metadata_is_complete_and_matches_the_sources
run_test test_a_version_suffix_is_applied
run_test test_invalid_arguments_are_rejected
run_test test_the_build_is_reproducible
run_test test_the_post_install_script_prints_the_next_step_and_leaves_the_home_alone
run_test test_the_installed_layout_works_from_the_package
run_test test_the_packaged_plugin_is_the_source_plugin
run_test test_the_man_page_documents_every_option_of_the_command
run_test test_the_changelog_is_a_valid_debian_entry
run_test test_lintian_finds_nothing_to_report
finish_tests
