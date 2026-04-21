# Repository Guidelines

## Project Structure & Module Organization
`install.sh` is the main entrypoint; `bootstrap.sh` installs prerequisites and clones/updates the repo before handing off to `install.sh`. Shared Bash helpers live in `lib/`, distro adapters in `distros/`, and ordered install stages in `modules/` using the `NN-name.sh` pattern (`00-preflight.sh` through `90-doctor.sh`).

Data-driven inputs live under `choices/`, `packages/`, and `sources/`. Use `choices/<distro>/*.conf` for wizard options, `packages/<distro>/.../*.pkgs` and `*.flatpaks` for manifests, and `sources/<distro>/**/*.source` for repo definitions. Managed user config lives under `dotfiles/<stow-package>/`, while `templates/` is reserved for rendered files that are not shipped through Stow. Regression checks live in `tests/`.

## Build, Test, and Development Commands
Run the installer locally with `./install.sh wizard` for the interactive flow or `./install.sh install --yes --dry-run` to inspect the generated plan safely. Use `./install.sh print-plan --distro fedora --select browser=firefox --dry-run` when validating planner changes without applying them.

Run `./tests/smoke.sh` before opening a PR. It covers shell syntax, manifest parsing, distro detection, planner behavior, idempotency helpers, and runs `shellcheck` when available. For targeted work, run individual scripts such as `./tests/planner.sh` or `./tests/idempotency.sh`.

## Coding Style & Naming Conventions
Write Bash with `#!/usr/bin/env bash` and `set -Eeuo pipefail`. Follow the existing style: lowercase function names (`build_plan_from_selections`), uppercase globals/environment flags (`DRY_RUN`, `TARGET_HOME`), and quote variable expansions. Keep modules thin and push reusable logic into `lib/`.

Manifest and choice files are part of the API. Preserve existing suffixes (`.pkgs`, `.flatpaks`, `.source`, `.conf`) and keep `choices/*.conf` as tab-separated records with six fields.

## Testing Guidelines
Add or update a focused script in `tests/` for planner, parser, or idempotency changes. Prefer fast, non-interactive assertions that run with plain Bash. New tests should fail on regressions without needing root access or network calls.

## Commit & Pull Request Guidelines
Recent history uses short, imperative commit subjects, for example `Implement KDE-focused Niri Noctalia bootstrapper with gum wizard`. Keep the first line concise and descriptive.

PRs should state the affected distro(s), summarize any new sources/packages/choices, and list the commands you ran, usually `./tests/smoke.sh`. Include screenshots only when changing user-facing TUI behavior or generated desktop/session assets.

## Agent Notes
When you need upstream reference code or docs, prefer the read-only repos under `/files/Dev/ref_repos` instead of package decompilation or ad hoc reverse engineering.
