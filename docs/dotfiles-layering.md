# Dotfiles and templates layering

This page explains how user configuration reaches the target home directory
and how to decide where a new file belongs: a Stow package under `dotfiles/`,
or an installer-rendered file under `templates/`.

## Two delivery paths

| Layer | Deployed by | Semantics |
| --- | --- | --- |
| `dotfiles/<stow-package>/` | GNU Stow, via `modules/60-dotfiles.sh` | Files are symlinked into `$HOME`, so the repository checkout stays the live source of truth. Pre-existing real files at a target path are backed up first (`backup-before-stow`). |
| `templates/` | Installer seed and render helpers, for example `lib/theme-seeds.sh` | Files are copied or rendered into place, typically only when the destination is missing (`seed-if-missing`), and then left alone (`preserve`). The user owns the file afterwards. |

Decision rule when adding configuration for a new app:

- Portable config that should track the repository on every install and
  update goes in a Stow package: `dotfiles/<stow-package>/` mirroring the
  home-relative layout (for example
  `dotfiles/btop/.config/btop/btop.conf`). Reference the package from the
  owning bundle's `BUNDLE_STOW_PACKAGES` field.
- Hardware-specific, user-owned, or fallback content that the installer
  writes once and must never clobber afterwards goes in `templates/`, with a
  matching row in `config/managed-config.tsv` declaring its mode and
  conflict policy.

Guessing wrong has real consequences: a file placed under `templates/`
without seeding logic never deploys, and moving a seeded file into a Stow
package silently replaces user-owned content on the next install.

## `config/managed-config.tsv` is the authoritative map

`config/managed-config.tsv` declares, per managed path, the deployment
`mode` (`stow`, `seed-if-missing`, `first-run`, `generated`), the `conflict`
policy (`backup-before-stow`, `preserve`, `regenerate`), the `owner`, and a
description. When a path appears both in a Stow package and in
`templates/`, this file is what disambiguates which mechanism wins for that
path. Stow-managed files without an explicit row get a generated
`stow`/`backup-before-stow` policy entry in the plan (see
`lib/files.sh`).

## The `shell-*` Stow package prefix

The prefix encodes how a package integrates with the shared shell startup
tree:

- **Prefixed (`shell-*`): contributes drop-in fragments.** The package ships
  only `.shellrc.d/*` fragments that hook a tool into the interactive shell.
  The `.shellrc.d` tree itself belongs to `dotfiles/shell/`, whose
  `.bashrc` (and `dotfiles/zsh/.zshrc`) source every fragment. Examples:
  `dotfiles/shell-fastfetch`, `dotfiles/shell-fzf`,
  `dotfiles/shell-starship`, `dotfiles/shell-yazi`,
  `dotfiles/shell-zoxide`.
- **Unprefixed: owns its own config tree.** The package deploys the app's
  own configuration files, not shell hooks. Examples: `dotfiles/btop`
  (`.config/btop/`), `dotfiles/zsh` (`.zshrc`), `dotfiles/ghostty`
  (`.config/ghostty/`).

A tool that needs both an app config tree and a shell hook uses two
packages: an unprefixed one for the config tree and a `shell-*` one for the
fragment.

Note that `shell-*` **bundle IDs** do not map 1:1 to `shell-*` **Stow
packages**. Bundle IDs are `<category>-<basename>`, so every bundle under
`bundles/shell/` gets a `shell-` prefix regardless of what it stows. For
example, the `shell-btop` bundle (`bundles/shell/btop.bundle`) stows the
`btop` package, because btop's config is an owned tree, not a `.shellrc.d`
fragment. The `shell-fzf` bundle stows the `shell-fzf` package only because
fzf really does ship a fragment.

## Apps with both a template and a Stow package

Some apps intentionally have configuration in both layers. The Stow package
carries the portable live config; the template carries a rendered or
hardware-specific seed for a *different path* that the installer writes only
when missing and then preserves.

| App | Stow-managed live config (edit here) | Installer-seeded template (`seed-if-missing`, `preserve`) |
| --- | --- | --- |
| Ghostty | `dotfiles/ghostty/.config/ghostty/config` | `templates/ghostty/noctalia` → `~/.config/ghostty/themes/noctalia` (fallback theme until Noctalia regenerates it) |
| Niri | `dotfiles/niri/.config/niri/config.kdl` and `dotfiles/niri/.config/niri/cfg/` | `templates/niri/display.kdl` → `~/.config/niri/cfg/display.kdl` (hardware-specific); `templates/niri/noctalia.kdl` → `~/.config/niri/noctalia.kdl` |
| Starship | `dotfiles/shell-starship/.shellrc.d/starship` (shell hook only) | `templates/starship.toml` → `~/.config/starship.toml` (seeded only when the user has no config) |
| Noctalia | `dotfiles/noctalia/.config/noctalia/config.toml` (stowed) | No `templates/` entry; Noctalia's managed paths use `stow` mode. `dotfiles/noctalia/.config/noctalia/templates/` is a Noctalia app asset, not an installer template. |

To change an app's day-to-day configuration, edit the Stow package. Edit the
`templates/` file only when changing what a fresh machine gets seeded with;
existing installs keep their user-owned copy because of the `preserve`
policy in `config/managed-config.tsv`.
