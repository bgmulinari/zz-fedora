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
| `zz update` | Update packages and developer tools. |

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
zz update all
zz update all --dry-run
zz update all --cleanup
```

Individual update targets are `dnf`, `flatpak`, `brew`, `npm`, `dotnet`,
`dotnet-sdk`, `dotnet-tools`, `claude`, and `cleanup`. Run `zz update --help`
for details.
