#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Protocol tests for plugin/search_bridge.py. The real plugin runs against a fake `recoll` module and
# a stubbed xdg-open, inside a temporary home, so no real index or desktop is involved.
set -euo pipefail

# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

readonly PLUGIN_SCRIPT="${REPO_ROOT}/plugin/search_bridge.py"
readonly PLUGIN_MANIFEST="${REPO_ROOT}/plugin/plugin.ron"
readonly MAX_DESCRIPTION_LENGTH=120
readonly MAX_RESULTS=8
readonly DOCUMENTS_AVAILABLE=12
readonly LONG_ABSTRACT_LENGTH=300
readonly WAIT_ATTEMPTS=30
readonly WAIT_INTERVAL_SECONDS=0.1
readonly SETTLE_SECONDS=0.5
readonly DOCUMENTS_JSON='{
  "hermes": [
    {"url": "file:///home/user/My%20Notes.md", "filename": "My Notes.md", "mimetype": "text/markdown",
     "abstract": "<b>hermes</b> setup [L. 12]   first time"},
    {"url": "file:///home/user/run.sh", "filename": "", "mimetype": "", "abstract": ""}
  ],
  "other": [
    {"url": "file:///home/user/other.txt", "filename": "other.txt", "mimetype": "text/plain", "abstract": "x"}
  ]
}'

json_get() { python3 "${REPO_ROOT}/tests/lib/json_get.py" "$@"; }

write_stub() {
  local stub_path="${SANDBOX}/stubs/$1"
  {
    printf '#!/bin/sh\n'
    cat
  } >"$stub_path"
  chmod +x "$stub_path"
}

write_fake_recoll_module() {
  : >"${SANDBOX}/fake/recoll/__init__.py"
  cat >"${SANDBOX}/fake/recoll/recoll.py" <<'FAKE'
import json
import os


class Document:
    def __init__(self, url, filename, mimetype, abstract):
        self.url = url
        self.filename = filename
        self.mimetype = mimetype
        self.abstract = abstract


class Query:
    def __init__(self):
        self.documents = []

    def execute(self, text):
        with open(os.environ["FAKE_RECOLL_CALLS"], "a") as calls:
            calls.write(text + "\n")
        if os.environ.get("FAKE_RECOLL_FAILS"):
            raise RuntimeError("simulated search failure")
        catalogue = json.loads(os.environ.get("FAKE_RECOLL_DOCUMENTS", "{}"))
        self.documents = [Document(**entry) for entry in catalogue.get(text, [])]

    def fetchmany(self, count):
        return self.documents[:count]


class Database:
    def query(self):
        return Query()

    def makeDocAbstract(self, document, query):
        return document.abstract


def connect():
    if os.environ.get("FAKE_RECOLL_CONNECT_FAILS"):
        raise RuntimeError("simulated missing index")
    return Database()
FAKE
}

create_sandbox() {
  SANDBOX="$(mktemp -d)"
  trap 'rm -rf "$SANDBOX"' EXIT
  mkdir -p "${SANDBOX}/stubs" "${SANDBOX}/fake/recoll" "${SANDBOX}/home/.cache"
  export HOME="${SANDBOX}/home"
  export FAKE_RECOLL_CALLS="${SANDBOX}/recoll-calls"
  export FAKE_RECOLL_DOCUMENTS="$DOCUMENTS_JSON"
  PLUGIN_LOG="${HOME}/.cache/recoll-launcher.log"
  XDG_CALLS="${SANDBOX}/xdg-calls"
  write_fake_recoll_module
  write_stub xdg-open <<STUB
echo "\$#:\$1" >> "${XDG_CALLS}"
STUB
}

run_plugin() {
  local input
  input="$(printf '%s\n' "$@")"
  plugin_exit_code=0
  plugin_output="$(PYTHONPATH="${SANDBOX}/fake" PATH="${SANDBOX}/stubs:${PATH}" python3 "$PLUGIN_SCRIPT" <<<"$input" 2>"${SANDBOX}/plugin.stderr")" || plugin_exit_code=$?
}

output_line() { sed -n "${1}p" <<<"$plugin_output"; }

output_line_count() {
  if [[ -z "$plugin_output" ]]; then
    echo 0
    return 0
  fi
  printf '%s\n' "$plugin_output" | wc -l
}

wait_for_file() {
  local path="$1" attempt
  for ((attempt = 0; attempt < WAIT_ATTEMPTS; attempt++)); do
    if [[ -e "$path" ]]; then
      return 0
    fi
    sleep "$WAIT_INTERVAL_SECONDS"
  done
  return 1
}

test_a_search_returns_results_then_finishes() {
  create_sandbox
  run_plugin '{"Search": "in: hermes"}'
  assert_equals 0 "$plugin_exit_code" "plugin exits cleanly at the end of its input"
  assert_equals 3 "$(output_line_count)" "two results plus Finished"
  local first second
  first="$(output_line 1)"
  second="$(output_line 2)"
  assert_equals 0 "$(json_get "$first" Append id)" "first result id"
  assert_equals "My Notes.md" "$(json_get "$first" Append name)" "first result name"
  assert_equals "hermes setup first time" "$(json_get "$first" Append description)" "tags and line numbers are stripped from the snippet"
  assert_equals '{"Mime": "text/markdown"}' "$(json_get "$first" Append icon)" "icon follows the mime type"
  assert_equals 1 "$(json_get "$second" Append id)" "second result id"
  assert_equals "run.sh" "$(json_get "$second" Append name)" "name falls back to the file name"
  assert_equals '{"Name": "text-x-generic"}' "$(json_get "$second" Append icon)" "icon falls back to a generic one"
  assert_equals '"Finished"' "$(output_line 3)" "the search ends with Finished"
  assert_equals "hermes" "$(cat "$FAKE_RECOLL_CALLS")" "the in: prefix is removed before searching"
}

test_the_prefix_is_matched_case_insensitively() {
  create_sandbox
  run_plugin '{"Search": "IN: hermes"}'
  assert_equals "hermes" "$(cat "$FAKE_RECOLL_CALLS")" "uppercase prefix is removed"
}

test_long_snippets_are_shortened_with_an_ellipsis() {
  create_sandbox
  local long_abstract
  long_abstract="$(head -c "$LONG_ABSTRACT_LENGTH" </dev/zero | tr '\0' 'a')"
  export FAKE_RECOLL_DOCUMENTS="{\"hermes\": [{\"url\": \"file:///x/a.txt\", \"filename\": \"a.txt\", \"mimetype\": \"text/plain\", \"abstract\": \"${long_abstract}\"}]}"
  run_plugin '{"Search": "in: hermes"}'
  local description
  description="$(json_get "$(output_line 1)" Append description)"
  assert_equals "..." "${description: -3}" "snippet ends with an ellipsis"
  if ((${#description} > MAX_DESCRIPTION_LENGTH)); then
    fail_test "snippet is ${#description} characters, limit is ${MAX_DESCRIPTION_LENGTH}"
  fi
}

test_results_are_capped() {
  create_sandbox
  local documents="" index
  for ((index = 0; index < DOCUMENTS_AVAILABLE; index++)); do
    documents+="{\"url\": \"file:///x/${index}.txt\", \"filename\": \"${index}.txt\", \"mimetype\": \"text/plain\", \"abstract\": \"a\"},"
  done
  export FAKE_RECOLL_DOCUMENTS="{\"hermes\": [${documents%,}]}"
  run_plugin '{"Search": "in: hermes"}'
  assert_equals "$((MAX_RESULTS + 1))" "$(output_line_count)" "at most ${MAX_RESULTS} results plus Finished"
}

test_a_document_without_any_name_is_still_listed() {
  create_sandbox
  export FAKE_RECOLL_DOCUMENTS='{"hermes": [{"url": "file:///", "filename": "", "mimetype": "", "abstract": ""}]}'
  run_plugin '{"Search": "in: hermes"}'
  assert_equals "Unnamed document" "$(json_get "$(output_line 1)" Append name)" "a placeholder name is shown"
}

test_a_single_character_query_returns_nothing_but_finishes() {
  create_sandbox
  run_plugin '{"Search": "in: a"}'
  assert_equals '"Finished"' "$plugin_output" "only Finished is sent"
  assert_file_missing "$FAKE_RECOLL_CALLS" "Recoll is not queried for one character"
}

test_a_failing_search_still_finishes_and_is_logged() {
  create_sandbox
  export FAKE_RECOLL_FAILS=1
  run_plugin '{"Search": "in: hermes"}'
  assert_equals '"Finished"' "$plugin_output" "the launcher is never left waiting"
  assert_contains "$(cat "$PLUGIN_LOG")" "search error" "the failure is logged"
}

test_activating_a_result_opens_the_decoded_path_and_closes() {
  create_sandbox
  run_plugin '{"Search": "in: hermes"}' '{"Activate": 0}'
  assert_equals '"Close"' "$(output_line 4)" "the launcher is told to close"
  wait_for_file "$XDG_CALLS" || fail_test "xdg-open was never called"
  assert_equals "1:/home/user/My Notes.md" "$(cat "$XDG_CALLS")" "one argument, percent-decoded"
}

test_activating_an_unknown_id_only_closes() {
  create_sandbox
  run_plugin '{"Activate": 99}'
  assert_equals '"Close"' "$plugin_output" "Close is still sent"
  sleep "$SETTLE_SECONDS"
  assert_file_missing "$XDG_CALLS" "nothing is opened"
}

test_a_new_search_replaces_the_previous_results() {
  create_sandbox
  run_plugin '{"Search": "in: hermes"}' '{"Search": "in: other"}' '{"Activate": 1}' '{"Activate": 0}'
  wait_for_file "$XDG_CALLS" || fail_test "xdg-open was never called"
  sleep "$SETTLE_SECONDS"
  assert_equals "1:/home/user/other.txt" "$(cat "$XDG_CALLS")" "only the newest result 0 is opened; id 1 no longer exists"
}

test_malformed_input_is_ignored_and_logged() {
  create_sandbox
  run_plugin 'not json' '{"Search": "in: hermes"}'
  assert_equals 3 "$(output_line_count)" "the plugin keeps working"
  assert_contains "$(cat "$PLUGIN_LOG")" "bad json" "the bad line is logged"
}

test_requests_the_plugin_does_not_use_are_ignored() {
  create_sandbox
  run_plugin '"Interrupt"' '{"Quit": 1}' '{"Search": "in: hermes"}'
  assert_equals 3 "$(output_line_count)" "no extra output for unused requests"
}

test_an_exit_request_stops_the_plugin() {
  create_sandbox
  run_plugin '"Exit"' '{"Search": "in: hermes"}'
  assert_equals 0 "$plugin_exit_code" "clean exit"
  assert_equals 0 "$(output_line_count)" "nothing is processed after Exit"
}

test_a_missing_index_stops_the_plugin_and_is_logged() {
  create_sandbox
  export FAKE_RECOLL_CONNECT_FAILS=1
  run_plugin '{"Search": "in: hermes"}'
  assert_equals 1 "$plugin_exit_code" "the plugin exits with an error"
  assert_equals 0 "$(output_line_count)" "no output"
  assert_contains "$(cat "$PLUGIN_LOG")" "cannot open Recoll index" "the reason is logged"
}

test_the_manifest_matches_what_pop_launcher_requires() {
  local manifest
  manifest="$(cat "$PLUGIN_MANIFEST")"
  assert_contains "$manifest" 'icon: Name("' "the icon is an enum value, not a bare string"
  assert_contains "$manifest" "long_lived: true" "the plugin stays running between searches"
  assert_contains "$manifest" 'regex: "^in:' "the in: trigger is declared"
  assert_contains "$manifest" 'bin: (path: "search_bridge.py")' "the entry point is declared"
  if [[ ! -x "${REPO_ROOT}/plugin/search_bridge.py" ]]; then
    fail_test "the entry point is not executable"
  fi
}

run_test test_a_search_returns_results_then_finishes
run_test test_the_prefix_is_matched_case_insensitively
run_test test_long_snippets_are_shortened_with_an_ellipsis
run_test test_results_are_capped
run_test test_a_document_without_any_name_is_still_listed
run_test test_a_single_character_query_returns_nothing_but_finishes
run_test test_a_failing_search_still_finishes_and_is_logged
run_test test_activating_a_result_opens_the_decoded_path_and_closes
run_test test_activating_an_unknown_id_only_closes
run_test test_a_new_search_replaces_the_previous_results
run_test test_malformed_input_is_ignored_and_logged
run_test test_requests_the_plugin_does_not_use_are_ignored
run_test test_an_exit_request_stops_the_plugin
run_test test_a_missing_index_stops_the_plugin_and_is_logged
run_test test_the_manifest_matches_what_pop_launcher_requires
finish_tests
