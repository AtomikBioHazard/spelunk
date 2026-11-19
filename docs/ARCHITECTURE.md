# Architecture

## Installed layout

The repository tree is installed as-is, so every script finds its siblings relative to its own
resolved path and runs identically from a checkout and from the installed package.

| Repository | Installed |
|---|---|
| `bin/spelunk-setup.sh` | `/usr/lib/spelunk/bin/spelunk-setup.sh`, linked as `/usr/bin/spelunk-setup` |
| `lib/` | `/usr/lib/spelunk/lib/` |
| `data/` | `/usr/lib/spelunk/data/` |
| `plugin/` | `/usr/lib/pop-launcher/plugins/spelunk/` |
| `packaging/spelunk-setup.1` | `/usr/share/man/man1/spelunk-setup.1.gz` |
| `README.md`, `docs/PREREQUISITES.md` | `/usr/share/doc/spelunk/` |
| `LICENSE` | `/usr/share/doc/spelunk/copyright` |
| `CHANGELOG.md` | `/usr/share/doc/spelunk/changelog.gz`, converted to Debian format (see below) |

Scripts resolve symlinks (`readlink -f`) before locating `../lib` and `../data`. Keep that when
adding scripts, and update this table whenever the layout changes.

## Package build

`scripts/build-deb.sh` builds the `.deb`. What goes into the package is one dictionary,
`INSTALLED_FILES`, in that script: each line maps a path inside the package to its mode and its
source in the repository, so adding a file to the package is adding a line. The test
`tests/test_deb_package.sh` holds its own copy of the expected layout and fails on any difference.

- **Dependencies** come from `packaging/runtime-packages.txt`, the same list the installer uses.
- **Changelog:** Debian requires its own format, so `packaging/changelog-to-debian.awk` converts the
  section of `CHANGELOG.md` for the version being built (the Unreleased section when no dated
  section exists). `CHANGELOG.md` stays the only changelog.
- **Reproducible:** file timestamps and the changelog date are clamped to the date of the last
  commit, so the same commit always gives byte-identical packages.
- **Post-install script** (`packaging/postinst.sh`) only prints the next step. A system package
  must not change per-user state, so everything per user is done by `spelunk-setup`.
- **Quality gate:** lintian must report nothing, and no lintian override is allowed, in the same
  way no lint suppression is.

## Launcher plugin

`plugin/` is a pop-launcher plugin (`plugin.ron` plus `search_bridge.py`) that answers `in: <words>`
with Recoll results. It speaks pop-launcher's JSON-lines protocol on stdin and stdout:

| Request | Response |
|---|---|
| `{"Search": "in: hermes"}` | one `{"Append": {...}}` line per result (at most 8), then `"Finished"` |
| `{"Activate": <id>}` | opens the result with `xdg-open`, then `"Close"` |
| `"Exit"` | the plugin stops |

Every search ends with `Finished`, even when it fails, so the launcher is never left waiting. Any
other request is ignored. Queries shorter than two characters return no results.

The first version writes errors to `~/.cache/recoll-launcher.log` instead of showing them in the
launcher. Showing them is planned for v0.2.0 (issue #17), together with the module refactor.

`tests/test_plugin_protocol.sh` runs the real plugin against a fake `recoll` module, so the protocol
is tested without an index or a desktop.
