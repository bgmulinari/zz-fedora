# Repository Guidelines

## Project Structure & Module Organization
`install.sh` is the main entrypoint; `bootstrap.sh` installs prerequisites and clones/updates the repo before handing off to `install.sh`. Shared Bash helpers live in `lib/`, distro adapters in `distros/`, and ordered install stages in `modules/` using the `NN-name.sh` pattern (`00-preflight.sh` through `90-doctor.sh`).

Data-driven inputs live under `choices/`, `packages/`, and `sources/`. Use `choices/<distro>/*.conf` for optional wizard choices, `packages/<distro>/.../*.pkgs` and `*.flatpaks` for manifests, `packages/actions/*.actions` for direct installer actions, and `sources/<distro>/**/*.source` for repo definitions. Distro base bundles are declared in `BASE_BUNDLE_IDS_<distro>` and are the non-optional desktop baseline installed before selected optional bundles. Base bundle IDs must not also appear in optional choice catalogs. Broader default selections live in `DEFAULT_BUNDLE_IDS_<distro>`; Fedora currently keeps this empty so unattended installs produce only the complete base desktop. Managed user config lives under `dotfiles/<stow-package>/`, while `templates/` is reserved for rendered files that are not shipped through Stow. Regression checks live in `tests/`.

The installed `zz` launcher is a post-install utility only. Do not add install, wizard, plan, check, or repair wrappers under `bin/zz.d/`; setup stays under `./install.sh` and `./bootstrap.sh`. Current `zz` commands are `doctor`, `logs`, `debug`, `first-run`, `defaults`, `dotnet`, `update`, and `commands --json`.

## Build, Test, and Development Commands
Run the installer locally with `./install.sh wizard` for the interactive flow or `./install.sh install --yes --dry-run` to inspect the generated base plan safely. Use `./install.sh print-plan --distro fedora --select browser=brave --dry-run` when validating optional planner changes without applying them. Use `zz doctor`, `zz logs --tail`, `zz debug`, `zz first-run`, `zz defaults`, `zz dotnet devcert status`, and `zz update all` for post-install operations.

Run `./tests/smoke.sh` before opening a PR. The suite uses Bats and fails fast with an install hint when `bats` is missing. Smoke covers shell syntax, manifest parsing, catalog validation, distro detection, fast planner behavior, and CLI smoke checks. Set `ZZ_TEST_LINT=1` to include `shellcheck` in smoke. Run `./tests/full.sh` for full regression, `./tests/full.sh --timings` for per-suite durations during the full gate, and `./tests/profile.sh` for the non-gating timing helper. For targeted work, run individual Bats files such as `bats tests/planner.bats` or compatibility shims such as `./tests/idempotency.sh`.

## Coding Style & Naming Conventions
Write Bash with `#!/usr/bin/env bash` and `set -Eeuo pipefail`. Follow the existing style: lowercase function names (`build_plan_from_selections`), uppercase globals/environment flags (`DRY_RUN`, `TARGET_HOME`), and quote variable expansions. Keep modules thin and push reusable logic into `lib/`.

Manifest and choice files are part of the API. Preserve existing suffixes (`.pkgs`, `.flatpaks`, `.actions`, `.source`, `.conf`) and keep `choices/*.conf` as tab-separated records with five fields: `id`, `label`, `default`, `bundle_ids`, and `description`. Source descriptors must include trust metadata: `SOURCE_GPG_POLICY`, `SOURCE_BOOTSTRAP_EXCEPTION`, `SOURCE_REQUIRED`, and `SOURCE_REASON`.

## Testing Guidelines
Add or update a focused Bats suite in `tests/` for planner, parser, CLI, first-run, source trust, verification, or idempotency changes. Prefer fast, non-interactive assertions that run without root access or network calls. Source shared helpers from `tests/helpers/` and use in-process planner/module calls instead of repeated `install.sh` subprocesses unless the behavior under test is the CLI boundary. New tests should fail on regressions without needing root access or network calls. If you change base bundle behavior, update tests that prove base bundles are always planned for every supported distro, installed before optional bundles, verified when required, and not blocked by optional package failures. If you change first-login/session-sensitive work, cover marker creation/removal and idempotency.

## Commit & Pull Request Guidelines
Recent history uses short, imperative commit subjects, for example `Implement GTK-oriented Niri Noctalia bootstrapper with gum wizard`. Keep the first line concise and descriptive.

PRs should state the affected distro(s), summarize any new sources/packages/choices, and list the commands you ran, usually `./tests/smoke.sh`. Include screenshots only when changing user-facing TUI behavior or generated desktop/session assets.

## Agent Notes
When you need upstream reference code or docs, prefer the read-only repos under `/files/Dev/ref_repos` instead of package decompilation or ad hoc reverse engineering.
Keep repository-facing names and documentation generic. Do not introduce third-party project branding into bundle IDs, manifest filenames, stow package names, or docs unless the user explicitly asks for that.
For Noctalia v5 work, read and update `docs/noctalia-v5-integration-status.md`; it is the living checkpoint for the current alpha integration, package pinning, known issues, and next comparison steps.
This installer is under active development. Do not add migration logic, backward-compatibility shims, existing-install preservation work, or regression guards for prior behavior unless the user explicitly asks for them.
Package manifests and installer wiring are expected to churn while the desktop baseline is being explored. When changing or removing packages, actions, bundle IDs, installer strings, manifest filenames, or other implementation identifiers, do not add or keep tests whose only purpose is to assert that the old identifier stays absent. Prefer assertions for the new desired behavior, and only test negative selection when it protects intentional planner behavior or an explicitly requested constraint.
Base package/action manifests should stay explainable through the generated `base-rationale.tsv`; when adding base work, make sure the owning bundle description gives a clear reason. Keep session-sensitive GUI defaults in the first-run path when they depend on a user session, and keep required base actions idempotent with an explicit verification check.
