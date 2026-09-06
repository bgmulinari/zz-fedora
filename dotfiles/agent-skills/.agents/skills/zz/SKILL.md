---
name: zz
description: >
  REQUIRED for end-user customization of a ZZ Fedora desktop (Niri compositor +
  DankMaterialShell). Use when editing ~/.config/niri/, ~/.config/DankMaterialShell/,
  ~/.config/ghostty/, ~/.config/starship.toml, ~/.config/btop/, ~/.config/fastfetch/,
  ~/.shellrc.d/, ~/.zshrc.d/, or ~/.config/zz-fedora/. Triggers: Niri, window rules,
  layout, gaps, borders, animations, keybindings, monitors, outputs, DMS, DankBar, the
  bar, launcher, notifications, lock screen, idle, control center, plugins, themes,
  wallpaper, accent colors, icon theme, night light, terminal config, shell prompt,
  screenshots, and user-facing zz commands (zz doctor, zz refresh, zz update, zz logs).
  Excludes ZZ source development in ~/.zz and the repository's own test or catalog work.
---

# ZZ Skill

Manage a ZZ Fedora desktop: Fedora Workstation hardware support, the Niri scrolling
compositor, and DankMaterialShell (DMS) as bar, launcher, notifications, lock screen,
OSD, settings UI, and theming engine, with Ghostty as the terminal.

This skill is for end-user customization on an installed system. It is not for
contributing to ZZ itself.

## When This Skill MUST Be Used

**ALWAYS invoke this skill for end-user requests involving ANY of these:**

- Editing ANY file in `~/.config/niri/` (layout, window rules, animations, input, keybinds)
- Editing ANY file in `~/.config/DankMaterialShell/` (settings, plugins, themes)
- Editing terminal, prompt, or monitor configs (`~/.config/ghostty/`, `~/.config/starship.toml`, `~/.config/btop/`, `~/.config/fastfetch/`)
- Shell startup fragments in `~/.shellrc.d/`, `~/.zshrc.d/`, or the linked `~/.config/zz-fedora/shell.d/`
- Window behavior, gaps, borders, focus ring, animations, workspace and output settings
- Themes, wallpapers, accent colors, icon theme, light/dark mode, fonts
- The bar (DankBar), launcher, notifications, control center, lock screen, idle, night light
- User-facing `zz` commands (`zz doctor`, `zz refresh ...`, `zz update ...`, `zz logs`, `zz defaults`)
- Screenshots, clipboard history, DMS plugins from the registry

**If you're about to edit a config file in ~/.config/ on this system, STOP and use this skill first.**

**Do NOT use this skill for ZZ development tasks** (editing files in `~/.zz/`, the catalog,
managed-config rows, tests, or shipped plugins). Follow `~/.zz/AGENTS.md` and the
repository's task guides for that.

## Topic Guides

Deeper instructions for common areas live next to this file. Read the matching guide
before starting:

- [`niri.md`](niri.md) - compositor config, overrides, keybinds, window rules, displays
- [`dms.md`](dms.md) - the shell: settings, bar, launcher, plugins, lock, idle, notifications
- [`theming.md`](theming.md) - themes, wallpaper, accent, icon theme, what follows the palette
- [`shells.md`](shells.md) - Ghostty, Bash and Zsh fragments, Starship, btop, fastfetch, editors

## Critical Safety Rules

**For end-user customization tasks, NEVER modify anything in `~/.zz/`** - but READING is
safe and encouraged.

`~/.zz` is a Git checkout that `zz update zz` fast-forwards. It refuses to update a
dirty checkout, so any edit there:
- Blocks future updates until reverted
- Is lost or conflicts when the update finally runs
- Changes product defaults for every file that links into it

```
~/.zz/                      # READ-ONLY - NEVER EDIT (reading is OK)
├── bin/zz.d/               # Source of every zz command
├── dotfiles/               # Live product defaults (linked or included from ~/.config)
├── templates/              # Seeds for user-owned files (what `zz refresh` restores)
├── catalog/                # Install units and software sources
├── config/managed-config.tsv   # Which path ZZ owns, and how
└── docs/dotfiles-layering.md   # The ownership model, worth reading once
```

**Reading `~/.zz/` is SAFE and useful** - do it freely to:
- Understand a command: `cat ~/.zz/bin/zz.d/refresh`
- See the product defaults before overriding them: `cat ~/.zz/dotfiles/niri/.config/niri/cfg/layout.kdl`
- See what a seed looked like originally: `cat ~/.zz/templates/niri/dms-binds.kdl`
- Check who owns a path: `grep 'niri' ~/.zz/config/managed-config.tsv`

**Always use these safe locations instead:**
- `~/.config/niri/local.kdl` - personal Niri overrides (loaded last, wins)
- `~/.config/niri/dms/binds.kdl` - keybinds (also editable in DMS Settings > Keybinds)
- `~/.config/DankMaterialShell/settings.json` - DMS settings, owned by the Settings UI
- `~/.config/ghostty/local` - personal Ghostty settings
- `~/.shellrc.d/`, `~/.zshrc.d/` - personal shell fragments
- `~/.config/DankMaterialShell/plugins/`, `~/.config/DankMaterialShell/themes/` - user plugins and themes

Never edit a path that is a symlink into `~/.zz`; check with `readlink -f <path>` first.
Those are product links, and each topic guide names the personal override for them.

## Privilege Escalation

Post-install customization rarely needs root. When it does (a package, a system
service), use `sudo` in a visible terminal where the user can enter a password. Use
`pkexec` only when no terminal is available, such as a command launched from a
graphical agent session. Never wrap `zz` commands that already elevate themselves.

## System Architecture

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **Fedora** | Base OS | `/etc/`, `~/.config/` |
| **Niri** | Wayland scrolling compositor | `~/.config/niri/` |
| **DMS** (DankMaterialShell) | Bar, launcher, notifications, lock, OSD, settings UI, theming | `~/.config/DankMaterialShell/`, `~/.config/niri/dms/` |
| **Ghostty** | Terminal | `~/.config/ghostty/` |
| **matugen** (via DMS) | Generates theme files for Ghostty, btop, Qt, GTK, Starship, editors | `~/.config/matugen/dms/` (drop-ins), outputs under `~/.cache/DankMaterialShell/` |
| **dms-greeter** (greetd) | Login screen, follows the DMS theme | system-managed |
| **Starship, btop, fastfetch** | Prompt, monitor, system info | `~/.config/starship.toml`, `~/.config/btop/`, `~/.config/fastfetch/` |

## Command Discovery

ZZ ships a single `zz` launcher for post-install operations; DMS ships `dms`; Niri ships
`niri`. Prefer these over hand-editing when a command exists.

```bash
# ZZ
zz --help                 # list commands
zz commands --json        # machine-readable command metadata
zz refresh --list         # every user-owned file zz can restore, with its purpose
cat ~/.zz/bin/zz.d/doctor # read a command's source

# DMS
dms --help
dms ipc --help            # every live target: bar, launcher, wallpaper, theme, night, lock, plugins, settings ...
dms ipc call theme toggle
dms ipc call wallpaper set ~/Pictures/wall.jpg

# Niri
niri validate             # check the config before and after every edit
niri msg outputs          # connected outputs, modes, scale
niri msg windows          # open windows with app-id and title (for window rules)
```

### zz commands

| Command | Purpose | Example |
|---------|---------|---------|
| `zz doctor` | Desktop readiness and post-install checks | `zz doctor` |
| `zz refresh` | Restore one user-owned file to the shipped default, backing it up first | `zz refresh niri/config.kdl` |
| `zz update zz` | Fast-forward `~/.zz` and re-apply required config; skips optional software | `zz update zz` |
| `zz update all` | Update dnf, flatpak, brew, npm, .NET, Claude Code | `zz update all --dry-run` |
| `zz app list` | Every catalog choice with its selected and installed state | `zz app list` |
| `zz app install <choice>` | Install one catalog choice and save it; only its units run; asks first (`--yes` skips) | `zz app install brave` |
| `zz app remove <choice>` | Remove one choice and what no other choice needs; unsave it; asks first | `zz app remove office/pinta --dry-run` |
| `zz first-run` | Resume unfinished first-login setup (theme artifacts, GTK opt-in, greeter profile) | `zz first-run` |
| `zz defaults` | Reapply default applications and browser preferences | `zz defaults` |
| `zz logs` | Latest installer log | `zz logs --tail` |
| `zz debug` | Sanitized debug bundle for support | `zz debug` |

## Configuration Locations

Niri config lives in `~/.config/niri/` (see [`niri.md`](niri.md)); the shell is
configured through DMS Settings and `~/.config/DankMaterialShell/` (see
[`dms.md`](dms.md)); terminal, prompt, and shell fragments are covered in
[`shells.md`](shells.md).

## Safe Customization Patterns

### Personal override file

```bash
# 1. Read the product default you are overriding
cat ~/.zz/dotfiles/niri/.config/niri/cfg/layout.kdl

# 2. Add or edit the personal file (create it if missing)
$EDITOR ~/.config/niri/local.kdl

# 3. Validate and confirm
niri validate
```

Same shape for Ghostty (`~/.config/ghostty/local`) and shells (`~/.shellrc.d/<name>`).

### Change it in DMS Settings

For anything DMS owns (bar, widgets, theme, wallpaper, displays, input, lock, idle,
notifications, window rules), open Settings (`Mod+Comma` or
`dms ipc call settings focusOrToggle`) and change it there. DMS then regenerates the
matching `~/.config/niri/dms/*.kdl` fragment and the theme outputs. A hand edit of a
generated file is overwritten on the next change.

### Reset to Defaults -- ALWAYS SEEK USER CONFIRMATION BEFORE RUNNING

```bash
zz refresh --list                 # what can be restored
zz refresh niri/config.kdl        # backs up as <file>.bak.<timestamp>, restores, prints the diff
```

Product links are not refreshable; updating `~/.zz` already refreshes them.

### Update

```bash
zz update zz          # product defaults, links, required config (needs a clean ~/.zz)
zz update all         # packages and tools; --dry-run to preview
zz doctor             # verify afterwards
```

## Troubleshooting

```bash
zz doctor                                   # readiness checks, including DMS
zz logs --tail                              # last installer run
dms doctor                                  # DMS dependencies and payload
journalctl --user -u dms.service -n 100 --no-pager
niri validate                               # config errors
zz first-run                                # rerun unfinished first-login steps
zz debug                                    # bundle for support (review before sharing)
```

If the theme did not reach Ghostty, btop, or Qt after a fresh install, DMS has not
rendered its templates yet: `zz first-run` waits for them; `dms restart` triggers them.

## Decision Framework

1. **Is it a `zz`, `dms`, or `niri` command?** Use it directly
2. **Does DMS own it** (theme, bar, displays, input, lock, idle, window rules from the UI)? Change it in Settings or through `dms ipc`; see [`dms.md`](dms.md)
3. **Is it a config edit?** Edit the personal file (`local.kdl`, `ghostty/local`, `~/.shellrc.d/`), never `~/.zz/` and never a product link
4. **Is it a keybind?** `~/.config/niri/dms/binds.kdl` or Settings > Keybinds; see [`niri.md`](niri.md)
5. **Is it a theme or plugin?** Use the DMS registry (Settings > Theme / Plugins, `dms plugins`); see [`theming.md`](theming.md)
6. **Is it a package?** `sudo dnf install <pkg>` or `flatpak install`; ZZ does not wrap package installs after setup
7. **Went wrong?** `zz refresh <file>` after confirming with the user, then `zz doctor`

## Out of Scope

This skill intentionally does not cover ZZ source development. Do not use it for:
- Editing files in `~/.zz/` (`catalog/`, `dotfiles/`, `templates/`, `lib/`, `modules/`, `bin/`, `tests/`)
- Shipping a new plugin, theme, or default with ZZ
- Running `install.sh` or the test suites

## Example Requests

- "Switch to light mode" -> `dms ipc call theme light`
- "Set this image as wallpaper" -> `dms ipc call wallpaper set <path>`
- "Make the gaps bigger" -> add `layout { gaps 12 }` to `~/.config/niri/local.kdl`, then `niri validate`
- "Open Spotify with Super+Shift+M" -> check `dms keybinds show niri`, add the bind to `~/.config/niri/dms/binds.kdl`, `niri validate`
- "Float the calculator" -> `window-rule` in `~/.config/niri/local.kdl` matched on the `app-id` from `niri msg windows`
- "Move the bar to the bottom" -> Settings > Bar, or `dms ipc call bar setPosition index 0 bottom`
- "Change my terminal font size" -> `font-size = 13` in `~/.config/ghostty/local`
- "Reset my niri config" -> confirm, then `zz refresh niri/config.kdl`
- "Update everything" -> `zz update all`, then `zz update zz`, then `zz doctor`
- "Add a CPU temperature widget" -> Settings > Plugins > Browse, or `dms plugins browse`
