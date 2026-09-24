---
name: create-dms-plugin
description: >
  Write, modify, or debug a DankMaterialShell (DMS) plugin of the user's own on a ZZ
  Fedora desktop: a bar widget or pill, a launcher search, a background daemon, a
  desktop widget, or a Control Center tile, in QML against the installed DMS and
  Quickshell. Use when the user wants to build or change a plugin under
  ~/.config/DankMaterialShell/plugins/, asks about the DMS plugin API, plugin.json,
  PluginService, popouts, or why a plugin fails to load. Installing plugins from the
  registry belongs to the zz skill; shipping a plugin with ZZ itself is repository
  work under ~/.zz and is not covered here.
---

# Creating a DMS plugin

A DMS plugin is a directory with a `plugin.json` manifest and QML components that the
shell loads into its bar, launcher, desktop, or Control Center. This skill covers a
plugin the user writes for their own desktop; the shell's own documentation is the API
reference, and this file adds where to find it on this machine, what is specific to a
ZZ desktop, and how to load and test the result.

## Where it lives

User plugins go in `~/.config/DankMaterialShell/plugins/<PascalName>/`, one directory
per plugin with `plugin.json` at its root. The directory is PascalCase, the manifest
`id` is camelCase, component paths in the manifest start with `./`.

Plugins ZZ ships (the ZZ menu, agent usage, GitHub) are symlinks into `~/.zz`, which is a Git
checkout that `zz update zz` fast-forwards and that refuses to update when dirty. To
build on one, copy its directory to a new name and give the copy a new `id`; do not
edit the linked one.

## Answer from the installed shell

The plugin API changes between DMS releases (`dms version` prints the installed one),
so read the installed shell's own files rather than online docs or memory. The
running shell's source is under `/usr/share/quickshell/dms/` and is by construction
the version the plugin will load into:

| Question | File under `/usr/share/quickshell/dms/` |
| --- | --- |
| The full plugin guide: types, manifest, settings, persistence, startup checks, translations, "Creating a Plugin" | `PLUGINS/README.md` |
| Manifest schema | `PLUGINS/plugin-schema.json` |
| A worked example per type (widget, launcher, daemon, desktop, composite, variants, startup check, popout control) | `PLUGINS/*Example*/`, `PLUGINS/WallpaperWatcherDaemon/` |
| Theme properties, popout service | `PLUGINS/THEME_REFERENCE.md`, `PLUGINS/POPOUT_SERVICE.md` |
| What the host injects into a plugin (`PluginComponent`, `BasePill`, the setting components) | `Modules/Plugins/` |
| Discovery, load gating, IPC target | `Services/PluginService.qml` |
| `Theme.*`, `Proc.runCommand` and the shared widgets | `Common/Theme.qml`, `DankCommon/Common/Proc.qml`, `DankCommon/Widgets/` |

The upstream repository also carries an agent skill with per-type guides
(`.agents/skills/dms-plugin-dev/`) that the package does not install. When the README
and the examples leave a question open, clone the matching tag and read it:

```bash
tag="$(dms version | awk 'NR==1 {print $NF}')"   # "dms v1.6.1" -> v1.6.1
git clone --depth 1 --branch "$tag" https://github.com/AvengeMedia/DankMaterialShell.git \
  "${XDG_CACHE_HOME:-$HOME/.cache}/zz-fedora/DankMaterialShell"
```

Runtime types (`Process`, `FileView`, `Socket`) come from Quickshell; `qs --version`
prints the installed revision, and the property list that revision supports is the
one to trust when the online documentation describes a newer release.

## Specific to a ZZ desktop

- **Colors and sizes come from `Theme.*`.** ZZ keeps a registry theme and matugen
  drop-ins in sync across the shell and every application it wires up; a hardcoded
  color or size is the one thing that breaks on the next theme change. Use the
  `qs.Widgets` components (`StyledText`, `DankIcon`, ...) rather than raw `Text`.
- **A bar pill is content, not a box.** `BasePill` already draws the background,
  padding, hover, and blur, and honors the bar's `noBackground` setting, which the
  ZZ bar seed turns on. The upstream widget template wraps the pill in a
  `StyledRect`, which double-boxes under that bar; return a bare `Row` of icon and
  `StyledText`, sized with `Theme.barTextSize(...)` and colored with
  `Theme.widgetIconColor`, the way the built-in widgets in `Modules/DankBar/Widgets/`
  do.
- **Provide both bar orientations.** A widget declares `horizontalBarPill` and
  `verticalBarPill`; the shipped bar is horizontal, but the user can move it.
- **One `Proc.runCommand` id per instance.** `Proc` keeps one debouncer and one
  callback per id, and a bar widget is instantiated once per monitor and per section,
  so a fixed id means only the last instance ever updates. Build the id from a
  per-instance random suffix and call `Proc.release(id)` in `Component.onDestruction`.
- **A tool the plugin shells out to needs a startup check.** List it in the manifest
  `dependencies` and add a `StartupCheck.qml` so a missing tool blocks activation with
  a readable error instead of a silent widget; the manifest list alone enforces
  nothing.
- **A settings page needs the `settings_write` permission**, or Settings > Plugins
  shows an error for it.
- **A popout is `popoutContent`.** `PluginComponent` gives a widget an anchored popout
  with keyboard focus: set `popoutContent` and `popoutWidth` and leave
  `pillClickAction` unset so the click toggles it. The host keeps the content alive
  between opens, so reset state on `parentPopout.shouldBeVisible` rather than in
  `Component.onCompleted` alone. `dms ipc call widget toggle <id>` opens it from a
  keybind.

## Load it and test it

```bash
dms ipc call plugin-scan scan                # register a new directory
dms ipc call plugin-scan status <id>         # loaded, type, error
dms ipc call plugins enable <id>             # or Settings > Plugins
journalctl --user -u dms.service -n 100 --no-pager | grep -iE 'plugin|qml|error'
```

A widget also has to be placed: add it to a bar section in Settings > Bar (it appears
under its plugin id). A launcher plugin shows up under its `trigger` prefix in the
launcher; a desktop plugin enables itself.

Iterate with `dms ipc call plugin-scan reload <id>` after editing a QML file the
manifest names, and `rescan <id>` after editing the manifest. The engine caches
sibling QML files that the manifest does not name, so after editing or adding one,
`dms restart` instead. `jq . plugin.json` is a fast syntax check; QML errors print to
the journal with file and line. A popout can be opened and captured without a pointer
(`dms ipc call widget toggle <id>`, then `dms screenshot full --stdout > out.png`);
keyboard input cannot be scripted into it, so test keys by hand.

Plugin enablement and settings persist in `~/.config/DankMaterialShell/plugin_settings.json`
and runtime state in `~/.local/state/DankMaterialShell/plugins/<id>_state.json`. Both
are written by the shell; change them through the plugin's own settings page or
`dms ipc call plugins`, not by hand while the shell runs.

## Publishing

A plugin only needs to exist in the plugins directory to run. To publish it to the DMS
plugin registry so others can `dms plugins install` it, the plugin needs its own
repository and a registry entry; the registry's `CONTRIBUTING.md`
(github.com/AvengeMedia/dms-plugin-registry) has the format. Shipping it as a ZZ
default is repository work under `~/.zz` with its own guide, not this skill.
