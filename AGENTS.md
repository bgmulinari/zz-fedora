# Repository instructions

## Scope and invariants

- This repository is a Fedora post-install bootstrapper for the Niri and Noctalia desktop.
- `install.sh` owns setup. `bootstrap.sh` only installs prerequisites, clones or updates the repository, and hands off to `install.sh`.
- The installed `zz` launcher is for post-install operations. Do not add install, wizard, plan, check, or repair wrappers under `bin/zz.d/`. Discover its supported commands with `./bin/zz commands --json`.
- The installer is under active development. Do not add migrations, compatibility shims, existing-install preservation, or regression guards for previous behavior unless the user explicitly requests them.
- Keep new repository-facing identifiers and documentation generic. Do not introduce third-party branding into bundle IDs, manifest names, Stow package names, or docs unless the user explicitly requests it.

## Put changes in the right place

- Keep ordered install orchestration in `modules/NN-name.sh`; put reusable Bash logic in `lib/` and keep modules thin.
- Treat `choices/`, `bundles/`, `packages/`, and `sources/` as the data-driven installer API.
- Put optional wizard choices in `choices/*.conf`, bundle composition in `bundles/**/*.bundle`, package lists in `packages/**/*.pkgs` or `*.flatpaks`, direct installer actions in `packages/actions/*.actions`, and repository definitions in `sources/**/*.source`.
- Put portable user configuration in `dotfiles/<stow-package>/`. Reserve `templates/` for files rendered by the installer rather than deployed through Stow.
- Put regression tests in `tests/`; share Bash test helpers through `tests/helpers/` and put non-Bash test harnesses in `tests/support/`.
- When upstream reference code or docs are needed, prefer the read-only checkouts under `/files/Dev/ref_repos` when available instead of package decompilation or ad hoc reverse engineering.

## Preserve manifest contracts

- Keep each `choices/*.conf` row tab-separated with exactly five fields: `id`, `label`, `default`, `bundle_ids`, and `description`.
- Preserve manifest suffixes: `.conf`, `.bundle`, `.pkgs`, `.flatpaks`, `.actions`, and `.source`.
- Base bundle membership is declared in the bundle descriptor: `BUNDLE_BASE=1` with a unique numeric `BUNDLE_BASE_ORDER`, plus optional `BUNDLE_BASE_EARLY=1` and `BUNDLE_MINIMAL_DESKTOP_SKIP=1`. Every descriptor under `bundles/base/` must declare `BUNDLE_BASE=1`. Base bundles are planned before optional bundles and must not appear in an optional choice catalog. Use `DEFAULT_BUNDLE_IDS` only for broader defaults outside the choice catalogs.
- The default install selects every non-browser catalog choice and only Firefox from the browser catalog. Express optional catalog defaults through the third field of each choice row.
- Give every base-owning bundle a useful `BUNDLE_DESCRIPTION`; base package and action work must remain explainable in the generated `base-rationale.tsv`.
- Source descriptors must declare trust metadata with `SOURCE_GPG_POLICY`, `SOURCE_BOOTSTRAP_EXCEPTION`, `SOURCE_REQUIRED`, and `SOURCE_REASON`.
- Bundles reference sources only through the comma-separated `BUNDLE_SOURCE_IDS` key; unknown descriptor keys fail catalog validation. Dedicated `source-*` base bundles own base-required sources; optional bundles declare their own source needs inline via `BUNDLE_SOURCE_IDS` (source enablement is idempotent, so overlap with base sources is fine).

## Bash and installer behavior

- Use `#!/usr/bin/env bash` and `set -Eeuo pipefail` in Bash entrypoints.
- Follow the existing naming style: lowercase function names, uppercase globals and environment flags, and quoted variable expansions.
- Keep required base actions idempotent and give them explicit verification checks.
- Keep GUI defaults that require a logged-in user session in the first-run path rather than the system install path.
- For Noctalia changes, keep portable settings in the managed dotfiles and do not commit generated, monitor-specific, or hardware-specific state from `~/.local/state/noctalia/`.

## Fedora installer ISO

- Treat `iso/zz-fedora.ks`, `iso/anaconda-addon/`, `iso/anaconda-addon-data/`, `scripts/build-fedora-installer-iso.sh`, `scripts/lib/iso-common.sh`, and `scripts/test-fedora-installer-vm.sh` as one installer path. Keep `docs/fedora-installer-iso.md` synchronized with behavior and CLI changes.
- Keep the ISO online: it embeds the current checkout and installer integration, not package mirrors. Stage only Git-tracked runtime files; never include `.git`, tests, logs, caches, ignored files, or unrelated untracked files.
- Keep disk layout, locale, timezone, hostname, credentials, and user creation under Anaconda. Run repository setup through the add-on service and normal `install.sh` path; do not duplicate it in Kickstart `%post` logic.
- Build only from a supported Fedora x86_64 installer ISO and pass `--input-sha256` from Fedora's signed checksum file. Input and output paths must differ, and generated images belong under ignored `release/` rather than in Git.
- Use `--skip-mkefiboot` only for development builds that do not need a refreshed EFI boot image. Validate publishable media without that flag.
- For ISO changes, run the focused suites:

  ```bash
  bats tests/fedora_iso.bats tests/anaconda_addon.bats tests/post_actions_installer_iso.bats
  ```

- Before publishing installer-path changes, run `scripts/test-fedora-installer-vm.sh --input <fedora-installer.iso> --input-sha256 <sha256>`. Use its direct/text/headless modes for iteration, but validate the generated ISO boot path for release work.

## Safe development commands

- Inspect the generated base plan without applying it:

  ```bash
  ./install.sh install --yes --dry-run
  ```

- Exercise an optional planner selection without applying it:

  ```bash
  ./install.sh print-plan --select browser=brave --dry-run
  ```

- Use `./install.sh wizard` only for an intentional interactive install. Do not run a non-dry installation unless the user explicitly asks for it.

## Verification

- Run the smallest relevant Bats suite while iterating, for example:

  ```bash
  bats tests/planner.bats
  ```

- Run the required pre-PR smoke gate:

  ```bash
  ./tests/smoke.sh
  ```

  It requires Bats. Set `ZZ_TEST_LINT=1` to include ShellCheck.

- Use `./tests/full.sh` for broad or cross-cutting changes, `./tests/full.sh --timings` to include per-suite timings, and `./tests/profile.sh` only as the non-gating performance helper.
- Prefer fast, non-interactive tests that need neither root nor network access. Test planner and module behavior in-process; use `install.sh` subprocesses only when testing the CLI boundary.
- For base-bundle changes, test that base work is always planned, runs before optional work, is verified when required, and is not blocked by optional package failures.
- For first-login or session-sensitive changes, test marker creation and removal plus repeated-run idempotency.
- When implementation identifiers churn, test the new desired behavior. Do not add absence-only tests for old package names, actions, bundle IDs, filenames, or installer strings unless a negative selection is an intentional planner contract.

## Commits and pull requests

- Only create branches or PRs when specifically instructed to.
- Use a short, imperative commit subject.
- In a pull request, summarize changed sources, packages, choices, and user-visible behavior; list the exact validation commands run.
- Include screenshots only for user-facing TUI or generated desktop/session changes.
