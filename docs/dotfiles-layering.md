# Configuration ownership and layering

ZZ keeps the product checkout at `~/.zz`. Git owns that tree, and
`zz update zz` fast-forwards that checkout, rebuilds the current plan from
saved selections, and applies its required and configuration work in update
mode. Optional software installation is skipped. User configuration lives
outside the checkout and is never silently replaced; product-owned links into
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

| Surface | User-owned entrypoint or override | Product-owned default |
| --- | --- | --- |
| Niri | `~/.config/niri/config.kdl`, plus optional `~/.config/niri/local.kdl` | `dotfiles/niri/.config/niri/defaults.kdl` and its `cfg/` includes |
| Noctalia | `~/.config/noctalia/config.toml` and `~/.config/noctalia/conf.d` | `dotfiles/noctalia/.config/noctalia/config.toml`; Settings UI state remains under `~/.local/state/noctalia/` and loads last |
| Ghostty | `~/.config/ghostty/config` and optional `~/.config/ghostty/local` | `dotfiles/ghostty/.config/ghostty/config`, linked as `~/.config/ghostty/zz-defaults` |
| Bash | `~/.bashrc` and `~/.shellrc.d/` | `dotfiles/shell/.bashrc`; selected product integrations are linked under `~/.config/zz-fedora/shell.d/` |
| Zsh | `~/.zshrc`, `~/.shellrc.d/`, and `~/.zshrc.d/` | `dotfiles/zsh/.zshrc` and the same selected product integration links |

This split lets Git update the product defaults without merging or overwriting
personal changes. Optional shell integrations remain tied to their catalog
selections: the installer links only selected fragments into the product
integration directory, and each fragment also checks for its corresponding
command before enabling anything.

Hardware-specific and generated values stay in user or state files. For
example, Niri display settings are seeded from
`templates/niri/display.kdl`, while Noctalia-generated monitor and widget state
stays out of the repository.

## Resetting a user-owned file

Seeded files do not change automatically. To intentionally replace one with
the latest shipped default:

```bash
zz refresh --list
zz refresh niri/config.kdl
```

If the current file differs, `zz refresh` first creates an adjacent
`<filename>.bak.<timestamp>` copy, installs the current default, and prints
the diff. Product-owned links are intentionally excluded from this command
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

Use the `promote-noctalia-config` skill for Noctalia Settings UI changes so
portable defaults are promoted without committing hardware-specific state.
