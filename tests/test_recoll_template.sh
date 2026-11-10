#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verifies, with a real Recoll index, that data/recoll.conf.template keeps hidden entries,
# secret-bearing files and build output out of the index while real documents stay searchable.
# Needs recoll installed. Works in a temporary directory and never touches ~/.recoll.
set -euo pipefail

# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

readonly CONFIG_TEMPLATE="${REPO_ROOT}/data/recoll.conf.template"
readonly CANARY_WORD="spelunkcanary"
readonly SEARCHABLE_FILES=(notes.txt docs/guide.txt)
readonly EXCLUDED_FILES=(
  .env
  .hidden/secret.txt
  .ssh/config
  server.env
  cert.pem
  tls.key
  bundle.p12
  bundle.pfx
  backup.gpg
  armored.asc
  vault.kdbx
  id_rsa
  id_ecdsa
  keys/id_ed25519
  build/out.txt
  node_modules/pkg.txt
  Trash/old.txt
)

create_indexed_tree() {
  SANDBOX="$(mktemp -d)"
  trap 'rm -rf "$SANDBOX"' EXIT
  export HOME="${SANDBOX}/home"
  mkdir -p "$HOME"
  TREE="${SANDBOX}/tree"
  CONFIG_DIRECTORY="${SANDBOX}/recoll"

  local relative_path
  for relative_path in "${SEARCHABLE_FILES[@]}" "${EXCLUDED_FILES[@]}"; do
    mkdir -p "${TREE}/$(dirname "$relative_path")"
    printf '%s\n' "$CANARY_WORD" >"${TREE}/${relative_path}"
  done

  mkdir -p "$CONFIG_DIRECTORY"
  sed "s|^topdirs = .*|topdirs = ${TREE}|" "$CONFIG_TEMPLATE" >"${CONFIG_DIRECTORY}/recoll.conf"
  assert_contains "$(cat "${CONFIG_DIRECTORY}/recoll.conf")" "topdirs = ${TREE}" "test tree replaces the home directory"
}

indexed_relative_paths() {
  recollindex -c "$CONFIG_DIRECTORY" -z >"${SANDBOX}/index.log" 2>&1
  recollq -c "$CONFIG_DIRECTORY" -b "$CANARY_WORD" 2>/dev/null |
    sed "s|^file://${TREE}/||" |
    sort
}

test_only_real_documents_are_indexed() {
  create_indexed_tree
  local expected actual
  expected="$(printf '%s\n' "${SEARCHABLE_FILES[@]}" | sort)"
  actual="$(indexed_relative_paths)"
  assert_equals "$expected" "$actual" "only searchable documents are indexed"
}

run_test test_only_real_documents_are_indexed
finish_tests
