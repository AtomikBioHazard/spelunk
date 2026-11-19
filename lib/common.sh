# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Shared helpers for spelunk shell scripts. Source this file; do not execute it.

readonly ROOT_USER_ID=0
readonly PACKAGE_NAME_PATTERN='^[a-z0-9][a-z0-9+.-]+$'

print_step() { printf '==> %s\n' "$1"; }
print_warning() { printf 'WARNING: %s\n' "$1" >&2; }
print_error() { printf 'ERROR: %s\n' "$1" >&2; }

is_root_user() { [[ "$(id -u)" -eq "$ROOT_USER_ID" ]]; }

# Prints the runtime packages listed in the given file, one per line. Fails on a missing file,
# an empty list or an invalid package name, so a typo can never reach apt or the package metadata.
print_runtime_packages() {
  local packages_file="$1" package
  local package_count=0
  if [[ ! -r "$packages_file" ]]; then
    print_error "Cannot read the runtime package list: ${packages_file}"
    return 1
  fi
  while IFS= read -r package || [[ -n "$package" ]]; do
    if [[ ! "$package" =~ $PACKAGE_NAME_PATTERN ]]; then
      print_error "Invalid package name '${package}' in ${packages_file}"
      return 1
    fi
    printf '%s\n' "$package"
    package_count=$((package_count + 1))
  done <"$packages_file"
  if ((package_count == 0)); then
    print_error "The runtime package list is empty: ${packages_file}"
    return 1
  fi
}
