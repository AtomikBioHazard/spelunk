#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds spelunk_<version>_all.deb from the repository tree. Reproducible: file timestamps are
# clamped to the date of the last commit, so the same commit always gives the same package.
# Usage: scripts/build-deb.sh [--version-suffix SUFFIX] [--output-directory DIRECTORY]
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly SCRIPT_DIRECTORY
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIRECTORY}/../lib/common.sh"

REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly REPOSITORY_ROOT

readonly PACKAGE_NAME="spelunk"
readonly SEMVER_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'
readonly VERSION_SUFFIX_PATTERN='^[~+.0-9A-Za-z]*$'
readonly EXECUTABLE_MODE=755
readonly FILE_MODE=644
readonly DIRECTORY_MODE=755
readonly FILE_CREATION_MASK=022
readonly ARGUMENTS_PER_OPTION=2
readonly APPLICATION_DIRECTORY="usr/lib/${PACKAGE_NAME}"
readonly PLUGIN_DIRECTORY="usr/lib/pop-launcher/plugins/${PACKAGE_NAME}"
readonly DOCUMENTATION_DIRECTORY="usr/share/doc/${PACKAGE_NAME}"
readonly MANUAL_FILE="usr/share/man/man1/spelunk-setup.1.gz"
readonly COMMAND_LINK="usr/bin/spelunk-setup"
readonly COMMAND_LINK_TARGET="../lib/${PACKAGE_NAME}/bin/spelunk-setup.sh"
readonly CONTROL_TEMPLATE="${REPOSITORY_ROOT}/packaging/control.in"
readonly RUNTIME_PACKAGES_FILE="${REPOSITORY_ROOT}/packaging/runtime-packages.txt"
readonly POSTINST_SOURCE="${REPOSITORY_ROOT}/packaging/postinst.sh"
readonly MANUAL_SOURCE="${REPOSITORY_ROOT}/packaging/spelunk-setup.1"
readonly CHANGELOG_SOURCE="${REPOSITORY_ROOT}/CHANGELOG.md"
readonly CHANGELOG_CONVERTER="${REPOSITORY_ROOT}/packaging/changelog-to-debian.awk"
readonly CHANGELOG_LINE_WIDTH=78
readonly UNRELEASED_SECTION="## [Unreleased]"
readonly DEFAULT_OUTPUT_DIRECTORY="${REPOSITORY_ROOT}/dist"

# Path inside the package => "mode:source path inside the repository". The layout is described in
# docs/ARCHITECTURE.md; add a file to the package by adding a line here.
declare -A -r INSTALLED_FILES=(
  ["${APPLICATION_DIRECTORY}/bin/spelunk-setup.sh"]="${EXECUTABLE_MODE}:bin/spelunk-setup.sh"
  ["${APPLICATION_DIRECTORY}/lib/common.sh"]="${FILE_MODE}:lib/common.sh"
  ["${APPLICATION_DIRECTORY}/data/recoll.conf.template"]="${FILE_MODE}:data/recoll.conf.template"
  ["${APPLICATION_DIRECTORY}/data/recollindex.desktop"]="${FILE_MODE}:data/recollindex.desktop"
  ["${PLUGIN_DIRECTORY}/plugin.ron"]="${FILE_MODE}:plugin/plugin.ron"
  ["${PLUGIN_DIRECTORY}/search_bridge.py"]="${EXECUTABLE_MODE}:plugin/search_bridge.py"
  ["${DOCUMENTATION_DIRECTORY}/README.md"]="${FILE_MODE}:README.md"
  ["${DOCUMENTATION_DIRECTORY}/PREREQUISITES.md"]="${FILE_MODE}:docs/PREREQUISITES.md"
  ["${DOCUMENTATION_DIRECTORY}/copyright"]="${FILE_MODE}:LICENSE"
)

declare -A -r VALUE_FLAGS=(
  ["--version-suffix"]=version_suffix
  ["--output-directory"]=output_directory
)

version_suffix=""
output_directory="$DEFAULT_OUTPUT_DIRECTORY"
staging_directory=""

parse_arguments() {
  local flag
  while (($# > 0)); do
    flag="$1"
    if [[ -z "$flag" || -z "${VALUE_FLAGS[$flag]:-}" ]]; then
      print_error "Unknown option: ${flag}"
      exit 1
    fi
    if (($# < ARGUMENTS_PER_OPTION)); then
      print_error "${flag} needs a value"
      exit 1
    fi
    printf -v "${VALUE_FLAGS[$flag]}" '%s' "$2"
    shift "$ARGUMENTS_PER_OPTION"
  done
}

read_base_version() {
  local version
  version="$(tr -d '[:space:]' <"${REPOSITORY_ROOT}/VERSION")"
  if [[ ! "$version" =~ $SEMVER_PATTERN ]]; then
    print_error "VERSION must look like X.Y.Z, found '${version}'"
    exit 1
  fi
  printf '%s' "$version"
}

read_source_date_epoch() {
  local epoch
  if ! epoch="$(git -C "$REPOSITORY_ROOT" log -1 --format=%ct 2>/dev/null)" || [[ -z "$epoch" ]]; then
    print_error "Cannot read the date of the last commit. Build from a git checkout."
    exit 1
  fi
  printf '%s' "$epoch"
}

format_dependencies() {
  local packages_text joined
  local -a packages
  packages_text="$(print_runtime_packages "$RUNTIME_PACKAGES_FILE")"
  mapfile -t packages <<<"$packages_text"
  printf -v joined '%s, ' "${packages[@]}"
  printf '%s' "${joined%, }"
}

stage_installed_files() {
  local destination mode source
  for destination in "${!INSTALLED_FILES[@]}"; do
    IFS=: read -r mode source <<<"${INSTALLED_FILES[$destination]}"
    install -D -m "$mode" "${REPOSITORY_ROOT}/${source}" "${staging_directory}/${destination}"
  done
}

# Debian wants its own changelog format for the package, so the release section of CHANGELOG.md is
# converted. A dated section for this version wins; otherwise the Unreleased section is used.
write_debian_changelog() {
  local package_version="$1" base_version="$2" section_marker maintainer entries
  section_marker="$UNRELEASED_SECTION"
  if grep -qF "## [${base_version}]" "$CHANGELOG_SOURCE"; then
    section_marker="## [${base_version}]"
  fi
  entries="$(awk -v marker="$section_marker" -v width="$CHANGELOG_LINE_WIDTH" -f "$CHANGELOG_CONVERTER" "$CHANGELOG_SOURCE")"
  if [[ -z "$entries" ]]; then
    print_error "CHANGELOG.md has no entries under '${section_marker}'."
    exit 1
  fi
  maintainer="$(sed -n 's/^Maintainer: //p' "$CONTROL_TEMPLATE")"
  {
    printf '%s (%s) unstable; urgency=medium\n\n' "$PACKAGE_NAME" "$package_version"
    printf '%s\n\n' "$entries"
    printf ' -- %s  %s\n' "$maintainer" "$(date -u -R -d "@${SOURCE_DATE_EPOCH}")"
  } | gzip --best --no-name >"${staging_directory}/${DOCUMENTATION_DIRECTORY}/changelog.gz"
}

stage_generated_files() {
  local package_version="$1" base_version="$2"
  install -d -m "$DIRECTORY_MODE" "$(dirname "${staging_directory}/${MANUAL_FILE}")" "$(dirname "${staging_directory}/${COMMAND_LINK}")"
  write_debian_changelog "$package_version" "$base_version"
  gzip --best --no-name --stdout "$MANUAL_SOURCE" >"${staging_directory}/${MANUAL_FILE}"
  chmod "$FILE_MODE" "${staging_directory}/${DOCUMENTATION_DIRECTORY}/changelog.gz" "${staging_directory}/${MANUAL_FILE}"
  ln -s "$COMMAND_LINK_TARGET" "${staging_directory}/${COMMAND_LINK}"
}

write_control_files() {
  local package_version="$1" installed_size="$2" dependencies="$3"
  install -d -m "$DIRECTORY_MODE" "${staging_directory}/DEBIAN"
  sed -e "s|@VERSION@|${package_version}|" \
    -e "s|@INSTALLED_SIZE@|${installed_size}|" \
    -e "s|@DEPENDS@|${dependencies}|" \
    "$CONTROL_TEMPLATE" >"${staging_directory}/DEBIAN/control"
  install -m "$EXECUTABLE_MODE" "$POSTINST_SOURCE" "${staging_directory}/DEBIAN/postinst"
}

parse_arguments "$@"
if [[ ! "$version_suffix" =~ $VERSION_SUFFIX_PATTERN ]]; then
  print_error "Invalid --version-suffix '${version_suffix}': use letters, digits, '.', '+' and '~'."
  exit 1
fi

umask "$FILE_CREATION_MASK"
base_version="$(read_base_version)"
package_version="${base_version}${version_suffix}"
SOURCE_DATE_EPOCH="$(read_source_date_epoch)"
export SOURCE_DATE_EPOCH

staging_directory="$(mktemp -d)"
trap 'rm -rf "${staging_directory:?}"' EXIT
chmod "$DIRECTORY_MODE" "$staging_directory"

stage_installed_files
stage_generated_files "$package_version" "$base_version"
dependencies="$(format_dependencies)"
installed_size="$(du -sk --apparent-size "$staging_directory" | cut -f1)"
write_control_files "$package_version" "$installed_size" "$dependencies"

mkdir -p "$output_directory"
package_file="${output_directory}/${PACKAGE_NAME}_${package_version}_all.deb"
dpkg-deb --build --root-owner-group "$staging_directory" "$package_file" >/dev/null
print_step "Built ${package_file}"
