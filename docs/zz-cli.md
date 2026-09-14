# ZZ Command-Line Utility

`zz` provides post-install maintenance and troubleshooting commands.

## Commands

| Command | Purpose |
| --- | --- |
| `zz doctor` | Check desktop and installation readiness. |
| `zz logs` | Print the path to the latest installer log. |
| `zz debug` | Create a sanitized local debug bundle. |
| `zz first-run` | Resume unfinished first-login actions using independent, input-aware completion state. |
| `zz defaults` | Reapply default applications and browser preferences. |
| `zz dotnet` | Manage .NET development utilities. |
| `zz ssh` | Set up, inspect, or remove key-only SSH access to this machine. |
| `zz refresh` | Replace one user-owned config with the current ZZ default, backing it up first. |
| `zz update` | Update ZZ itself, packages, or developer tools. |
| `zz app` | Install or remove one catalog application without rerunning the whole install. |
| `zz agent` | Launch the default coding agent, or choose which one that is. |
| `zz crash` | Announce process crashes and hand a core dump to the default coding agent. |

Run `zz --help` to list commands or `zz commands --json` for machine-readable
command metadata.

The desktop shell exposes the same commands through the ZZ menu: click the
ZZ button in the bar (a popout under it) or press Super+Z (centered, like
the launcher), walk the groups, and pick a row; it runs in a terminal window that stays
open until a key is pressed, unless the row starts an interactive program
such as an editor, a monitor, or the coding agent, whose window closes when
it exits. Typing `zz` in the
launcher searches the same rows. Super+Z is part of the seeded keybinds:
an install seeded before the menu shipped keeps its own
`~/.config/niri/dms/binds.kdl`, so add the bind there (Settings > Keybinds,
action `dms ipc call widget toggleWith zzMenu root`) or run
`zz refresh niri/dms/binds.kdl`; `zz doctor` warns while it is missing. See
`docs/design/dms-integration.md` for the plugin.

## Logs

```bash
zz logs
zz logs --tail
zz logs --follow
zz logs --tail --lines 200
```

## Debug bundle

```bash
zz debug
```

The command prints the path to a compressed bundle under
`~/.local/state/zz-fedora/debug`. Sensitive-looking values are redacted, but
review the bundle before sharing it.

## .NET development certificate

```bash
zz dotnet devcert status
zz dotnet devcert create
```

## SSH access

```bash
zz ssh setup
zz ssh setup --key "ssh-ed25519 AAAA... user@host"
zz ssh status
zz ssh remove
```

A fresh install does not accept SSH connections: the Kickstart disables
`sshd.service`, and `zz doctor` warns when the server is enabled without the
password-login restriction below. `zz ssh setup` asks whether to fetch the
public keys GitHub publishes for a username (`https://github.com/<user>.keys`)
or to paste one key, shows the fingerprints and asks before authorizing them,
writes them to `~/.ssh/authorized_keys`, installs the OpenSSH server if
needed, generates the host keys a never-started server still lacks (through
`sshd-keygen.target`, the same unit `sshd.service` pulls in), then writes
`/etc/ssh/sshd_config.d/10-zz-fedora-hardening.conf` to turn password and
keyboard-interactive logins off. The drop-in is validated with `sshd -t` and
checked against `sshd -T` before the server is enabled, and removed again if
sshd would not apply it. Fedora's firewalld zones already
allow the ssh service; the command adds it only where it is missing. `--key`
skips every prompt for unattended use.

Keys imported from GitHub are marked with the account name on their line.
Rerunning `zz ssh setup` for the same account replaces exactly those lines
with the account's current key list, so one rerun per host picks up a device
you added on GitHub and drops one you removed. Pasted keys are never touched.
Adding a device is therefore `gh auth login` on it, choosing SSH so the CLI
generates and uploads its key, followed by `zz ssh setup` on each host.

`zz ssh remove` disables the server and deletes the drop-in; it asks before
removing the authorized keys (`--remove-keys` and `--keep-keys` answer for
scripts). The openssh packages stay installed because they also provide the
client.

## Coding agent

```bash
zz agent                       # the default agent in a new terminal window
zz agent run --inline          # the same, in this terminal
zz agent prompt "Review this"  # start it with a task
zz agent default               # which agent that is
zz agent default codex         # choose one
zz agent list                  # the supported agents, installed and default state
```

The default coding agent is the one the desktop launches: the crash
notifications below hand their diagnosis to it, and the ZZ menu's Agent group
starts it. ZZ picks none for you. The first login sends a one-time
notification, "Set your default coding agent", whose click opens the ZZ menu
at its Agent group; `zz agent invite` is that notification, and it sends
nothing once an agent is chosen or while none of the three is installed.

The Agent group is built from `zz agent list --json`: a "Launch agent
(Claude Code)" row naming the current default, and a "Set default agent"
submenu with one row per installed agent (Claude Code `claude`, Codex
`codex`, OpenCode `opencode`), the current one marked, that sets the choice
and confirms it with a notification. The Agent and Crashes groups appear
only once one of the three agents is installed. The choice is kept in
`~/.config/zz-fedora/agent`.

Agents launched this way run in their own don't-stop-to-ask mode
(`claude --permission-mode auto`, `codex --approve-for-me`,
`opencode --auto`), so expect them to act. The terminal window carries the
app id `zz-agent` for window rules.

## Crash diagnosis

```bash
zz crash list                  # the core dumps systemd-coredump keeps
zz crash diagnose latest       # hand the most recent one to the default agent
zz crash diagnose 4242         # or one PID from the list
zz crash mute nautilus         # silence one program; `off` lifts it, no argument lists
zz crash capture off           # silence every program; `on`, `toggle`, `status`
```

The `crash-diagnosis` choice in the AI category (selected by default) links the
`zz-crash-watch` user service, which follows the journal for systemd-coredump
entries. When one of your programs dumps core, a critical notification says
"<program> crashed. Click to diagnose with AI"; the click opens the default
agent in a terminal with the crash facts (process, PID, binary, signal, time)
and the shipped `diagnose-crash` skill, which walks the agent through
`coredumpctl` and symbolization against Fedora's debuginfod, then has it
explain the cause, say how to address it, and offer to apply a fix (asking
first). The skill is personal assistance only: it never files issues or
reports crashes anywhere.

Crashes belonging to other users, a program muted with `zz crash mute`, a name
matching `ZZ_CRASH_IGNORE` (an extended regex), and repeats of one program
within `ZZ_CRASH_DEDUPE_SECONDS` (60) are not announced; until a default
agent is chosen nothing is, since the toast has nothing to offer.

`zz crash capture off` stops the watcher and writes the flag the unit checks
with `ConditionPathExists`, so it stays off across logins without the unit
being disabled; `zz crash diagnose` still works by hand. Mutes are per
program, keyed on the binary's basename (a process name is truncated to 15
characters), and live under `~/.local/state/zz-fedora/crash-ignore/`; the
diagnosis ends by offering one for the program it just explained. The ZZ
menu's Crashes group carries the same commands. Symbolization needs `gdb`
and the debuginfod client, which the choice installs.

## Updates

```bash
zz update zz
zz update all
zz update all --dry-run
zz update all --cleanup
```

`zz update zz` is intentionally separate from `zz update all`. It requires a
clean `~/.zz` Git checkout, fetches its upstream branch, and fast-forwards the
ZZ-managed tree. It then loads the saved selections, builds a fresh plan
from the updated catalog and configuration manifest, and applies that plan
idempotently. This may request root privileges when the current ZZ plan
requires system changes.

`zz update all` upgrades the broader set of installed system packages and
developer tools. `zz update zz` applies the installer in update mode: required
base work and managed configuration converge, while optional software sources,
packages, and custom installation actions are skipped. An optional application
that the user deliberately removed is therefore not reinstalled from its saved
selection, and application defaults are reapplied only for optional software
that remains installed.

If a saved category or choice no longer exists in the current catalog, update
mode reports it, removes it from the saved selections, and continues. Explicit
unknown values passed through `--select` remain errors. ZZ does not uninstall
software merely because its former choice was removed from the catalog.

There are no product versions or release channels: the current upstream Git
branch is the update source.

Package/tool update targets are `dnf`, `flatpak`, `brew`, `npm`, `dotnet`,
`dotnet-sdk`, `dotnet-tools`, `claude`, and `cleanup`. Run `zz update --help`
for details.

## Installing and removing applications

```bash
zz app list
zz app install brave
zz app remove office/pinta --dry-run
```

`zz app` changes one wizard choice at a time on an installed system. A
choice is named by its id (`zed`, `spotify`) or by `category/id` when the
same id exists in more than one category; `zz app list` shows every choice
with its category, whether the saved selections include it, and whether it
is installed right now.

`zz app install` adds the choice to the saved selections, then applies only
that choice's units and their dependencies: it enables the sources they
need, installs their packages and Flatpaks, runs their actions, and finally
converges managed configuration and desktop defaults the way `zz update zz`
does. The rest of the plan is not re-run. `zz app remove` takes the choice
out of the saved selections and removes the packages, Flatpaks, Homebrew
and npm packages, user services, and product links that no remaining
choice or base unit still needs. Bootstrap prerequisites and anything
another selected choice shares are kept, a native package that other
installed software still depends on is kept as well (rpm's own dependency
resolution decides, so nothing is pulled out from under a package outside
the choice), and units installed by other custom actions (direct
installers) are reported as left in place. Both
commands list the resolved choices and ask for confirmation first; `--yes`
skips the prompt. Both accept `--dry-run`, which prints the commands
without a prompt and leaves the saved selections untouched, and both need
root for package changes.

The desktop menu's Apps group lists the same choices per category; each
row installs the choice when it is absent and removes it when it is
present, in a terminal.

## Refreshing user configuration

```bash
zz refresh --list
zz refresh ghostty/config
```

`zz refresh` only exposes user-owned seeded files. If the existing file
differs, it writes an adjacent `.bak.<timestamp>` backup before installing
the default from `~/.zz`. ZZ-managed linked files update directly with
Git and are not refresh targets.
