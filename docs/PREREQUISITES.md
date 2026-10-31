# Prerequisites

## Runtime (installed automatically by the .deb)

`pop-launcher`, `recoll`, `python3-recoll`, `python3`, `xdg-utils`

## Development

Run `./scripts/install-dev-deps.sh`. It installs the runtime packages plus
`python3-pip`, `python3-full`, `lintian` and `shellcheck`.

## Recoll configuration

Done automatically by `spelunk-setup` once the package is installed. The resulting setup is:

- Index `~` (home directory). Added exclusions, on top of Recoll's defaults (which already skip
  `.cache`, `.git`, `__pycache__`, etc.): `.local .npm .nv .nvm .pnpm .venv .virtualvenvs Trash
  build dist node_modules venv`
- `skippedPaths` is empty on purpose, so external drives under `/media` are indexed.
- The real-time indexing daemon starts with the desktop session: `recollindex -w 60 -m`

## Manual equivalent

1. Run `recoll` once and set the exclusions above under Preferences → Index configuration.
2. Open Preferences → Indexing schedule → Real time indexing, then enable both
   "Start indexing daemon with my desktop session" and "also start indexing daemon right now".
