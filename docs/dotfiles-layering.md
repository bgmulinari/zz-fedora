# Configuration ownership and layering

ZZ keeps the product checkout at `~/.zz`. Git owns that tree, and
`zz update zz` fast-forwards that checkout, rebuilds the current plan from
saved selections, and applies its required and configuration work in update
mode. Optional software installation is skipped. User configuration lives
outside the checkout and is never silently replaced; ZZ-managed links into
`~/.zz` see updated defaults immediately, and newly declared links are created
when the refreshed plan is applied.

GNU Stow is not part of this model. The catalog selects named configuration
components, and `modules/60-user-config.sh` applies the paths declared in
`config/managed-config.tsv`.

## Ownership modes

Each manifest row has seven tab-separated fields:

`component`, `path`, `mode`, `conflict`, `source`, `required-command`, and
`description`.

| Mode | Owner | Update behavior |
| --- | --- | --- |
| `product-link` | ZZ | The target is a symlink into `~/.zz`. Git updates take effect immediately. A conflicting target is backed up before the link is created. |
| `system-file` | ZZ | The installer copies the repository source to `/etc` or `/usr/lib` and replaces changed content through the normal installer backup path. |
| `seed-if-missing` | User | The installer copies the default only when the target does not exist. Later ZZ updates preserve it. |
| `directory` | User | The installer ensures an override directory exists without managing its contents. |
| `first-run` | Installer/session | A later first-login step creates or updates the path. |
| `generated` | Installer | Installer logic renders or installs the path. |

Repository defaults and product assets live under `dotfiles/`. Despite the
historical directory name, these files are not Stow packages. Seed sources
that exist only to initialize a user-owned file live under `templates/`.

Catalog units select components with their top-level `config` array. The
planner expands those components into
`files/config-deployments.tsv`, reports their ownership policy, and applies
them during the User Configuration step.

## Native application layers

The entrypoint for each configurable application is user-owned. It loads the
live ZZ defaults first and a user override last:

| Surface | User-owned entrypoint or override | ZZ-managed default |
| --- | --- | --- |
| Niri | `~/.config/niri/config.kdl`, plus optional `~/.config/niri/local.kdl` | `dotfiles/niri/.config/niri/defaults.kdl` and its `cfg/` includes |
| Niri keybinds | `~/.config/niri/dms/binds.kdl` (seeded once, then owned by DMS Settings → Keybinds) | `templates/niri/dms-binds.kdl` |
| DMS | `~/.config/DankMaterialShell/settings.json` (seeded once, then owned by the Settings UI) | `dotfiles/dms/.config/DankMaterialShell/themes/catppuccin/theme.json`, linked as the selected registry theme; session state stays under `~/.local/state/DankMaterialShell/` |
| Ghostty | `~/.config/ghostty/config` and optional `~/.config/ghostty/local` | `dotfiles/ghostty/.config/ghostty/config`, linked as `~/.config/ghostty/zz-defaults` |
| Fastfetch | `~/.config/fastfetch/config.jsonc` | `dotfiles/fastfetch/.config/fastfetch/zz-fedora.txt`, linked into the Fastfetch config directory |
| Bash | `~/.bashrc` and `~/.shellrc.d/` | `dotfiles/shell/.bashrc`; selected product integrations are linked under `~/.config/zz-fedora/shell.d/` |
| Zsh | `~/.zshrc`, `~/.shellrc.d/`, and `~/.zshrc.d/` | `dotfiles/zsh/.zshrc` and the same selected product integration links |

This split lets Git update the product defaults without merging or overwriting
personal changes. Optional shell integrations remain tied to their catalog
selections: the installer links only selected fragments into the product
integration directory, and each fragment also checks for its corresponding
command before enabling anything.

Hardware-specific and generated values stay in user or state files. For
example, Niri display settings live in the DMS-managed
`~/.config/niri/dms/outputs.kdl`, and DMS-generated monitor and widget
state stays out of the repository.

Niri keybinds are seeded rather than linked because DMS both reads and
writes `~/.config/niri/dms/binds.kdl`: it is the only niri file
Settings → Keybinds parses, so binds kept in the product `cfg/` tree
would not appear in the UI at all. The trade is that updated keybind
defaults reach an existing install only through
`zz refresh niri/dms/binds.kdl`.

## Resetting a user-owned file

Seeded files do not change automatically. To intentionally replace one with
the latest shipped default:

```bash
zz refresh --list
zz refresh niri/config.kdl
```

If the current file differs, `zz refresh` first creates an adjacent
`<filename>.bak.<timestamp>` copy, installs the current default, and prints
the diff. ZZ-managed links are intentionally excluded from this command
because updating `~/.zz` already refreshes them.

## Adding configuration

1. Put live product defaults or assets under the appropriate directory in
   `dotfiles/`; put a user seed under `templates/`.
2. Add a row to `config/managed-config.tsv` with explicit ownership and
   conflict behavior.
3. Add the component to the owning catalog unit's `config` array.
4. For an application with native includes, keep the user entrypoint thin:
   load the product default, then the user override.
5. Add focused planner and apply tests for preservation, backup, and link
   behavior.

## Promoting a DMS Settings change into the baseline

The portable seed values live in `templates/dms/settings-seed.json` and
`templates/dms/session-seed.json`. `lib/dms.sh` overlays the keys that render
to absolute paths (`customThemeFile`, `iconThemeDark`, `iconThemeLight`, and
`wallpaperPath`) from `dms_theme_file`, `dms_icon_theme`, and
`dms_default_wallpaper`, which remain the single source for those facts.

Change something in the DMS Settings UI, then:

```bash
scripts/dms-seed-diff.sh                 # list what moved
scripts/dms-seed-diff.sh --apply         # live -> seed, keep it as a default
scripts/dms-seed-diff.sh --reset         # seed -> live, throw the change away
scripts/dms-seed-diff.sh --apply cornerRadius showDock
```

`--apply` and `--reset` are the two directions of the same report and cannot
be combined. `--reset` writes the live DMS files, so it backs each one up as
`<file>.bak.<epoch>` and then restarts `dms.service`. That restart is required
rather than cosmetic: DMS holds its settings in memory and rewrites the file
on any later change, so an unrestarted shell would quietly undo the reset. The
`dms ipc call settings set` path is not usable here — it rejects objects and
arrays outright, and it assigns without running the `onChange` hooks, so
compositor fragments such as `dms/layout.kdl` would not be regenerated. Pass
`--no-restart` when DMS is not the running session and `--yes` to skip the
confirmation prompt.

A key the report lists as `not in the seed, changed from the DMS default`
resets to the DMS default, not to a ZZ value. Keys the report does not mention
are never touched in either direction.

Changing the icon theme or the wallpaper is reported too, but as a key
`lib/dms.sh` renders rather than one a seed file holds: the report names the
helper to edit (`dms_icon_theme`, `dms_default_wallpaper`, `dms_theme_file`)
and `--apply` never writes an absolute host path into a seed.

Keybinds are compared too, against `templates/niri/dms-binds.kdl`. Both sides
are parsed by `dms keybinds show` rather than diffed as text, because DMS
rewrites the fragment on the first UI edit — re-sorting binds and dropping the
seed's comments — so a textual diff would report churn forever. Keybinds move
as a whole file rather than per bind, since re-emitting individual binds would
mean reimplementing DMS's KDL writer; promoting them preserves the seed's
comment header. `--reset` needs no shell restart for them, as niri watches its
own config.

DMS writes every key it knows into `settings.json`, so a plain diff reports
hundreds of untouched defaults. The script reads the installed shell's own
specs (`Common/settings/*Spec.js`) to tell a deliberate change from a default
DMS never moved, and compares structured settings field by field so promoting
one bar property does not freeze the whole backfilled bar schema into the
seed. Machine-specific and runtime keys — monitor layouts, GPU and device
identity, weather coordinates, launcher history, sidebar state — are excluded
and can never be promoted; see `EXCLUDED` in `lib/dms_seed_diff.py`.

It exits non-zero while differences remain, so it can gate a check.
