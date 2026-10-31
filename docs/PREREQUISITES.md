# Prerequisites

## Runtime

The packages Spelunk needs at runtime are listed in `RUNTIME_PACKAGES` in
`scripts/install-dev-deps.sh`, the single source of truth for package lists.

## Development

Run `./scripts/install-dev-deps.sh` on Pop!_OS. It installs the runtime packages plus the
development tools listed in `DEVELOPMENT_PACKAGES` in the same script.

## Recoll configuration

Once the Spelunk package is installed, `spelunk-setup` applies this configuration automatically;
until then, follow the manual steps below.

- Index `~` (home directory).
- Exclude every hidden file and directory (`.*`), plus `Trash build dist node_modules venv`. This
  adds to Recoll's defaults, which already skip `.cache`, `.git`, `__pycache__`, etc.
- Exclude files that usually hold secrets:
  `*.env *.pem *.key *.p12 *.pfx *.gpg *.asc *.kdbx id_rsa id_ed25519 id_ecdsa`
- `skippedPaths` is empty on purpose, so external drives under `/media` are indexed.
- The real-time indexing daemon starts with the desktop session: `recollindex -w 60 -m`

## Manual equivalent

1. Run `recoll` once and set the exclusions above under Preferences → Index configuration.
2. Open Preferences → Indexing schedule → Real time indexing, then enable both
   "Start indexing daemon with my desktop session" and "also start indexing daemon right now".

## Security

Recoll stores the extracted text of every indexed document in `~/.recoll/xapiandb`, and Spelunk
shows matching text snippets in the launcher. Anything indexed can therefore appear on screen
(screen sharing, shoulder surfing) and is readable from the index itself.

- Keep the exclusions above. A default index of a home directory includes SSH private keys,
  `.env` files, credential stores and browser profiles.
- Exclusions match file names only and cannot catch every secret. Keep secrets out of indexed
  directories.
- Keep the index private: `chmod 700 ~/.recoll`.
- After changing exclusions, rebuild the index so already-indexed secrets are purged:
  `recollindex -z`

## Linting and checks

All checks run through [pre-commit](https://pre-commit.com/), so your machine and CI use the same
pinned tool versions. `./scripts/install-dev-deps.sh` installs `pre-commit`. Then, once per clone:

```bash
pre-commit install
```

Run every check on the whole repository at any time:

```bash
pre-commit run --all-files
```

What is checked:

- Python: ruff lint and format.
- Shell: ShellCheck and shfmt (settings in `.shellcheckrc` and `.editorconfig`).
- GitHub workflows (actionlint) and the Dependabot configuration (schema).
- File hygiene: whitespace, line endings, YAML and TOML validity, executable bits, large files.
- Secrets: private-key detection, plus `.gitignore` patterns for common secret files.
- Policy: no direct commits to `main`, `develop` or `qa`; an SPDX license identifier in every shell
  and Python file; no lint suppressions (`noqa`, `shellcheck disable`, per-file ignores).
- Commit messages: Conventional Commits, single line, no body.

The Lint workflow re-runs the same checks on every pull request and push; `--no-verify` only skips
them locally. Hook and action versions are updated by Dependabot after a 14-day cooldown.
