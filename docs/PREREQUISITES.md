# Prerequisites

## Runtime

The packages Spelunk needs at runtime are listed in `packaging/runtime-packages.txt`, the single
source of truth: the installer installs them and the package declares them as its dependencies.

## Development

Run `./scripts/install-dev-deps.sh` on Pop!_OS. It installs the runtime packages plus the
development tools listed in `DEVELOPMENT_PACKAGES` in the same script.

## Building the package

```bash
./scripts/build-deb.sh
```

builds `dist/spelunk_<version>_all.deb` from the `VERSION` file. Options: `--version-suffix` (for
example `~dev.abc1234`, which CI uses) and `--output-directory`. The build is reproducible: file
timestamps are clamped to the date of the last commit, so the same commit always gives the same
package.

Install it, then finish the setup as your normal user:

```bash
sudo apt install ./dist/spelunk_*_all.deb
spelunk-setup
```

If you used an earlier development copy of the plugin, remove it first, or every result appears
twice: `rm -rf ~/.local/share/pop-launcher/plugins/recoll-inside-search`

## Recoll configuration

After installing the package, run `spelunk-setup` once, as your normal user (never as root):

```bash
spelunk-setup
```

Paths such as `data/recoll.conf.template` are relative to the repository. Once the package is
installed, the same files are under `/usr/lib/spelunk/`, for example
`/usr/lib/spelunk/data/recoll.conf.template`.

It installs the Recoll configuration from `data/recoll.conf.template`, but only when you have no
Recoll settings yet; an existing configuration is never overwritten. It also:

- warns when your existing configuration does not exclude hidden files and directories (see
  Security);
- makes `~/.recoll` private to your user (mode 700);
- enables the real-time indexer at login and starts it, logging to
  `~/.local/state/spelunk/indexer.log`.

Options: `--no-autostart`, `--no-indexer`, `--help`.

The autostart entry runs `recollindex -w 60 -m -x`. Without `-x`, Recoll's real-time monitor exits
on its own when it cannot see an X11 session; on Pop!_OS 24.04 it exited within seconds in tests.

`data/recoll.conf.template` is the single source of truth for what is indexed: the home directory,
minus hidden entries, build and dependency folders, and files that usually hold secrets.
`skippedPaths` is empty on purpose, so external drives under `/media` are indexed.

## Manual equivalent

1. Run `recoll` once and copy the exclusions from `data/recoll.conf.template` into
   Preferences → Index configuration.
2. Open Preferences → Indexing schedule → Real time indexing, then enable both
   "Start indexing daemon with my desktop session" and "also start indexing daemon right now".

## Security

Recoll stores the extracted text of every indexed document in `~/.recoll/xapiandb`, and Spelunk
shows matching text snippets in the launcher. Anything indexed can therefore appear on screen
(screen sharing, shoulder surfing) and is readable from the index itself.

- Keep the exclusions from `data/recoll.conf.template`. Tested against a real index, stock Recoll
  indexes `.env` files, `.asc` files, KeePass files and extensionless private keys such as
  `id_rsa`, plus everything inside hidden directories.
- Exclusions match file names only: a private key saved as `backup_key` is still indexed. Keep
  secrets out of indexed directories.
- Keep the index private: `chmod 700 ~/.recoll` (`spelunk-setup` does this).
- After changing exclusions, rebuild the index so already-indexed secrets are purged. While the
  real-time indexer runs, `recollindex -z` fails ("Can't become exclusive indexer"), so stop it
  first, rebuild (this can take a long time on a large home directory), then start it again:

  ```bash
  pkill -x recollindex
  recollindex -z
  spelunk-setup
  ```

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

## Tests

`tests/run.sh` runs the shell tests: the installer, `spelunk-setup`, the plugin protocol, the Recoll
template against a real index, the changelog converter, and the built `.deb` (contents, modes,
metadata, reproducibility, the installed layout and lintian). They need Recoll and lintian installed
(`./scripts/install-dev-deps.sh`) and never touch your real `~/.recoll`: every test works in a
temporary home with stubbed tools.

The Test workflow runs them on every pull request and push. The Package workflow builds the `.deb`
with a `~dev.<commit>` version suffix, checks it with lintian and uploads it as an artifact.
