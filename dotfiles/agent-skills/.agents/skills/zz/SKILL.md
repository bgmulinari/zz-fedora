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
  screenshots, and user-facing zz commands (zz doctor, zz refresh, zz update, zz logs,
  zz agent, zz crash).
  Excludes ZZ source development in ~/.zz and the repository's own test or catalog work.
---

# ZZ Skill

Manage a ZZ Fedora desktop: Fedora Workstation hardware support, the Niri scrolling
compositor, and DankMaterialShell (DMS) as bar, launcher, notifications, lock screen,
OSD, settings UI, and theming engine, with Ghostty as the terminal.

## Scope

This skill covers the user-facing surface of an installed ZZ desktop: the files under
`~/.config/niri/`, `~/.config/DankMaterialShell/`, `~/.config/ghostty/`,
`~/.config/starship.toml`, `~/.config/btop/`, and `~/.config/fastfetch/`; the shell
fragments in `~/.shellrc.d/`, `~/.zshrc.d/`, and the linked
`~/.config/zz-fedora/shell.d/`; the look of the desktop (themes, wallpaper, accent,
icon theme, light/dark mode, fonts); the shell's surfaces (bar, launcher,
notifications, control center, lock screen, idle, night light); window behavior,
workspaces, and outputs; screenshots, clipboard history, and registry plugins; and
the user-facing `zz` commands (`zz doctor`, `zz refresh`, `zz update`, `zz logs`,
`zz defaults`, `zz agent`, `zz crash`). Read the matching topic guide before editing
any of them.

## Topic Guides

Deeper instructions for common areas live next to this file. Read the matching guide
before starting:

- [`niri.md`](niri.md) - compositor config, overrides, keybinds, window rules, displays
- [`dms.md`](dms.md) - the shell: settings, bar, launcher, plugins, lock, idle, notifications
- [`theming.md`](theming.md) - themes, wallpaper, accent, icon theme, what follows the palette
- [`shells.md`](shells.md) - Ghostty, Bash and Zsh fragments, Starship, btop, fastfetch, editors

## Where edits go

`~/.zz` is a Git checkout that `zz update zz` fast-forwards, and it refuses to update
a dirty checkout. For end-user customization, read it freely but leave it unmodified:
an edit there blocks updates until it is reverted, and it changes the product default
behind every file that links into it.

```
~/.zz/                      # Product checkout: read, do not edit
├── bin/zz.d/               # Source of every zz command
├── dotfiles/               # Live product defaults (linked or included from ~/.config)
├── templates/              # Seeds for user-owned files (what `zz refresh` restores)
├── catalog/                # Install units and software sources
├── config/managed-config.tsv   # Which path ZZ owns, and how
└── docs/dotfiles-layering.md   # The ownership model, worth reading once
```

Reading it answers most questions before an edit:
- Understand a command: `cat ~/.zz/bin/zz.d/refresh`
- See the product default before overriding it: `cat ~/.zz/dotfiles/niri/.config/niri/cfg/layout.kdl`
- See what a seed looked like originally: `cat ~/.zz/templates/niri/dms-binds.kdl`
- Check who owns a path: `grep 'niri' ~/.zz/config/managed-config.tsv`

Personal changes go in the user-owned locations:
- `~/.config/niri/local.kdl` - personal Niri overrides (loaded last, wins)
- `~/.config/niri/dms/binds.kdl` - keybinds (also editable in DMS Settings > Keyboard Shortcuts)
- `~/.config/DankMaterialShell/settings.json` - DMS settings, owned by the Settings UI
- `~/.config/ghostty/local` - personal Ghostty settings
- `~/.shellrc.d/`, `~/.zshrc.d/` - personal shell fragments
- `~/.config/DankMaterialShell/plugins/`, `~/.config/DankMaterialShell/themes/` - user plugins and themes

A path that resolves into `~/.zz` (`readlink -f <path>`) is a product link, not a
personal file; each topic guide names the personal override for it.

## Privilege Escalation

Post-install customization rarely needs root. When it does (a package, a system
service, a file under `/etc`), run the command through `pkexec`. The desktop shell
runs a polkit authentication agent, so the user gets a graphical password prompt
even though your shell has no terminal for `sudo` to ask on. Do not tell the user
you cannot run a command because it needs `sudo`; do not ask them to run it for
you; run it with `pkexec`.

**Before every `pkexec`, print the full command and the reason for it**, so that
the password prompt the user is about to see is explained by what they just read:

```
Running with elevated permissions:
  pkexec dnf install -y gdb
Reason: symbolizing the core dump needs gdb, which is not installed.
```

Then run it. Rules:

- One command per `pkexec`, spelled out in full; never a script the user has not
  seen. For a pipeline or a redirection, pass the exact script text through
  `pkexec bash -c '<script>'` and print that text.
- Use absolute paths. `pkexec` runs the program with a minimal environment and
  none of your shell's variables, so nothing in it may depend on your `PATH`,
  `HOME`, or the current directory.
- If `pkexec` fails to authenticate, the user declined; stop and say so. If it
  reports that no authentication agent is available (a session reached over SSH,
  for example), print the command for the user to run themselves.
- Never wrap `zz` commands that already elevate themselves (`zz update`,
  `zz app`, `zz ssh`, `zz dotnet devcert`); they ask for the password in their
  own terminal.

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
| `zz update zz` | Fast-forward `~/.zz` and re-apply required config; installs only catalog defaults added since the selections were saved | `zz update zz` |
| `zz update all` | Update dnf, flatpak, brew, npm, .NET, Claude Code | `zz update all --dry-run` |
| `zz app list` | Every catalog choice with its selected and installed state | `zz app list` |
| `zz app install <choice>` | Install one catalog choice and save it; only its units run; asks first (`--yes` skips) | `zz app install brave` |
| `zz app remove <choice>` | Remove one choice and what no other choice needs; unsave it; asks first | `zz app remove office/pinta --dry-run` |
| `zz first-run` | Resume unfinished first-login setup (theme artifacts, GTK opt-in, greeter profile) | `zz first-run` |
| `zz defaults` | Reapply default applications and browser preferences | `zz defaults` |
| `zz ssh setup` | Key-only SSH access: import a GitHub account's keys (rerun to sync adds and removals) or paste one, start sshd, turn password logins off | `zz ssh setup` |
| `zz ssh remove` | Disable sshd and its password-login restriction; asks before removing keys | `zz ssh remove` |
| `zz agent` | Launch the default AI agent in a terminal; `default` chooses it (claude, codex, opencode; none until chosen), `prompt` starts it with a task | `zz agent default codex` |
| `zz crash list` | Core dumps systemd-coredump keeps | `zz crash list` |
| `zz crash diagnose` | Hand one core dump to the default agent with the diagnose-crash skill | `zz crash diagnose latest` |
| `zz crash mute` | Silence crash notifications for one program (`off` lifts it; no argument lists) | `zz crash mute nautilus` |
| `zz crash capture` | Turn the crash notifications on or off for every program | `zz crash capture off` |
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

### Reset to defaults (confirm with the user first)

```bash
zz refresh --list                 # what can be restored
zz refresh niri/config.kdl        # backs up as <file>.bak.<timestamp>, restores, prints the diff
zz refresh dms                    # every DMS setting (settings, plugins, session); restarts dms.service
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
4. **Is it a keybind?** `~/.config/niri/dms/binds.kdl` or Settings > Keyboard Shortcuts; see [`niri.md`](niri.md)
5. **Is it a theme or plugin?** Use the DMS registry (Settings > Theme / Plugins, `dms plugins`); see [`theming.md`](theming.md)
6. **Is it a package?** `pkexec dnf install <pkg>` (announce it first, see Privilege Escalation) or `flatpak install`; ZZ does not wrap package installs after setup
7. **Went wrong?** `zz refresh <file>` after confirming with the user, then `zz doctor`

## Out of Scope

ZZ source development is a different job with its own guide: editing files in
`~/.zz/` (`catalog/`, `dotfiles/`, `templates/`, `lib/`, `modules/`, `bin/`,
`tests/`), shipping a new plugin, theme, or default with ZZ, or running `install.sh`
and the test suites. For that, follow `~/.zz/AGENTS.md` and the task guides it
indexes.

## Example Requests

- "Switch to light mode" -> `dms ipc call theme light`
- "Set this image as wallpaper" -> `dms ipc call wallpaper set <path>`
- "Make the gaps bigger" -> add `layout { gaps 12 }` to `~/.config/niri/local.kdl`, then `niri validate`
- "Open Spotify with Super+Shift+M" -> check `dms keybinds show niri`, add the bind to `~/.config/niri/dms/binds.kdl`, `niri validate`
- "Float the calculator" -> `window-rule` in `~/.config/niri/local.kdl` matched on the `app-id` from `niri msg windows`
- "Move the bar to the bottom" -> Settings > Bar, or `dms ipc call bar setPosition index 0 bottom`
- "Change my terminal font size" -> `font-size = 13` in `~/.config/ghostty/local`
- "Reset my niri config" -> confirm, then `zz refresh niri/config.kdl`
- "Reset DMS to the defaults" -> confirm, then `zz refresh dms`
- "Update everything" -> `zz update all`, then `zz update zz`, then `zz doctor`
- "Add a CPU temperature widget" -> Settings > Plugins > Browse, or `dms plugins browse`
