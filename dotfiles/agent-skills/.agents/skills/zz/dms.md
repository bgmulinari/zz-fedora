# DMS: Settings, Bar, Launcher, Plugins, Lock, Idle, Notifications

Read this before changing the bar, launcher, notifications, lock screen, idle behavior,
control center, or anything under `~/.config/DankMaterialShell/`.

DankMaterialShell runs as one long-lived Quickshell process (`dms.service`, bound to
the Niri session). It owns the bar (DankBar), launcher (spotlight), notification
daemon, lock screen, OSD, control center, clipboard history, and the Settings UI, and
it regenerates the `~/.config/niri/dms/*.kdl` fragments and theme outputs.

```
~/.config/DankMaterialShell/
├── settings.json           # Owned by the Settings UI (Mod+Comma). Prefer the UI or
│                           # `dms ipc call settings set <key> <value>` for scalars
├── plugin_settings.json    # Plugin enablement and per-plugin settings
├── plugins/<Name>/         # User-installed plugins (registry or manual)
└── themes/<id>/theme.json  # Registry themes (ZZ ships catppuccin as a product link)
~/.local/state/DankMaterialShell/session.json   # Wallpaper, dark mode, pinned apps
```

**Commands:** `dms restart`, `dms doctor`, `dms ipc --help`,
`dms ipc call settings focusOrToggle`

## Settings file rules

- `settings.json` is rewritten by DMS from memory on any change: an external edit made
  while DMS runs is silently undone. Use the Settings UI, `dms ipc call settings set`,
  or edit with DMS stopped (`dms kill`, edit, `dms run` or re-login)
- `dms ipc call settings set` handles scalars only (no objects or arrays) and skips
  the hooks that regenerate `dms/*.kdl`; for structured keys use the UI
- `dms ipc call settings dump` prints the effective settings; `settings get <key>`
  reads one
- Keys absent from the file inherit the DMS default, so a missing key is not a bug

## Bar

Bar layout, sections, widgets, position, auto-hide, and per-monitor bars are in
Settings > Bar. Live control:

```bash
dms ipc call bar status
dms ipc call bar setPosition index 0 bottom   # selector: id|name|index, then the value
dms ipc call bar toggleAutoHide index 0
dms ipc call widget list                      # widgets and their visibility
```

Widgets are referenced by id in the bar sections; plugins appear by their plugin id
once enabled. `dms ipc call bar reveal` and `hide` are handy from keybinds.

## Launcher, control center, notifications

```bash
dms ipc call spotlight toggle            # launcher (Mod+D / Mod+Space)
dms ipc call control-center toggle       # Mod+S
dms ipc call notifications toggle        # Mod+N
dms ipc call notifications toggleDoNotDisturb
dms ipc call clipboard toggle            # Mod+V, history managed by DMS
dms ipc call processlist focusOrToggle   # Mod+M
dms ipc call powermenu toggle            # Mod+Shift+Q
```

Launcher plugins add trigger-prefixed searches (for example `=` for the calculator);
`dms ipc call plugins list` shows what is loaded.

## Lock, idle, night light

```bash
dms ipc call lock lock                   # Mod+Alt+L
dms ipc call lock status
dms ipc call inhibit toggle              # keep the screen awake
dms ipc call night toggle                # night light; setDayTemp / setTargetTemp / getSchedule
```

Idle timeouts, lock-on-idle, and DPMS behavior are in Settings > Power / Lock; DMS runs
its own idle daemon, so do not add swayidle or another locker.

## Plugins

Browse and install from the registry with `dms plugins browse` /
`dms plugins install <id>` or Settings > Plugins > Browse, then enable the plugin and
add it to a bar section from the same page. Manual plugins go in
`~/.config/DankMaterialShell/plugins/<Name>/` (a directory with `plugin.json`).

```bash
dms plugins list
dms ipc call plugin-scan scan            # rescan after manual changes
dms ipc call plugin-scan status <id>     # loaded, type, error
dms ipc call plugins enable <id>
```

The ZZ menu is one of them: click the ZZ button in the bar or press Super+Z
for a menu of the `zz` commands, Niri and shell chores, system monitors, and docs
links, navigated group by group with a search that narrows the current group first
(Super+Z opens it centered like the launcher, the button under the bar;
`dms ipc call widget toggleWith zzMenu root` is the keybind, `openWith zzMenu niri`
opens a group, `widget toggle zzMenu` the popout; typing `zz` in the launcher searches the same rows).
Super+Z is a seeded keybind: an install whose `~/.config/niri/dms/binds.kdl` predates the
menu lacks it until the user adds the bind or runs `zz refresh niri/dms/binds.kdl`
(`zz doctor` warns). Add or override rows
and groups in `~/.config/zz-fedora/menu.json`
(entries keyed by dotted id; `action`, `terminal`, `when`, `label`, `icon`); the
format is documented in `~/.zz/dotfiles/dms/.config/DankMaterialShell/plugins/ZzMenu/README.md`.

Plugins ZZ ships arrive as symlinks into `~/.zz`; treat them as read-only like any
other product link. To customize one, copy it to a new directory with a new `id`.

## Notifications from scripts

```bash
dms notify "Title" "Body"                # desktop notification through DMS
dms ipc call toast info "Short message"  # transient toast
```

## Restarting and diagnosing

```bash
dms restart
dms doctor
journalctl --user -u dms.service -n 100 --no-pager
systemctl --user status dms.service
```

`dms.service` is wanted by `niri.service`, not enabled on its own, so it starts only
inside a Niri session; do not `systemctl --user enable` it.
