#!/usr/bin/env bash
# Installs everything needed to run and develop spelunk on Pop!_OS 24.04.
set -euo pipefail

readonly SUPPORTED_DISTRO_ID="pop"
readonly OS_RELEASE_FILE="/etc/os-release"
readonly RUNTIME_PACKAGES=(pop-launcher recoll python3-recoll python3 xdg-utils)
readonly DEVELOPMENT_PACKAGES=(python3-pip python3-full lintian shellcheck)

print_error() { printf 'ERROR: %s\n' "$1" >&2; }

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

install_packages() {
  sudo apt-get update
  sudo apt-get install -y "${RUNTIME_PACKAGES[@]}" "${DEVELOPMENT_PACKAGES[@]}"
}

verify_supported_system
install_packages
printf 'Dependencies installed. See docs/PREREQUISITES.md for the Recoll configuration.\n'
