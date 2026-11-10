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
