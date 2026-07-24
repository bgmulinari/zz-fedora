# Repository instructions

## Scope and invariants

- This repository is a Fedora post-install bootstrapper for the Niri and Noctalia desktop.
- `install.sh` owns setup. `bootstrap.sh` only installs prerequisites, clones or updates the repository, and hands off to `install.sh`.
- The installed `zz` launcher is for post-install operations. Do not add install, wizard, plan, check, or repair wrappers under `bin/zz.d/`. Discover its supported commands with `./bin/zz commands --json`.
- The installer is under active development. Do not add migrations, compatibility shims, existing-install preservation, or regression guards for previous behavior unless the user explicitly requests them.
- Keep new repository-facing identifiers and documentation generic. Do not introduce third-party branding into unit IDs, catalog file names, config component names, or docs unless the user explicitly requests it.

## Repository layout

```
install.sh    Installer entry point and orchestrator
bootstrap.sh  Installs prerequisites, clones the repo, hands off to install.sh
modules/      Ordered install steps (preflight, sources, plan, packages, ...)
lib/          Shared Bash logic, plus lib/catalog.py, the catalog validator/compiler
catalog/      One TOML file per unit and per software source; the data-driven installer API
dotfiles/     Product-owned defaults and assets loaded or linked from ~/.zz
templates/    Seeds for user-owned files and installer-rendered inputs
bin/          The installed zz post-install launcher and its subcommands
iso/          Fedora installer ISO integration (Kickstart, Anaconda add-on)
tests/        Bats regression suites
```

The data layer is the `catalog/` tree. Each unit file declares wizard
visibility through a `[choice]` table or base membership through a `[base]`
table, plus one or more `[[install]]` steps carrying its packages, flatpaks,
or actions and the sources they need. `lib/catalog.py` validates the catalog
and compiles it to flat TSVs that the Bash planner consumes through
`lib/catalog.sh`; wizard categories derive from the `[choice]` tables.

## Put changes in the right place

- Keep ordered install orchestration in `modules/NN-name.sh`; put reusable Bash logic in `lib/` and keep modules thin.
- Treat the `catalog/` tree as the data-driven installer API: put install units in `catalog/units/<group>/<name>.toml` and repository definitions in `catalog/sources/<kind>/<name>.toml`. Unit group directories are organizational; semantics come from each unit's tables.
- Put product-owned live defaults and assets under `dotfiles/`. Reserve `templates/` for user-owned seeds and rendered inputs. `config/managed-config.tsv` is the authoritative map of components, paths, ownership modes, and conflict behavior; see `docs/dotfiles-layering.md`.
- Put regression tests in `tests/`; share Bash test helpers through `tests/helpers/` and put non-Bash test harnesses in `tests/support/`.
- When upstream reference code or docs are needed, consult the upstream project's repository or documentation instead of package decompilation or ad hoc reverse engineering.

## Preserve catalog contracts

- Every unit file declares a catalog-unique `id` and a `description`, optionally `requires` (unit IDs pulled in by dependency expansion) and `config` (managed configuration components selected from `config/managed-config.tsv`), and at least one `[[install]]` step. `lib/catalog.py` validation fails on unknown keys at any level; run `python3 lib/catalog.py --root . validate` after catalog edits.
- Each `[[install]]` step declares `backend` (`dnf`, `flatpak`, or `action`), optional `sources` (source IDs the step needs), and a payload key that must match the backend: `packages` for `dnf`, `flatpaks` for `flatpak`, `actions` for `action`.
- Base membership is the `[base]` table: a required integer `order` unique across the catalog, plus optional `early = true` and `minimal_desktop_skip = true`. Every unit under `catalog/units/base/` must declare `[base]`; `[base]` units may also live in other groups (the `shell-*` units do). A unit must not declare both `[base]` and `[choice]`: base units are planned before optional units and never appear in a wizard category. Use `DEFAULT_BUNDLE_IDS` only for broader defaults outside the choice catalogs.
- Wizard visibility is the `[choice]` table: required `category`, `id` (unique within the category), `label`, and `description` (the wizard copy), plus optional `default`, `order` (rows sort by `order`, then `id`), and `also` (extra unit IDs the choice selects).
- The default install selects every non-browser catalog choice and only Firefox from the browsers category. Express optional defaults through `[choice]` `default = true`.
- Give every base-owning unit a useful `description`; base package and action work must remain explainable in the generated `base-rationale.tsv` (its format is unchanged).
- Source descriptors declare `id`, `kind` (`official`, `copr`, `terra`, `rpmfusion`, `cisco-openh264`, `vendor`, `flatpak`, or `artifact`), `label`, `required`, `description`, and trust metadata: `gpg_policy` (one of `distro-managed`, `copr-plugin`, `rpm-gpg-import`, `repo-gpg-key`, `flatpak-gpg`, `unsigned-bootstrap`, `pinned-commit`, `sha256`, `tls-only`), `bootstrap_exception` (must be `true` when `gpg_policy` is `unsigned-bootstrap`), and `reason`.
- `project` is kind-scoped: required for `copr` sources (the COPR project to enable) and `artifact` sources (the fetch origin, optionally pinned as `url@commit`), and forbidden for every other kind.
- Units reference sources only through the per-step `sources` lists; unknown source IDs fail catalog validation. Dedicated `source-*` base units own base-required sources; optional units declare their own source needs on their install steps (source enablement is idempotent, so overlap with base sources is fine).

## Bash and installer behavior

- Use `#!/usr/bin/env bash` and `set -Eeuo pipefail` in Bash entrypoints.
- Follow the existing naming style: lowercase function names, uppercase globals and environment flags, and quoted variable expansions.
- `lib/catalog.py` is the only catalog parser. It targets Python >= 3.11 and uses only the standard library (`tomllib`); `python3` is a bootstrap prerequisite installed by `bootstrap.sh`. Bash never parses catalog TOML: it consumes only the compiled TSVs through `lib/catalog.sh`.
- Give every externally-settable environment override the `ZZ_` prefix (for example `ZZ_DRY_RUN`, `ZZ_ASSUME_YES`, `ZZ_NO_TUI`); unprefixed uppercase names are internal runtime globals only and must not be read from the caller's environment as installer knobs.
- Keep required base actions idempotent and give them explicit verification checks.
- Keep GUI defaults that require a logged-in user session in the first-run path rather than the system install path.
- For Noctalia changes, keep portable product defaults in the managed config and do not commit generated, monitor-specific, or hardware-specific state from `~/.local/state/noctalia/`.

## Fedora installer ISO

- The installer-ISO path lives entirely under `iso/`: the Kickstart, Anaconda add-on, build and VM test scripts (`iso/scripts/`), build-time helpers (`iso/lib/build-common.sh`), the payload manifest (`iso/payload-paths.conf`), and the runtime loader (`iso/lib/runtime-loader.sh`).
- `docs/fedora-installer-iso.md` is the single expanded source for build, install-flow, and pre-publish VM validation procedure (verified input media, dev-only build shortcuts, harness modes); `docs/design/fedora-installer-iso-architecture.md` holds the design rationale. Keep both synchronized with behavior and CLI changes instead of restating their detail here.
- `iso/lib/build-common.sh` runs only at build time on the developer machine; `iso/lib/runtime-loader.sh` runs only inside Anaconda via the add-on and is never sourced by the normal `install.sh` path. Keep those lifecycles separate.
- Keep the ISO online: it embeds the current checkout and installer integration, not package mirrors, and stages only Git-tracked runtime files.
- Keep system configuration (disk layout, locale, timezone, hostname, credentials, user creation) under Anaconda. Run repository setup through the add-on service and normal `install.sh` path; do not duplicate it in Kickstart `%post` logic.
- For ISO changes, run the focused suites:

  ```bash
  bats tests/fedora_iso.bats tests/anaconda_addon.bats tests/post_actions_installer_iso.bats
  ```

- Before publishing installer-path changes, run the VM validation documented in `docs/fedora-installer-iso.md`.

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
- For base-unit changes, test that base work is always planned, runs before optional work, is verified when required, and is not blocked by optional package failures.
- For first-login or session-sensitive changes, test marker creation and removal plus repeated-run idempotency.
- When implementation identifiers churn, test the new desired behavior. Do not add absence-only tests for old package names, actions, unit IDs, filenames, or installer strings unless a negative selection is an intentional planner contract.

## Commits and pull requests

- Only create branches or PRs when specifically instructed to.
- Use a short, imperative commit subject.
