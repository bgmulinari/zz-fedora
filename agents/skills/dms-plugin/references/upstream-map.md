# Upstream reference map

Paths are relative to the checkouts synced by `scripts/sync_refs.sh`:

- `DMS=/files/dev/ref-repos/AvengeMedia/DankMaterialShell` (tag matching `dms version`)
- `COMMON=/files/dev/ref-repos/AvengeMedia/dank-qml-common` (the `dank-qml-common`
  submodule, synced at the commit the DMS tree pins; the shallow DMS clone leaves
  `$DMS/dank-qml-common/` empty)
- `QS=/files/dev/ref-repos/quickshell-mirror/quickshell` (commit from `qs --version`)
- `REG=/files/dev/ref-repos/AvengeMedia/dms-plugin-registry` (master)

Treat every path as read-only. Use `rg`, `sed -n`, `git -C ... log`; never build,
edit, or write inside them. Versions are recorded in the sync output; cite them in the
design doc when a decision depends on upstream behavior.

## DMS plugin API

| Question | File |
| --- | --- |
| Full plugin guide (types, manifest, settings, persistence, theme, popouts, CC, commands) | `$DMS/.agents/skills/dms-plugin-dev/SKILL.md` |
| Manifest field reference and schema | `$DMS/.agents/skills/dms-plugin-dev/references/plugin-manifest-reference.md`, `$DMS/quickshell/PLUGINS/plugin-schema.json` |
| Widget: bar pills, popouts, click actions, Control Center | `$DMS/.agents/skills/dms-plugin-dev/references/widget-plugin-guide.md` |
| Launcher: getItems/executeItem, triggers, icons, tile view | `.../references/launcher-plugin-guide.md` |
| Desktop widgets: sizing, edit mode, persistence | `.../references/desktop-plugin-guide.md` |
| Daemons: event-driven services, process execution | `.../references/daemon-plugin-guide.md` |
| Setting components (String, Toggle, Selection, Slider, Color, List, ListWithInput) | `.../references/settings-components-reference.md` |
| Theme properties and common widgets | `.../references/theme-reference.md`, `$DMS/quickshell/PLUGINS/THEME_REFERENCE.md` |
| Data persistence tiers (pluginData, state, global vars) | `.../references/data-persistence-guide.md` |
| PopoutService API | `.../references/popout-service-reference.md`, `$DMS/quickshell/PLUGINS/POPOUT_SERVICE.md` |
| Variants, JS utilities, qmldir, IPC, multi-file plugins | `.../references/advanced-patterns.md` |
| Scaffold templates per type | `$DMS/.agents/skills/dms-plugin-dev/assets/templates/{widget,daemon,launcher,desktop}/` |

The guides describe intent; the QML decides. Two known places where the v1.6.0 guide
and the source disagree, so read the source before relying on a guide example:

- Launcher context menus: the guide shows `getContextMenuActions` returning
  `action: "type:data"` strings routed through `executeItem`, but
  `$DMS/quickshell/Modals/DankLauncherV2/LauncherContextMenu.qml`
  (`executePluginAction`) only runs an `action` that is a function. Return
  `{ label, icon, action: () => ..., closeLauncher }` objects.
- `popoutService` is not declared by `PluginComponent`; a plugin that reads it must
  declare `property var popoutService: null` or it stays null (the validator errors).
- Launcher refresh: the guide says to emit the plugin's `itemsChanged()` when async
  results arrive, but nothing in the shell connects to it. The launcher controller
  (`$DMS/quickshell/Modals/DankLauncherV2/Controller.qml`) listens to
  `PluginService.requestLauncherUpdate(pluginId)`, so a launcher that loads items
  asynchronously must call `pluginService.requestLauncherUpdate(pluginId)` after
  updating its cache, or the list stays stale until the next keystroke.

## Shared components in dank-qml-common

| Question | File |
| --- | --- |
| `Proc.runCommand(id, command, callback, debounceMs, timeoutMs, owner)`, `Proc.release(id)` | `$COMMON/DankCommon/Common/Proc.qml` |
| Shared `Theme` (colors, spacing, fonts, radii) | `$COMMON/Common/Theme.qml` |
| `Paths`, `I18n`, `CacheData`, `Anims` | `$COMMON/Common/*.qml` (thin re-exports) and `$COMMON/DankCommon/Common/*.qml` (implementations, plus `Log`, `Style`, `Fonts`, `Host`) |
| `qs.Widgets` components (StyledText, StyledRect, DankIcon, DankButton, DankTextField, ...) | `$COMMON/DankCommon/Widgets/` |
| Shared modals and session helpers | `$COMMON/DankCommon/Modals/`, `$COMMON/DankCommon/Session/` |
| Bar-specific theme helpers (`widgetIconColor`, `widgetInactiveIconColor`, `barTextSize()`, `tempWarning`, `tempDanger`) | `$DMS/quickshell/Common/Theme.qml` only; they are not in the shared Theme |
| What a bar pill already gets for free (background, padding, hover) | `$DMS/quickshell/Modules/Plugins/BasePill.qml` and `PluginComponent.qml` |

DMS re-exports these under `qs.Common`, `qs.Widgets`, and `qs.Services`; plugins keep
importing the `qs.*` names regardless of where a component is implemented. When a
property is missing from the shared Theme, check the DMS Theme before concluding it
does not exist.

## DMS internals worth reading when behavior is unclear

| Topic | File |
| --- | --- |
| Discovery, load gating, startup checks, state files, IPC target | `$DMS/quickshell/Services/PluginService.qml` |
| Where `enabled` and plugin settings persist (`plugin_settings.json`) | `$DMS/quickshell/Common/SettingsData.qml` (`pluginSettingsPath`, `setPluginSetting`) |
| Base components injected into plugins | `$DMS/quickshell/Modules/Plugins/PluginComponent.qml`, `DesktopPluginComponent.qml`, `PluginPopout.qml`, `PluginSettings.qml` |
| How the bar resolves a widget id to a plugin component | `$DMS/quickshell/Modules/DankBar/WidgetHost.qml` |
| Settings UI for plugins (scan, enable, settings accordion) | `$DMS/quickshell/Modules/Settings/PluginsTab.qml` |
| Built-in plugins as worked examples | `$DMS/quickshell/Modules/BuiltinDesktopPlugins/`, `$DMS/quickshell/Modules/ControlCenter/BuiltinPlugins/` |
| Example plugins (composite, startup check, launcher tiles, variants, daemon, notes) | `$DMS/quickshell/PLUGINS/*/` |
| Shell IPC surface (`dms ipc ...`) | `$DMS/docs/IPC.md` |
| Go side of plugin install/registry commands | `$DMS/core/internal/plugins/`, `$DMS/core/internal/server/plugins/` |

## Quickshell runtime types

| Type | File |
| --- | --- |
| `Process`, `running`, `command`, `stdout`/`stderr` parsers, `exited` | `$QS/src/io/process.hpp` |
| `StdioCollector`, `SplitParser`, `DataStream` | `$QS/src/io/datastream.hpp` |
| `FileView` (read/write files, `setText`, watch) | `$QS/src/io/fileview.hpp`, `$QS/src/io/FileView.qml` |
| `Socket`, `SocketServer` | `$QS/src/io/socket.hpp` |
| `IpcHandler` (what `dms ipc` calls into) | `$QS/src/io/ipchandler.hpp` |
| `Quickshell.env`, `execDetached`, reload hooks | `$QS/src/core/qmlglobal.hpp` |
| Module overview and QML docs comments | `$QS/src/io/module.md` and the `///` doc comments in each header |

Header doc comments are the authoritative property list for the installed revision;
the online docs may describe a newer release.

## Plugin registry (for publishing upstream, not for ZZ shipping)

| Question | File |
| --- | --- |
| Entry format (id, capabilities, category, repo, dependencies, compositors, distro, screenshot) | `$REG/plugins/*.json` |
| Contribution rules, translations via POEditor | `$REG/CONTRIBUTING.md` |
| Existing plugins for prior art by category | `$REG/README.md` |

ZZ-shipped plugins do not need a registry entry. If the user also wants to publish
one, the plugin must live in its own repository; the registry entry then points at
that repository, not at this one.
