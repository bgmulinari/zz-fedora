---
name: dms-plugin
description: >
  Create, wire, validate, and live-test DankMaterialShell (DMS) plugins that ship with
  the ZZ Fedora bootstrapper repository: scaffold the plugin under dotfiles/dms
  from the version-matched upstream templates, write the QML against the installed DMS
  and Quickshell API, add the managed-config product-link row, the catalog unit (or base
  attachment), optional enable-by-default seeds, Bats tests, and docs, then validate
  plugin.json and load it through `dms ipc plugin-scan`. Use this whenever the user
  mentions a DMS plugin, a DankBar widget or pill, a launcher/daemon/desktop plugin, a
  Quickshell or QML widget for the ZZ desktop, vendoring or shipping a plugin in ZZ, a
  Control Center tile, or asks how ZZ should package something for its shell, even if
  they never say the word "plugin". Also use it to modify or debug a plugin that ZZ
  already ships.
compatibility: Claude Code on the ZZ development machine (dms and qs installed, reference checkouts under /files/dev/ref-repos)
metadata:
  domain: zz-fedora-bootstrapper
  upstream: AvengeMedia/DankMaterialShell, quickshell-mirror/quickshell
---

# ZZ DMS plugin creator

ZZ is a Fedora post-install bootstrapper for the Niri + DMS desktop. A "ZZ-shipped"
DMS plugin is not something the user installs from the registry: its source lives in
the ZZ checkout, ZZ product-links the plugin directory into the user's DMS plugin
directory, and a catalog unit decides who gets it. This skill covers the whole path
from an idea to a plugin that the planner, the installer, the tests, and the running
shell all agree on.

Three layers, each with its own contract:

| Layer | Contract owner | Where to look |
| --- | --- | --- |
| Plugin API (manifest, QML, services, theme) | Installed DMS release | upstream skill in the reference checkout (Step 0) |
| Shipping it with ZZ (paths, catalog, seeds, tests, docs) | this repository's rules | [references/zz-wiring.md](references/zz-wiring.md) |
| Runtime (Process, FileView, sockets) | Installed Quickshell revision | `src/io/*.hpp` in the quickshell reference checkout |

Read `CLAUDE.md` at the repository root before touching anything; it defines the invariants this
skill relies on (catalog contracts, managed-config rules, no migrations, generic naming).

## Step 0: Sync the references to the installed versions

The plugin API changes between DMS releases (1.6 moved plugin settings into their own
file, added composite plugins, startup checks, and translations), so answer from the
release that is actually installed, never from memory or a random default branch:

```bash
bash agents/skills/dms-plugin/scripts/sync_refs.sh
```

It reads `dms version` and `qs --version`, syncs the matching DMS tag, the
`dank-qml-common` submodule at the commit DMS pins (that is where `Proc.runCommand`,
`Theme`, and the `qs.Widgets` components are implemented), the Quickshell commit, and
the plugin registry through the `reference-github-repos` skill, and prints the
checkout paths. Then load the upstream plugin skill from that checkout; it is the
authoritative API guide and this skill deliberately does not duplicate it:

```
<dms-checkout>/.agents/skills/dms-plugin-dev/SKILL.md
```

[references/upstream-map.md](references/upstream-map.md) lists which upstream file
answers which question (QML base components, PluginService internals, example plugins,
registry entries, Quickshell IO types). Everything under `/files/dev/ref-repos` is
read-only reference material.

## Step 1: Decide type and ship mode

First check whether DMS already has it: the built-in bar widgets are listed in the
`componentMap` of `quickshell/Modules/DankBar/WidgetHost.qml` (clock, weather,
cpuUsage, memUsage, diskUsage, battery, network, ...), and the registry
(`dms plugins browse`) may carry a community plugin. Say so before building a
duplicate; the user may still want ZZ's own, but it should be a decision.

Pick the plugin type with the upstream skill's decision table (widget, daemon,
launcher, desktop, composite). Then decide how ZZ ships it, because that decides
which repository files change:

| Ship mode | When | Catalog wiring |
| --- | --- | --- |
| **Optional choice** (default) | Most plugins. The wizard offers it, `default = true` selects it on a default install. | New unit with a `[choice]` table and its own config component |
| **Base** | Only when the desktop is incomplete without it and it needs no wizard visibility | Component added to the `dms` component rows and `base-dms`'s `config` array |
| **Standalone dev copy** | Prototyping before deciding | Nothing in the repo; work in `~/.config/DankMaterialShell/plugins/<Name>/` and move it under `dotfiles/` when it settles |

Decide visibility explicitly. A selected widget that is not enabled and not placed in
a bar section is invisible, so "on by default" for a widget usually means the choice
is default *and* the plugin is enabled and placed by seed (Step 4, item 3). For a
launcher or daemon, enabled is enough; a pure desktop plugin enables itself. State
the interpretation in the summary so the user can correct it.

The installer is under active development: no migrations, compatibility shims, or
regression guards for previous plugin behavior unless the user asks.

## Step 2: Scaffold

```bash
bash agents/skills/dms-plugin/scripts/scaffold_plugin.sh \
  --type widget --id diskFree --name "Disk Free" \
  --description "Free space of the root filesystem in the bar"
```

The script copies the upstream templates for the type from the synced checkout into
`dotfiles/dms/.config/DankMaterialShell/plugins/<PascalName>/`, renames the
template id and name, and prints the managed-config row and unit snippet to add next.
It refuses to overwrite an existing directory. Composite plugins have no upstream
template: scaffold the surfaces one type at a time into one directory, then merge the
manifests by hand into a `components` map.

Naming, following upstream conventions: the directory is PascalCase, the manifest
`id` is camelCase (`^[a-zA-Z][a-zA-Z0-9]*$`), QML files are PascalCase, component
paths start with `./`.

## Step 3: Write the plugin

Follow the upstream skill for the QML. The ZZ-specific rules on top of it:

- **Theme everything.** ZZ ships a Catppuccin registry theme and matugen drop-ins;
  hardcoded colors or sizes break the light/dark and accent sync. Use `Theme.*`
  from `qs.Common` and the `qs.Widgets` components.
- **No host paths.** Nothing under `dotfiles/` may carry `/home/<user>` or a monitor,
  GPU, or device identity. Derive paths at runtime (`pluginService.getPluginPath(id)`,
  `Quickshell.env("HOME")`, `Paths.*`).
- **Declare tools twice.** A system tool the plugin shells out to goes into the
  manifest `dependencies` (registry metadata, not enforced) and into the unit's
  `[[install]]` packages (what actually installs it). Add a `StartupCheck.qml` so a
  missing tool blocks activation with a readable error instead of a silent widget.
- **Settings need `settings_write`.** Any plugin with a `settings` component must
  declare that permission or the Settings page shows an error.
- **Both bar orientations.** A widget needs `horizontalBarPill` and `verticalBarPill`;
  the shipped bar is top-anchored, but users move it.
- **Pills are content, not boxes.** `BasePill` (`Modules/Plugins/BasePill.qml`) already
  draws the pill background, padding, hover, and blur, and it honors the bar's
  `noBackground` setting, which ZZ's seed turns on. The upstream template wraps the
  pill in a `StyledRect`, which double-boxes under that bar. Return a bare `Row` (icon
  plus `StyledText`) like the built-in widgets in `Modules/DankBar/Widgets/`, sized
  with `Theme.barTextSize(...)` and colored with `Theme.widgetIconColor`.
- **One `Proc.runCommand` id per instance.** `Proc` keeps one debouncer and one
  callback per id, and a bar widget is instantiated once per monitor and section, so
  a fixed id means only the last instance ever updates. Build the id from a
  per-instance random suffix and call `Proc.release(id)` in `Component.onDestruction`.
- **Runtime types come from the installed Quickshell.** Check `Process`,
  `StdioCollector`, and `FileView` signatures in the quickshell checkout's
  `src/io/process.hpp` and `src/io/fileview.hpp` rather than guessing property names.
- **Guides describe intent; the QML decides.** When a guide example matters (launcher
  context menus, popout injection, item fields), confirm it against the shell source
  the map points to. The map lists the known v1.6.0 divergences.

## Step 4: Wire it into ZZ

Read [references/zz-wiring.md](references/zz-wiring.md) and apply, in this order:

1. **Managed-config row** in `config/managed-config.tsv`: one `product-link` row that
   links the whole plugin directory to
   `~/.config/DankMaterialShell/plugins/<PascalName>`, component
   `dms-plugin-<kebab>`, required command `dms`.
2. **Catalog unit** in `catalog/units/desktop/<kebab>.toml` (optional choice) or the
   `dms` component plus `base-dms` `config` (base). Every unit needs an `[[install]]`
   step with a payload; when the plugin needs no extra package, declare
   `packages = ["dms"]` with the `copr:avengemedia/dms` source, which is honest (the
   plugin requires the shell) and idempotent. `default = true` is required for a
   non-browser choice (a test enforces it), and a new desktop choice must also be
   appended to the ordered list in `tests/anaconda_addon.bats`.
3. **Enable-by-default seeds** only when the plugin must be active on first login.
   DMS 1.6 keeps the `enabled` flag in `plugin_settings.json`, which ZZ does not seed
   today; the reference explains the minimal `lib/dms.sh` and seed additions, and why
   bar widgets also need their id in a `barConfigs` section of
   `templates/dms/settings-seed.json`. Pure desktop plugins auto-enable and need none
   of this.
4. **Docs**: a "Plugins" subsection in `docs/design/dms-integration.md` (create it the
   first time, then one bullet per plugin) and the DMS row of the layers table in
   `docs/dotfiles-layering.md`, which must mention plugin directories once any exist
   (a test checks that every repository path the doc names exists).

## Step 5: Validate

Run from the repository root, one command at a time (compound `cd &&` lines are
rejected in sandboxed worktrees):

```bash
/usr/bin/python3 agents/skills/dms-plugin/scripts/validate_plugin.py dotfiles/dms/.config/DankMaterialShell/plugins/<PascalName>
/usr/bin/python3 lib/catalog.py --root . validate
./install.sh print-plan --select desktop=<choice-id> --dry-run
```

The validator is stdlib-only and mirrors the upstream JSON schema (bundled as
`assets/plugin-schema.json`, refreshed from the synced checkout when it differs) plus
the mistakes the schema cannot see: referenced QML files missing, `Settings.qml`
carrying a different `pluginId` than the manifest, a widget without
`property var popoutService`, a launcher without `trigger`, `requires` instead of
`dependencies`. Fix errors; read warnings.

The print-plan run must list the plugin's link under managed files and its unit under
bundles. Never run a non-dry install for this.

## Step 6: Tests

Add or extend `tests/dms_plugins.bats` (create it the first time; copy the validator
and schema into `tests/support/` so the suite does not depend on this skill being
installed). The reference has the templates. Cover:

- every shipped manifest validates;
- the choice selection plans the product link, the unit, and the dependency
  packages (`build_test_plan "desktop=<id>"`; with no selection it builds the
  base-only plan, so default choices are absent there);
- the choice is a default (`default_choice_ids desktop`);
- manifest `trigger`/`dependencies` agree with the QML and the unit's packages;
- for base plugins, that the link is planned before optional work and is not blocked
  by optional package failures (same expectations as other base units).

Expect two existing fixtures to need an update when a desktop choice is added: the
ordered choice list in `tests/anaconda_addon.bats`, and the plan-cache key length in
`tests/helpers/common.bash` if `tests/planner.bats` fails with "File name too long".

Then run the smallest relevant suites and the smoke gate from the repository root:

```bash
bats tests/dms_plugins.bats tests/managed_config.bats tests/planner.bats tests/catalog_validation.bats tests/manifest_catalog.bats tests/anaconda_addon.bats
./tests/smoke.sh
```

## Step 7: Load it in the running shell

This machine runs the target desktop, so test the real thing without installing. Link
the repository directory exactly as the installer would, ask DMS to rescan, and read
its status:

```bash
mkdir -p ~/.config/DankMaterialShell/plugins
ln -s "$PWD"/dotfiles/dms/.config/DankMaterialShell/plugins/<PascalName> ~/.config/DankMaterialShell/plugins/<PascalName>
dms ipc plugin-scan scan
dms ipc plugin-scan status <id>
journalctl --user -u dms.service -n 50 --no-pager
```

Enable it in Settings > Plugins (or `dms ipc plugin-scan reload <id>` after a code
change) and add a widget to a bar section. Startup-check failures surface as a toast
and in `status`. Remove the link afterwards unless the user wants to keep it; the
installer will recreate it from the managed-config row.

## Pitfalls specific to ZZ

- **Product-link the directory, not each file.** A directory symlink keeps new files
  reachable after `zz update zz` with no new rows; DMS lists symlinked plugin
  directories like real ones.
- **User plugins shadow system ones.** `/etc/xdg/quickshell/dms-plugins` exists, but
  ZZ does not use it: `system-file` mode only handles single files and would copy
  rather than link, so updates would stop flowing.
- **Seeds run once.** `seed-if-missing` files are user-owned afterwards. A plugin
  enabled by seed on a fresh install is not enabled on an existing one; say so in the
  docs instead of adding a migration.
- **Do not commit state.** Nothing from `~/.local/state/DankMaterialShell/` or
  `~/.cache/DankMaterialShell/` belongs in the repo, including `plugin_settings.json`
  captured from a live session.
- **Generic identifiers.** Name the unit after the feature (`desktop-disk-free`), not
  after the shell or a vendor; the `dms-plugin-` component prefix follows the
  existing `dms` component convention and is the only branded part.
- **Bash never parses the manifest.** If installer logic needs plugin facts, put them
  in the catalog TOML or a TSV, not in a `jq` read of `plugin.json`.

## Files in this skill

- `scripts/sync_refs.sh`: sync DMS, Quickshell, and registry checkouts to the installed versions.
- `scripts/scaffold_plugin.sh`: create a plugin directory from the upstream templates and print the wiring snippets.
- `scripts/validate_plugin.py`: stdlib manifest and layout validator.
- `assets/plugin-schema.json`: upstream `plugin.json` schema snapshot (DMS v1.6.0).
- `references/zz-wiring.md`: repository wiring, seeds, tests, docs, and verification commands.
- `references/upstream-map.md`: where each upstream answer lives in the reference checkouts.
