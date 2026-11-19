#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Tests for packaging/changelog-to-debian.awk, which turns one section of CHANGELOG.md into the
# entry lines of a Debian changelog. The converter runs on a small sample file with awkward cases.
set -euo pipefail

# shellcheck source=lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

readonly CONVERTER="${REPO_ROOT}/packaging/changelog-to-debian.awk"
readonly LINE_WIDTH=40
readonly SAMPLE_CHANGELOG='# Changelog

## [Unreleased]

### Added

- Pending feature.

## [1.2.0] - 2026-01-01

### Added

- First thing that is long enough to need wrapping across more than one output line.
- Wrapped bullet that continues
  on the next source line.

### Fixed

- A fix.

## [1.1.0] - 2025-12-01

### Added

- Older thing.'

create_sample() {
  SANDBOX="$(mktemp -d)"
  trap 'rm -rf "$SANDBOX"' EXIT
  printf '%s\n' "$SAMPLE_CHANGELOG" >"${SANDBOX}/CHANGELOG.md"
}

convert() { awk -v marker="$1" -v width="$LINE_WIDTH" -f "$CONVERTER" "${SANDBOX}/CHANGELOG.md"; }

test_the_section_is_selected_by_its_heading() {
  create_sample
  local converted
  converted="$(convert '## [1.2.0]')"
  assert_contains "$converted" "First thing" "the requested section is converted"
  assert_not_contains "$converted" "Pending feature" "the section above is not included"
  assert_not_contains "$converted" "Older thing" "the section below is not included"
}

test_the_unreleased_section_can_be_selected() {
  create_sample
  assert_contains "$(convert '## [Unreleased]')" "Pending feature" "unreleased entries are converted"
}

test_bullets_are_prefixed_with_their_category() {
  create_sample
  local converted
  converted="$(convert '## [1.2.0]')"
  assert_contains "$converted" "  * Added: First thing" "added entries"
  assert_contains "$converted" "  * Fixed: A fix." "fixed entries"
}

test_long_bullets_are_wrapped_with_an_indented_continuation() {
  create_sample
  local line first_character_count=0
  while IFS= read -r line; do
    if ((${#line} > LINE_WIDTH)); then
      fail_test "line longer than ${LINE_WIDTH}: ${line}"
    fi
    if [[ "$line" == "  * "* ]]; then
      first_character_count=$((first_character_count + 1))
    elif [[ "$line" != "    "* ]]; then
      fail_test "continuation line is not indented by four spaces: '${line}'"
    fi
  done <<<"$(convert '## [1.2.0]')"
  assert_equals 3 "$first_character_count" "three bullets start an entry each"
}

test_a_bullet_wrapped_in_the_source_is_not_truncated() {
  create_sample
  local joined
  joined="$(convert '## [1.2.0]' | tr '\n' ' ' | tr -s ' ')"
  assert_contains "$joined" "continues on the next source line." "the second source line is kept"
}

test_the_last_section_of_the_file_is_flushed() {
  create_sample
  assert_contains "$(convert '## [1.1.0]')" "Older thing" "the final bullet is not lost"
}

test_an_unknown_section_gives_nothing() {
  create_sample
  assert_equals "" "$(convert '## [9.9.9]')" "no output for a missing section"
}

run_test test_the_section_is_selected_by_its_heading
run_test test_the_unreleased_section_can_be_selected
run_test test_bullets_are_prefixed_with_their_category
run_test test_long_bullets_are_wrapped_with_an_indented_continuation
run_test test_a_bullet_wrapped_in_the_source_is_not_truncated
run_test test_the_last_section_of_the_file_is_flushed
run_test test_an_unknown_section_gives_nothing
finish_tests
