#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# spelunk-setup: one-time, per-user setup for the spelunk launcher plugin.
# Never overwrites an existing Recoll configuration or autostart entry.
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly SCRIPT_DIRECTORY
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIRECTORY}/../lib/common.sh"

readonly DATA_DIRECTORY="${SCRIPT_DIRECTORY}/../data"
readonly CONFIG_TEMPLATE_FILE="${DATA_DIRECTORY}/recoll.conf.template"
readonly AUTOSTART_TEMPLATE_FILE="${DATA_DIRECTORY}/recollindex.desktop"
readonly USER_HOME="${HOME:?HOME must be set}"
readonly RECOLL_DIRECTORY="${USER_HOME}/.recoll"
readonly RECOLL_CONFIG_FILE="${RECOLL_DIRECTORY}/recoll.conf"
readonly AUTOSTART_DIRECTORY="${USER_HOME}/.config/autostart"
readonly AUTOSTART_FILE="${AUTOSTART_DIRECTORY}/recollindex.desktop"
readonly STATE_DIRECTORY="${XDG_STATE_HOME:-${USER_HOME}/.local/state}/spelunk"
readonly INDEXER_LOG_FILE="${STATE_DIRECTORY}/indexer.log"
readonly INDEXER_STARTUP_CHECK_SECONDS=2
readonly PRIVATE_DIRECTORY_MODE=700
readonly PRIVATE_FILE_MODE=600
readonly HIDDEN_ENTRIES_EXCLUDED_REGEX='(=|[[:space:]])\.\*([[:space:]]|$)'
readonly LAUNCHER_RESTART_COMMAND="pkill -x cosmic-launcher; pkill -x pop-launcher"

should_enable_autostart=true
should_start_indexer=true

declare -A -r DISABLING_FLAGS=(
  ["--no-autostart"]=should_enable_autostart
  ["--no-indexer"]=should_start_indexer
)

print_usage() {
  cat <<'USAGE'
Usage: spelunk-setup [--no-autostart] [--no-indexer] [--help]

Prepares your account for spelunk: installs a Recoll configuration (only if you have none),
enables the real-time indexer at login and starts it.

  --no-autostart  do not start the indexer with your desktop session
  --no-indexer    do not start the indexer now
  --help          show this help
USAGE
}

parse_arguments() {
  local argument
  for argument in "$@"; do
    if [[ "$argument" == "--help" ]]; then
      print_usage
      exit 0
    fi
    if [[ -z "$argument" || -z "${DISABLING_FLAGS[$argument]:-}" ]]; then
      print_error "Unknown option: ${argument}"
      print_usage >&2
      exit 1
    fi
    printf -v "${DISABLING_FLAGS[$argument]}" '%s' false
  done
}

verify_not_root() {
  if is_root_user; then
    print_error "Run spelunk-setup as your normal user, not as root or with sudo."
    exit 1
  fi
}

verify_recoll_is_installed() {
  if ! command -v recollindex >/dev/null; then
    print_error "Recoll is not installed. Run: sudo apt install recoll python3-recoll"
    exit 1
  fi
  if ! python3 -c "from recoll import recoll" 2>/dev/null; then
    print_error "The Python Recoll module is missing. Run: sudo apt install python3-recoll"
    exit 1
  fi
}

ensure_private_directory() {
  local directory="$1"
  if [[ ! -d "$directory" ]]; then
    mkdir -p "$directory"
    chmod "$PRIVATE_DIRECTORY_MODE" "$directory"
    print_step "Created ${directory} (private to your user)"
    return 0
  fi
  if [[ "$(stat -c '%a' "$directory")" != "$PRIVATE_DIRECTORY_MODE" ]]; then
    chmod "$PRIVATE_DIRECTORY_MODE" "$directory"
    print_step "Restricted ${directory} to your user (mode ${PRIVATE_DIRECTORY_MODE})"
  fi
}

config_has_user_settings() {
  [[ -f "$RECOLL_CONFIG_FILE" ]] || return 1
  grep -qvE '^[[:space:]]*(#|$)' "$RECOLL_CONFIG_FILE"
}

read_skipped_names_settings() {
  sed -e ':join' -e '/\\$/{N;s/\\\n//;t join' -e '}' "$RECOLL_CONFIG_FILE" |
    grep -E '^[[:space:]]*skippedNames\+?[[:space:]]*=' || true
}

config_excludes_hidden_entries() {
  read_skipped_names_settings | grep -qE "$HIDDEN_ENTRIES_EXCLUDED_REGEX"
}

warn_if_hidden_entries_are_indexed() {
  if config_excludes_hidden_entries; then
    return 0
  fi
  print_warning "Your Recoll configuration does not exclude hidden files and directories (.*)."
  print_warning "They can hold SSH keys, tokens and .env files, and their text would appear in launcher results."
  print_warning "To fix it: add '.*' to skippedNames, stop the indexer (pkill -x recollindex), run recollindex -z, then run spelunk-setup again."
  print_warning "Details: Security section of docs/PREREQUISITES.md."
}

install_recoll_config() {
  if config_has_user_settings; then
    print_step "Keeping your existing Recoll configuration (${RECOLL_CONFIG_FILE})"
    warn_if_hidden_entries_are_indexed
    return 0
  fi
  install -m "$PRIVATE_FILE_MODE" "$CONFIG_TEMPLATE_FILE" "$RECOLL_CONFIG_FILE"
  print_step "Installed Recoll configuration template"
}

install_autostart_entry() {
  if [[ "$should_enable_autostart" != true ]]; then
    print_step "Skipping autostart entry (--no-autostart)"
    return 0
  fi
  if [[ -f "$AUTOSTART_FILE" ]]; then
    print_step "Keeping your existing autostart entry"
    return 0
  fi
  install -d "$AUTOSTART_DIRECTORY"
  install -m 644 "$AUTOSTART_TEMPLATE_FILE" "$AUTOSTART_FILE"
  print_step "Indexer will start with your desktop session"
}

indexer_is_running() {
  pgrep -u "$(id -u)" -x recollindex >/dev/null
}

read_indexer_command_line() {
  local exec_line
  exec_line="$(grep -m1 '^Exec=' "$AUTOSTART_TEMPLATE_FILE" || true)"
  if [[ -z "$exec_line" ]]; then
    print_error "No Exec line found in ${AUTOSTART_TEMPLATE_FILE}"
    exit 1
  fi
  printf '%s' "${exec_line#Exec=}"
}

start_indexer() {
  if [[ "$should_start_indexer" != true ]]; then
    print_step "Skipping indexer start (--no-indexer)"
    return 0
  fi
  if indexer_is_running; then
    print_step "Indexer is already running"
    return 0
  fi
  local command_line
  local -a indexer_command
  command_line="$(read_indexer_command_line)" || exit 1
  read -r -a indexer_command <<<"$command_line"
  ensure_private_directory "$STATE_DIRECTORY"
  setsid nohup "${indexer_command[@]}" >>"$INDEXER_LOG_FILE" 2>&1 &
  sleep "$INDEXER_STARTUP_CHECK_SECONDS"
  if ! indexer_is_running; then
    print_error "The indexer stopped right after starting. See ${INDEXER_LOG_FILE}"
    exit 1
  fi
  print_step "Indexer started in the background (the first index may take a while). Log: ${INDEXER_LOG_FILE}"
}

print_next_steps() {
  printf '\nAlmost done. Restart the launcher once:\n  %s\n' "$LAUNCHER_RESTART_COMMAND"
  printf 'Then press Super and type:  in: <words>\n'
}

parse_arguments "$@"
verify_not_root
verify_recoll_is_installed
ensure_private_directory "$RECOLL_DIRECTORY"
install_recoll_config
install_autostart_entry
start_indexer
print_next_steps
