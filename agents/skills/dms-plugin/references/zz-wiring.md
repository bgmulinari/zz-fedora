# Wiring a DMS plugin into ZZ

This reference describes the repository side: where the plugin lives, how the
installer delivers it, how the catalog selects it, how to enable it by default, and
how to test and document it. Facts below were read from the ZZ checkout and the DMS
v1.6.0 source (`quickshell/Services/PluginService.qml`, `quickshell/Common/SettingsData.qml`).

## Contents

1. [How DMS discovers plugins](#how-dms-discovers-plugins)
2. [Repository layout](#repository-layout)
3. [Managed-config row](#managed-config-row)
4. [Catalog unit](#catalog-unit)
5. [Enable by default](#enable-by-default)
6. [Tests](#tests)
7. [Docs](#docs)
8. [Verification commands](#verification-commands)
9. [Live testing](#live-testing)

## How DMS discovers plugins

- User plugins: `~/.config/DankMaterialShell/plugins/<Dir>/plugin.json`. DMS watches
  the directory with a `FolderListModel` (`showDirs: true`), so a symlinked directory
  is listed like a real one, and the manifest path is derived from the entry, which
  keeps `pluginDirectory` under the user path even for a symlink.
- System plugins: `/etc/xdg/quickshell/dms-plugins/<Dir>/plugin.json`. A user plugin
  with the same `id` shadows the system one. ZZ does not use this tier.
- A manifest is accepted when it has `id`, `name`, and `component` or `components`
  with at least one resolvable surface. Invalid manifests are logged and skipped.
- Loading: after registration, DMS loads the plugin when
  `SettingsData.getPluginSetting(id, "enabled", false)` is true, or unconditionally
  for a plugin whose only surface is `desktop`. `enabled` lives in
  `~/.config/DankMaterialShell/plugin_settings.json` (DMS 1.6), keyed by plugin id.
  Per-plugin user settings (`savePluginData`) live in the same file; runtime state
  (`savePluginState`) goes to `~/.local/state/DankMaterialShell/plugins/<id>_state.json`.
- Bar placement: a widget appears only when its plugin id is present in a bar
  section (`leftWidgets`, `centerWidgets`, `rightWidgets` of an entry in
  `barConfigs` in `settings.json`). The widget id is the plugin id, optionally
  `id:variantId` for variants.
- Runtime IPC: `dms ipc plugin-scan scan|rescan <id>|reload <id>|list|status <id>`
  and `dms ipc plugins enable|disable|toggle|list|status`.

## Repository layout

```
<repository root>/
  dotfiles/dms/.config/DankMaterialShell/plugins/<PascalName>/   plugin source (product-linked)
    plugin.json
    <Component>.qml
    Settings.qml, StartupCheck.qml, *.js, translations/        optional
  config/managed-config.tsv                                     the link row
  catalog/units/desktop/<kebab>.toml                            the unit (optional choice)
  templates/dms/settings-seed.json                              bar layout seed (only if shipped enabled)
  tests/dms_plugins.bats, tests/support/dms_plugin.py           tests
  docs/design/dms-integration.md                                design record
```

`dotfiles/` holds live product defaults that are linked, never copied; `templates/`
is for user-owned seeds. A plugin is product-owned, so it belongs under `dotfiles/`.

## Managed-config row

`config/managed-config.tsv` has seven tab-separated fields:
`component`, `path`, `mode`, `conflict`, `source`, `required-command`, `description`.
Rules enforced by `lib/files.sh` (`load_managed_config_policy_cache`):

- component matches `^[a-z0-9-]+$`;
- `product-link` pairs only with `backup-before-link` and requires a source that
  exists inside the repository;
- paths are unique across the file;
- the row is skipped at apply time when `required-command` is not on PATH.

Row for a plugin (tabs, not spaces):

```
dms-plugin-disk-free	~/.config/DankMaterialShell/plugins/DiskFree	product-link	backup-before-link	dotfiles/dms/.config/DankMaterialShell/plugins/DiskFree	dms	Links the managed disk-free bar widget plugin.
```

Why a directory link: `replace_user_path_with_product_link` accepts any existing
source path and creates one symlink, backing up whatever was at the destination.
Linking the directory means files added later (a new `translations/es.json`, a helper
`.js`) reach existing installs on the next `zz update zz` without new rows, and the
plugin cannot be half-updated. The theme file is linked per file because DMS expects
only `theme.json` under the theme id directory; plugins have no such constraint.

Why not `system-file`: it copies a single file into `/etc` or `/usr/lib` and only
re-copies when the installer runs, so git updates would not reach the shell, and the
user tier would shadow it anyway.

Component naming: `dms-plugin-<kebab>` per plugin for optional choices. For a base
plugin, use the existing `dms` component so `base-dms` picks it up without a new
catalog reference.

## Catalog unit

Optional choice (the default ship mode), `catalog/units/desktop/disk-free.toml`:

```toml
id = "desktop-disk-free"
description = "Disk free-space bar widget for the desktop shell"
config = ["dms-plugin-disk-free"]

[choice]
category = "desktop"
id = "disk-free"
label = "Disk free widget"
default = true
order = 90
description = "Show free space of the root filesystem in the bar"

[[install]]
backend = "dnf"
sources = ["copr:avengemedia/dms"]
packages = ["dms"]
```

Notes:

- `[choice].order` sorts rows within the category; check existing `desktop` units
  for a free slot. `id` must be unique within the category.
- `default = true` is required in practice: `tests/manifest_catalog.bats` asserts that
  the default install selects every non-browser choice. A plugin that should not be
  on by default therefore cannot be a wizard choice; ship it as a standalone dev copy
  or ask the user how they want the contract changed.
- Adding a desktop choice touches two test fixtures that enumerate choices: the
  ordered desktop choice id list in `tests/anaconda_addon.bats`, and the plan-cache
  key in `tests/helpers/common.bash` (`build_test_plan` turns the selection string
  into a directory name; a selection naming every desktop choice can exceed the
  255-byte filename limit, which surfaces as `mkdir: cannot create directory ...:
  File name too long` (or the same from `rm`) in `tests/planner.bats`; hash keys
  longer than about 200 bytes there, with a `plan-<sha256 prefix>` name, rather
  than shortening test data).
- The install step must carry a payload or a source (`lib/catalog.py` rejects a step
  with neither). List the plugin's real system dependencies here (`packages =
  ["btop", "jq"]`). A package from the official Fedora repositories needs no
  `sources` line at all; name a source only for COPR, Terra, RPM Fusion, or vendor
  packages. When the plugin has no dependency beyond the shell, `packages = ["dms"]`
  from the `copr:avengemedia/dms` source is the honest payload: the shell is
  genuinely required and dnf treats an installed package as a no-op.
- Group directories are organizational; `desktop/` is where user-facing desktop
  features live. Do not create a vendor-named group.
- Base plugin instead: add the row to the `dms` component (no catalog change; the
  `dms` component is already in `base-dms`'s `config`), and remember that base work
  must stay verifiable and explainable in `base-rationale.tsv`. The ZZ menu
  (`plugins/ZzMenu`) ships this way.

Run `/usr/bin/python3 lib/catalog.py --root . validate` after every catalog edit.

## Enable by default

Skip this for plugins the user opts into through Settings > Plugins, and for pure
desktop plugins (auto-enabled). When a plugin must be live at first login:

1. **`plugin_settings.json` seed.** Add `"<id>": {"enabled": true}` (plus any
   default plugin settings read through `pluginData`) to
   `templates/dms/plugin-settings-seed.json`. Nothing else: the base `dms`
   component already carries the `seed-if-missing` row for the file with no source,
   and `dms_plugin_settings_seed_json` in `lib/dms.sh` renders the template minus
   the ids whose plugin component is not in the plan (the same
   `dms_unplanned_plugin_ids` walk the bar seed uses), so a deselected choice seeds
   nothing for itself while every shipped plugin shares one file (a managed-config
   path may appear only once). The DMS state seeding writes it with `settings.json`
   in post-actions, and `dms_apply_plugin_defaults` then tops up existing
   installs: ids the live file lacks are added as enabled, the widget is inserted
   into the live bar at its seed position once (recorded in
   `~/.local/state/zz-fedora/dms-placed-widgets`), and a running shell is asked
   over IPC to load it. `zz refresh` does not list rendered seeds.
2. **Bar layout.** For a widget, add the plugin id to the wanted section of the
   `barConfigs[0]` entry in `templates/dms/settings-seed.json`. The seed-diff tool
   compares bar configs field by field, so this is a normal promotable key.
   `dms_settings_seed_json` strips the ids of shipped plugins whose component is not
   in the plan (it maps `plugins/<Name>` link rows to their `plugin.json` id), so a
   deselected choice leaves no dangling widget id behind.
3. **Doctor.** `modules/90-doctor.sh` checks `plugin_settings.json` whenever DMS
   is planned and each linked `plugin.json` when its component is in
   `components.list`; add the new plugin's manifest path to that block. The seed-diff tool (`lib/dms_seed_diff.py`) does not
   cover plugin settings; say so in the design doc rather than extending it unasked.
4. **Existing installs get it too.** The top-up above is what makes a plugin on by
   default everywhere; a user who disables it or removes the widget is left
   alone. Nothing else to add per plugin.

Never capture a live `plugin_settings.json`: it accumulates state for every plugin
the user ever enabled.

## Tests

Create `tests/dms_plugins.bats` the first time (tag it `smoke` like `dms_theme.bats`
if it is fast, which it is). Copy `scripts/validate_plugin.py` from this skill to
`tests/support/dms_plugin.py` and `assets/plugin-schema.json` to
`tests/support/plugin-schema.json` so the suite is self-contained; the script looks
for the schema beside itself when the skill layout is absent.

```bash
#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "shipped DMS plugin manifests are valid and complete" {
  local plugin
  for plugin in "$ROOT_DIR"/dotfiles/dms/.config/DankMaterialShell/plugins/*/; do
    "$SYSTEM_PYTHON" "$ROOT_DIR/tests/support/dms_plugin.py" "$plugin"
  done
}

@test "disk-free selection plans the plugin link and unit" {
  build_test_plan "desktop=disk-free"

  assert_plan_has "$PLAN_DIR/bundles.list" "desktop-disk-free"
  assert_plan_has "$PLAN_DIR/config/components.list" "dms-plugin-disk-free"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/DankMaterialShell/plugins/DiskFree"
}

@test "product link targets the repository plugin directory" {
  DRY_RUN=0
  SKIP_USER_CONFIG=0
  run_cmd_as_user() { shift; "$@"; }
  local source="$ROOT_DIR/dotfiles/dms/.config/DankMaterialShell/plugins/DiskFree"
  local destination="$TARGET_HOME/.config/DankMaterialShell/plugins/DiskFree"

  run replace_user_path_with_product_link "$source" "$destination"

  [ "$status" -eq 0 ]
  [[ -L "$destination" ]]
  [[ -f "$destination/plugin.json" ]]
}
```

`build_test_plan "<category>=<choice-id>[,<choice-id>]"` builds the dry-run plan in
process; `$PLAN_DIR` then holds `bundles.list`, `config/components.list`,
`files/managed-files.list`, `packages/dnf.pkgs`, and the per-kind source lists
(`sources/copr.list`, `sources/terra.list`, `sources/vendor.list`,
`sources/artifacts.list`, ...).

`build_test_plan` with no selection builds the base-only plan: a `default = true`
choice is not in it, so do not assert an optional plugin's link there (the base
ZZ menu link and the rendered `plugin_settings.json` seed are). To assert
that a choice is selected by default, use the catalog helper instead:

```bash
@test "disk-free is a default desktop choice" {
  run default_choice_ids desktop
  [ "$status" -eq 0 ]
  assert_contains "$output" "disk-free"
}
```

For a base plugin, call `build_test_plan` with no selection and assert the link is
present, and add a case to the base ordering expectations in `tests/planner.bats`
only if the unit is new. When an existing test enumerates the `dms` component's
paths (for example `tests/planner.bats` around the managed-files assertions),
extend it rather than duplicating it. A consistency test that cross-checks the
manifest `trigger`/`dependencies` against the QML and the unit's packages catches
the drift that no validator sees.

If a plugin ships a JSON seed of its own settings, assert the seeded id matches the
manifest id in the same suite; that mismatch is silent at runtime.

## Docs

- `docs/design/dms-integration.md`: add a "Plugins" section the first time,
  recording the product-link-a-directory decision and the enable-by-default limit,
  then one bullet per shipped plugin (what it does, which unit, which tools).
- `docs/dotfiles-layering.md`: the DMS row of the "Native application layers" table
  mentions the theme link; append "and any plugin directories under
  `dotfiles/dms/.config/DankMaterialShell/plugins/`" the first time a plugin lands.
- Keep the plugin's own `README.md` inside its directory short: purpose, settings,
  dependencies. It is linked into the user's config with the rest of the directory.

## Verification commands

```bash
/usr/bin/python3 agents/skills/dms-plugin/scripts/validate_plugin.py dotfiles/dms/.config/DankMaterialShell/plugins/<PascalName>
/usr/bin/python3 lib/catalog.py --root . validate
./install.sh print-plan --select desktop=<choice-id> --dry-run
./install.sh install --yes --dry-run            # base plugins: confirm the link is in the base plan
bats tests/dms_plugins.bats tests/managed_config.bats tests/planner.bats tests/catalog_validation.bats
./tests/smoke.sh                                 # required pre-PR gate; ZZ_TEST_LINT=1 adds ShellCheck
```

`jq . plugin.json` is a fast syntax check when iterating on the manifest.

## Live testing

The development machine runs the same DMS release the installer targets, so the
plugin can be exercised without an install:

```bash
mkdir -p ~/.config/DankMaterialShell/plugins
ln -s "$PWD"/dotfiles/dms/.config/DankMaterialShell/plugins/<PascalName> ~/.config/DankMaterialShell/plugins/<PascalName>
dms ipc plugin-scan scan
dms ipc plugin-scan list                 # TSV: id, loaded, type, name
dms ipc plugin-scan status <id>          # TSV: loaded, type, error
journalctl --user -u dms.service -n 100 --no-pager | grep -i -E "plugin|qml|error"
```

Then enable it (`dms ipc plugins enable <id>`, or Settings > Plugins) and, for a
widget, add it to a bar section through Settings > Bar. After editing QML, `dms ipc plugin-scan reload <id>` reloads
without restarting the shell; manifest changes need `rescan <id>`. QML errors print
to the journal with file and line.

`dms plugins lock` / `restore` and `dms plugins install` are registry tools for
user-installed plugins; ZZ-shipped plugins do not go through them.
