# Converts one release section of a Keep a Changelog file (CHANGELOG.md) into the bullet lines of a
# Debian changelog entry. Used by scripts/build-deb.sh, so CHANGELOG.md stays the only changelog.
#
# Variables: marker  the section heading to extract, for example "## [Unreleased]"
#            width   maximum line width of the output
#
# "### Added" followed by "- Something" becomes "  * Added: Something", wrapped to the width.
# A bullet that continues on indented following lines is joined into one entry.

function flush(    words, count, position, line) {
  if (pending == "") {
    return
  }
  count = split(pending, words, " ")
  line = "  *"
  for (position = 1; position <= count; position++) {
    if (length(line) + 1 + length(words[position]) > width) {
      print line
      line = "   "
    }
    line = line " " words[position]
  }
  print line
  pending = ""
}

index($0, marker) == 1 { in_section = 1; next }
in_section && /^## / { flush(); exit }
in_section && /^### / { flush(); category = substr($0, 5); next }
in_section && /^- / { flush(); pending = category ": " substr($0, 3); next }
in_section && /^[ \t]+[^ \t]/ && pending != "" { pending = pending " " $0; next }
in_section && /^[ \t]*$/ { flush() }
END { flush() }
