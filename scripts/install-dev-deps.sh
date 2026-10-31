#!/usr/bin/env bash
# Installs everything needed to run and develop spelunk on Pop!_OS 24.04.
set -euo pipefail

readonly RUNTIME_PACKAGES=(pop-launcher recoll python3-recoll python3 xdg-utils)
readonly DEVELOPMENT_PACKAGES=(python3-pip python3-full lintian shellcheck)

print_error() { printf 'ERROR: %s\n' "$1" >&2; }

verify_apt_is_available() {
  if ! command -v apt-get >/dev/null; then
    print_error "apt-get not found. Spelunk targets Pop!_OS and other Debian-based systems."
    exit 1
  fi
}

install_packages() {
  sudo apt-get update
  sudo apt-get install -y "${RUNTIME_PACKAGES[@]}" "${DEVELOPMENT_PACKAGES[@]}"
}

verify_apt_is_available
install_packages
printf 'Dependencies installed. See docs/PREREQUISITES.md for the Recoll configuration.\n'
