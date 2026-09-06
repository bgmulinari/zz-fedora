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
| `zz refresh` | Replace one user-owned config with the current ZZ default, backing it up first. |
| `zz update` | Update ZZ itself, packages, or developer tools. |
| `zz app` | Install or remove one catalog application without rerunning the whole install. |

Run `zz --help` to list commands or `zz commands --json` for machine-readable
command metadata.

The desktop shell exposes the same commands through the ZZ menu: click the
ZZ button in the bar (a popout under it) or press Super+Z (centered, like
the launcher), walk the groups, and pick a row; it runs in a terminal window that stays open. Typing `zz` in the
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
another selected choice shares are kept, and units installed by other
custom actions (direct installers) are reported as left in place. Both
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
