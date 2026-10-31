# Prerequisites

## Runtime

The packages Spelunk needs at runtime are listed in `RUNTIME_PACKAGES` in
`scripts/install-dev-deps.sh`, the single source of truth for package lists.

## Development

Run `./scripts/install-dev-deps.sh` on Pop!_OS. It installs the runtime packages plus the
development tools listed in `DEVELOPMENT_PACKAGES` in the same script.

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
