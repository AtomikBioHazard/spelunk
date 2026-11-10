# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added

- Development dependency installer (`scripts/install-dev-deps.sh`) and prerequisites documentation.
- Linting and policy checks through pre-commit (ruff, ShellCheck, shfmt, actionlint, file hygiene, SPDX headers, no lint suppressions, commit message rules), enforced locally and by the Lint workflow in CI.
- Shared shell helpers in `lib/common.sh`.
- Dependabot configuration for GitHub Actions and pre-commit hooks, with a 14-day cooldown.
- `spelunk-setup` command and Recoll configuration template.
- Shell test suite (`tests/run.sh`) and a Test workflow in CI.
- Architecture document describing the installed layout.

### Security

- Prerequisites document the secret exclusions and index protections required before indexing a home directory.
- Private-key detection hook and gitignore patterns for common secret files.
- Lint workflow pinned to a commit SHA and limited to a read-only token.
- `spelunk-setup` refuses to run as root, keeps its directories private and warns when an existing Recoll configuration would index hidden files.
- The Recoll template excludes hidden entries and secret-bearing files, verified against a real index.
