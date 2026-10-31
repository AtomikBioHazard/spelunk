#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Installs everything needed to run and develop spelunk on Pop!_OS 24.04.
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIRECTORY
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIRECTORY}/../lib/common.sh"

readonly SUPPORTED_DISTRO_ID="pop"
readonly OS_RELEASE_FILE="/etc/os-release"
readonly ROOT_USER_ID=0
readonly RUNTIME_PACKAGES=(pop-launcher recoll python3-recoll python3 xdg-utils)
readonly DEVELOPMENT_PACKAGES=(lintian shellcheck)

verify_supported_system() {
  local distro_id
  if [[ ! -r "$OS_RELEASE_FILE" ]]; then
    print_error "Cannot read ${OS_RELEASE_FILE}; unable to confirm this is Pop!_OS."
    exit 1
  fi
  distro_id="$(awk -F= '$1 == "ID" { gsub(/"/, "", $2); print $2 }' "$OS_RELEASE_FILE")"
  if [[ "$distro_id" != "$SUPPORTED_DISTRO_ID" ]]; then
    print_error "Unsupported system '${distro_id:-unknown}'. Spelunk targets Pop!_OS (COSMIC)."
    exit 1
  fi
}

run_as_root() {
  if [[ "$EUID" -eq "$ROOT_USER_ID" ]]; then
    "$@"
    return
  fi
  if ! command -v sudo >/dev/null; then
    print_error "sudo is required to install packages. Run this script as root or install sudo."
    exit 1
  fi
  sudo "$@"
}

install_packages() {
  run_as_root apt-get update
  run_as_root apt-get install -y "${RUNTIME_PACKAGES[@]}" "${DEVELOPMENT_PACKAGES[@]}"
}

verify_supported_system
install_packages
printf 'Dependencies installed. See docs/PREREQUISITES.md for the Recoll configuration.\n'
