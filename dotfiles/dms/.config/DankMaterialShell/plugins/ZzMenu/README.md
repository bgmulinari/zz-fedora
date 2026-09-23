# ZZ Menu

The desktop's command menu. Click the **ZZ** button on the right of the bar,
next to the system tray, and a menu drops down under it; press Super+Z and the same menu opens
centered on the screen over a dimmed background, the way the launcher
does. The root is short and grouped by what you want to do:

| Group | What is in it |
|---|---|
| Add or remove apps | Install (the catalog applications not installed yet) and Remove (the installed ones), each by category (`zz app`) |
| Update | All package managers and tools (`zz update all`), ZZ itself, cleaning up unused packages, and one updater at a time |
| Desktop | Edit the personal Niri overrides (checked when the editor closes), pick-a-window facts for window rules, outputs, restart the shell |
| Setup | The AI agent, SSH access, the .NET dev certificate, resetting the default apps (file types, terminal, browser) or a config to the ZZ default; pick apps one by one in Settings > Default Apps |
| Troubleshoot | Doctor, crashes, installer/compositor/shell/boot logs, plugin rescan, re-running first-login setup, the debug bundle |
| Learn | The keyboard shortcut list and documentation links |

The menu does not mirror the CLI: variants you rarely need from a menu
stay in `zz` itself (`zz --help`). The terminal a row opens asks for
confirmation before anything changes.

The menu is navigated like a menu: a group opens as a submenu with a
breadcrumb and a back arrow. Arrow keys (or Ctrl+N/P, Ctrl+J/K) move, Enter
opens the row or the group, Backspace or Left goes up, Escape clears the
search, then goes up, then closes. Typing searches the current group first
and everything below it after that, so `out` inside Desktop finds Outputs
and `desk out` from the root finds it too. The mouse works throughout.

A row runs detached, or, when marked `terminal`, in a terminal window that
stays open until a key is pressed so the output and any sudo prompt are on
screen. Right-clicking the bar button opens a terminal.

The same rows are reachable from the app launcher by typing the trigger
(`zz` by default) followed by a search (`zz upd dnf`, `zz reset ghostty`).
That surface is search only: the launcher closes after any plugin row runs,
so it cannot hold a submenu open, and each row shows its group path in the
subtitle instead.

## Files

| File | Role |
|---|---|
| `ZzMenuWidget.qml` | The bar button, its popout, and the centered modal |
| `ZzMenuPanel.qml` | The menu inside the popout: tree, navigation, search, keys |
| `ZzMenuLauncher.qml` | The launcher surface behind the trigger |
| `ZzMenuInventory.qml` | Loads the rows for either surface and runs them |
| `scripts/zz-menu-inventory` | Resolves `menu.json` plus the user overlay into groups and rows |
| `scripts/zz-menu-run` | Opens a terminal that stays open for a row's output |

`zz-menu-inventory` reads `menu.json` next to this file, merges the user's
overlay on top, evaluates each `when` guard once per load in a single
shell, and expands provider groups.

## Shell IPC

The widget answers the shell's widget IPC, which is what the keybind uses:

```bash
dms ipc call widget toggleWith zzMenu root   # the centered menu (Super+Z)
dms ipc call widget openWith zzMenu desktop  # centered, at a group
dms ipc call widget openWith zzMenu setup.agent  # a nested group
dms ipc call widget toggle zzMenu            # the popout under the bar button
```

## Menu definition

`menu.json` is an object keyed by entry id. Dotted ids are the tree:
`update.one.dnf` sits under `update.one`, and groups nest as deep as the ids do. An
entry with an `action` is a row, one with a `provider` is a group whose rows
are enumerated at load time, and anything else is a plain group. Providers:
`refresh` lists `zz refresh --list`; `agent` reads `zz agent list --json`
for a launch row and a default-agent picker; `apps` reads `zz app list --json` and
builds an Install group of the absent choices and a Remove group of the
installed ones, each with one subgroup per category.

| Field | Meaning |
|---|---|
| `label` | Row title; defaults to the last id segment |
| `description` | Subtitle and search text |
| `icon` | Material Symbols name; inherited from the nearest ancestor when absent |
| `action` | Shell command line, run in a login shell |
| `terminal` | `true` to run the action in a terminal window that stays open |
| `provider` | Runtime row source for a group |
| `aliases` | Extra search words |
| `when` | Shell condition; the entry and everything under it hide when it fails. It runs with `~/.local/bin`, `~/.dotnet`, and `~/.dotnet/tools` ahead of the session PATH and Homebrew behind it, the PATH the terminal runner uses too |

`~/.config/zz-fedora/menu.json` is merged on top entry by entry: reuse a
shipped id to change only the fields you declare (the row keeps its place),
or add new ids to append rows or groups. Edits to either file are picked up
on the next open. A file that fails to parse contributes nothing while the
other keeps working.

## Settings

Settings > Plugins > ZZ Menu: the launcher trigger, and whether the rows
also show in the launcher without a trigger. The Super+Z bind in
`~/.config/niri/dms/binds.kdl` opens the centered menu and does not depend
on the trigger; it is seeded with that file, so an older file needs the
bind added (Settings > Keyboard Shortcuts) or `zz refresh niri/dms/binds.kdl`.

Dependencies: `python3` (the inventory runs with `/usr/bin/python3`) and a
terminal launcher (`xdg-terminal-exec`, falling back to `ghostty`).
