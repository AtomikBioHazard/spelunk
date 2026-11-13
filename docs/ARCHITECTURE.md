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

Scripts resolve symlinks (`readlink -f`) before locating `../lib` and `../data`. Keep that when
adding scripts, and update this table whenever the layout changes.

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
