# ZZ Command-Line Utility

`zz` provides post-install maintenance and troubleshooting commands.

## Commands

| Command | Purpose |
| --- | --- |
| `zz doctor` | Check desktop and installation readiness. |
| `zz logs` | Print the path to the latest installer log. |
| `zz debug` | Create a sanitized local debug bundle. |
| `zz first-run` | Rerun idempotent first-login setup. |
| `zz defaults` | Reapply default applications and browser preferences. |
| `zz dotnet` | Manage .NET development utilities. |
| `zz refresh` | Replace one user-owned config with the current ZZ default, backing it up first. |
| `zz update` | Update ZZ itself, packages, or developer tools. |

Run `zz --help` to list commands or `zz commands --json` for machine-readable
command metadata.

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
product-owned tree. It then loads the saved selections, builds a fresh plan
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

## Refreshing user configuration

```bash
zz refresh --list
zz refresh ghostty/config
```

`zz refresh` only exposes user-owned seeded files. If the existing file
differs, it writes an adjacent `.bak.<timestamp>` backup before installing
the default from `~/.zz`. Product-owned linked files update directly with
Git and are not refresh targets.
