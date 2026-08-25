# DMS (DankMaterialShell) integration

This document records the design decisions behind the DMS desktop shell
integration: package ownership, theme seeding, greeter wiring, and the
first-run contract. It replaced the former Noctalia integration wholesale;
there are no compatibility or migration paths.

## Package and repository ownership

| Component | Package | Repository |
| --- | --- | --- |
| Shell + CLI | `dms` (pulls `dms-cli`, `dgop`) | COPR `avengemedia/dms` (stable channel) |
| Quickshell runtime | `quickshell` | COPR `avengemedia/danklinux` |
| Theming engine | `matugen` | COPR `avengemedia/danklinux` |
| Launcher file search | `danksearch` | COPR `avengemedia/danklinux` |
| Audio visualizer | `cava` | Fedora / COPR `avengemedia/danklinux` |
| Greeter | `dms-greeter` | COPR `avengemedia/danklinux` |
| Qt6 theming | `qt6ct-kde` | COPR `avengemedia/danklinux` |
| Terminal | `ghostty` | Terra |

Repo-priority rules keep ownership deterministic. Each rule is declared as
an `excludepkgs` list on the source's own catalog TOML, compiled into
`sources.tsv`, and applied generically by `fedora_enable_sources`
(`lib/fedora.sh`) to the dnf repository the source enables — so a COPR
migration updates the ownership rule together with the source definition:

- `catalog/sources/terra/terra.toml` excludes
  `quickshell,quickshell-git,noctalia-qs,matugen,dgop,danksearch,dms,dms-cli,dms-greeter`
  so the DMS stack always resolves from the DankLinux COPRs (Terra also
  packages quickshell, and its `noctalia-qs` declares
  `Provides: quickshell`, which the solver would otherwise accept for the
  dms RPM's `(quickshell or quickshell-git)` dependency). `base-dms` also
  names `quickshell` explicitly so the real package is installed rather
  than trusting provider resolution of that boolean dependency.
- `catalog/sources/copr/avengemedia-danklinux.toml` excludes
  `ghostty,ghostty-shell-integration,ghostty-nautilus` so Terra always
  owns Ghostty (the COPR also builds it).

DMS bundles its UI fonts (Inter Variable, FiraCode Nerd Font, Material
Symbols Rounded) through Qt FontLoader, so no font packages are required
for the shell itself. DMS's clipboard manager, screenshot flow, lock
screen, idle daemon, notification daemon, OSD, and polkit agent are all
native, replacing the usual cliphist/wl-clipboard/swaylock/swayidle/mako
stack. The `dms.service` user unit takes the `org.freedesktop.Notifications`
bus name; never install another notification daemon alongside it.

## Launch path

DMS starts through its packaged systemd user unit (`dms.service`), but it
is never `systemctl enable`d: its `[Install]` section hooks
`graphical-session.target`, which every desktop activates, so enabling it
on a machine that also has GNOME or KDE would launch DMS inside those
sessions where it fights the native shell for the
`org.freedesktop.Notifications` bus. The wiring is data: `base-dms`
declares `user_wants = ["niri.service/dms.service"]` (and
`user_services = ["dsearch.service"]`) in its catalog unit, the planner
compiles the declarations of every planned unit into
`services/user-enable.list` and `services/user-wants.tsv`, and the
user-service machinery applies upstream's recommended scoping:
`systemctl --user add-wants niri.service dms.service` at first-run
(starting the unit immediately when the Niri session is already live),
with a `--global add-wants` fallback for the root/installer-chroot path.
There is deliberately no `spawn-at-startup` fallback: two launch
mechanisms mean double shells. `dsearch.service` (the danksearch indexer
feeding the spotlight launcher's file search; `WantedBy=default.target`,
harmless in any session) stays a plain enable, matching upstream
dankinstall. Readiness grades the binding by the wants symlink the two
`add-wants` scopes create (`~/.config/systemd/user/niri.service.wants/`
or `/etc/systemd/user/niri.service.wants/`) at warn severity — a
system-scope `is-enabled` cannot see a user binding, and before the first
login the binding legitimately does not exist yet.

The niri entrypoint includes every fragment DMS regenerates under
`~/.config/niri/dms/` — `dms/colors.kdl` (matugen), plus optional
`dms/layout.kdl`, `dms/alttab.kdl`, `dms/binds.kdl`, `dms/cursor.kdl`,
`dms/outputs.kdl`, `dms/windowrules.kdl`, and `dms/wpblur.kdl` — because
each Settings page gates itself on `dms config resolve-include` and goes
read-only when its fragment is not included. Fragment paths are written
without a `./` prefix: `KeybindsService` detects its own include with the
literal pattern `include.*"dms/binds.kdl"`, and the `./` form fails that
match, which makes DMS offer to "repair" the user-owned entrypoint by
backing it up and appending its own include line.

`dms/input.kdl` is deliberately absent: DMS has no writer for it and
never creates it, so the include only resolved to nothing. Niri input
belongs to `cfg/input.kdl`.

`dms/binds.kdl` is the *only* niri file the Settings → Keybinds page
reads. `dms keybinds show niri` parses that fragment alone, so binds kept
anywhere else — including a product-owned `cfg/keybinds.kdl` — are
invisible to the UI and the page renders empty. Including the fragment is
therefore necessary but not sufficient: the shipped keybinds have to live
*in* it.

So ZZ's keybind defaults are seeded into `~/.config/niri/dms/binds.kdl`
from `templates/niri/dms-binds.kdl`, and the niri defaults tree carries no
keybinds at all. DMS parses the seeded KDL directly, preserving
`hotkey-overlay-title`, `allow-when-locked`, `allow-inhibiting`, and
`cooldown-ms`, and sorts the binds into its own categories for display.

DMS's default-vs-override layering does not reach niri, so ZZ's seed
cannot act as a revertible default layer. The niri provider tags a bind
`dms-default` when it comes from `dms/binds.kdl` and `config` otherwise,
and never emits `dms` (`core/internal/keybinds/providers/niri.go`); the
Settings UI computes `isOverride` as `source === "dms"`
(`Services/KeybindsService.qml`). The Overrides filter is therefore always
empty on niri no matter what the seed contains or what the user changes.
Hyprland gets the two-layer model — `dms/binds.lua` for DMS defaults and
`dms/binds-user.lua` for overrides — and only its provider produces the
`dms` source. Consequently the per-bind "Reset to Default" action deletes
the bind on niri rather than restoring anything, despite prompt wording
that says the DMS default will re-apply. The supported revert is
whole-file: `zz refresh niri/dms/binds.kdl`. Revisit this if a DMS release
adds a niri user-override fragment.

This makes keybinds user-owned rather than product-owned, with two
consequences. Changed defaults no longer reach an existing install
automatically; `zz refresh niri/dms/binds.kdl` re-seeds them, backing up
the current file first. And the first edit made in the Settings UI
rewrites the whole fragment, discarding the seed's comments and section
grouping while keeping every bind — so the seed's layout is a
seed-time convenience, not a format DMS maintains.

Settings the repository could set in KDL but DMS also owns are left to
DMS, so the Settings UI stays the single place they change. `cfg/layout.kdl`
therefore sets no gaps, no border or focus-ring width, and no colors:
`niriLayoutGapsOverride` and `niriLayoutBorderSize` in the DMS settings
seed drive them through `dms/layout.kdl`, and every color comes from
`dms/colors.kdl`. Note that DMS writes one width to both `border` and
`focus-ring`, so the two cannot differ while DMS owns them.
Display configuration is DMS-owned through `dms/outputs.kdl` (Settings →
Displays); there is no separate manual display seed. When something must
beat the DMS-managed configuration, the user-owned `config.kdl`
entrypoint can declare an output block above the includes — niri uses the
first matching output section.

## Theme seeding

The default look is the official Catppuccin registry theme, mocha flavor
with the blue accent (latte + blue in light mode).

- `dotfiles/dms/.config/DankMaterialShell/themes/catppuccin/theme.json` is
  vendored from the official plugin/theme registry
  (https://github.com/AvengeMedia/dms-plugin-registry, `themes/catppuccin/theme.json`,
  commit `b65b029182b781c7d61ecfe1561eaae3fd059554`, 2026-08-21). To update
  it, fetch the same path from the registry HEAD, re-run
  `tests/dms_theme.bats`, and record the new commit here. Installing a
  registry theme is just placing its `theme.json` under
  `~/.config/DankMaterialShell/themes/<id>/`; the file is product-linked.
- `~/.config/DankMaterialShell/settings.json` is seeded once
  (seed-if-missing) with the theme selection keys
  (`currentThemeCategory: "registry"`, `currentThemeName: "custom"`,
  `customThemeFile`, `registryThemeVariants.catppuccin`), the managed mono
  font, and the Yaru-blue icon theme. Every other key falls back to the DMS
  defaults, and the Settings UI owns the file afterwards. The seed emitters
  and path/theme-fact helpers live in `lib/dms.sh`; the seeds, greeter
  staging, planner, first-run waits, and doctor checks all derive the DMS
  paths from it.
- `~/.local/state/DankMaterialShell/session.json` is seeded with the
  managed default wallpaper and dark mode.
- `dms_seed_state_files_if_missing` (`lib/dms.sh`) is the single writer
  for both seeds plus the `dms-colors.json` placeholder. The greeter
  action (module 30) runs before the post-actions seeding (module 80) and
  needs the files to exist for its cache symlinks, so it calls the same
  seeder — never a bare placeholder, which would block the real seeds
  behind the seed-if-missing guard.
- Static fallbacks bridge the gap until the shell first renders its matugen
  templates: `templates/ghostty/dankcolors` and
  `templates/niri/dms-colors.kdl` carry the same Catppuccin mocha/blue
  values as the generated `~/.config/ghostty/themes/dankcolors` and
  `~/.config/niri/dms/colors.kdl` that later overwrite them.
- qt6ct and kdeglobals point at the matugen-generated
  `~/.local/share/color-schemes/DankMatugen.colors` KColorScheme — the
  same wiring the Settings "Apply Qt Colors" button would write, so Qt
  apps follow the theme with no manual step.
- GTK/libadwaita apps follow the theme through the upstream one-time
  opt-in: the `dms-gtk-theme` first-run checkpoint runs the shell's own
  `scripts/gtk.sh apply` (what the Settings "Apply GTK Colors" button
  invokes), which imports the generated `dank-colors.css` from the user
  `gtk.css` files. After that, DMS's automatic `patch`/regeneration passes
  keep GTK apps synchronized on every theme change.
- The icon theme follows the accent automatically (ported from the
  previous shell's icon sync): a ZZ matugen drop-in
  (`~/.config/matugen/dms/configs/zz-icon-theme.toml` — DMS appends every
  `*.toml` in that directory, under its `configDir` of `~/.config`, to
  its merged matugen config) renders the primary color to
  `~/.cache/DankMaterialShell/icon-theme-accent`, and its post-hook runs
  `zz-sync-icon-theme`, which picks the hue-nearest Yaru variant and
  applies it to gsettings, qt6ct, kdeglobals, and the shell's own icon
  settings through the settings IPC. DMS itself covers the companion
  GNOME accent-color sync once its GTK theming is active.
- Editors select the matugen-generated themes by name: VS Code
  `Dynamic Base16 DankShell` (extension `danklinux.dms-theme`), Zed
  `DankShell Dark` / `DankShell Light`.
- Starship follows the theme through the same drop-in mechanism
  (`zz-starship.toml`): starship cannot include external files, so the
  palette renders to `~/.cache/DankMaterialShell/starship-palette.toml`
  and the post-hook `zz-sync-starship-palette` splices it into the
  marker-delimited `[palettes.zz]` block of the user-owned
  `starship.toml` (everything outside the markers is preserved; removing
  the markers opts out). The static palette in `templates/starship.toml`
  is the pre-first-render fallback.
- btop has no upstream DMS template and its `TTY` builtin leans on the
  terminal ANSI palette, whose generated slots are not a classic ramp; a
  ZZ matugen drop-in (`zz-btop.toml`) renders the managed
  `templates/btop/dank.theme`-shaped theme to
  `~/.config/btop/themes/dank.theme` (seeded statically as a fallback)
  and the btop config selects it as `dank`.
- Firefox theming (optional `browsers-firefox-theme` unit) uses Pywalfox:
  the native host is pip-installed per user (Fedora does not package it;
  the unit installs `python3-pip`, which Fedora's `python3` does not
  bundle), and `~/.cache/wal/colors.json` symlinks to the DMS template
  output `~/.cache/wal/dank-pywalfox.json`, the upstream-documented
  bridge. A pre-existing regular `colors.json` (a standalone-pywal
  palette) is backed up before the link replaces it.

## Greeter

`dms-greeter` (greetd) replaces the previous shell-specific greeter. The
RPM scriptlets own the system heavy lifting (greeter user, SELinux
contexts, `/etc/pam.d/greetd`, greetd config creation/repair,
graphical.target). The `dms-greeter` action (`lib/actions/dms-greeter.sh`)
adds only what the package cannot know:

- installs the package pinned to the DankLinux COPR and re-asserts the
  greetd session config when a foreign config survived the scriptlet;
- replicates the root-side plumbing of upstream `dms-greeter enable`/`sync`
  for the target user (the upstream commands act on the *invoking* user, so
  they cannot be called from the root install path): `greeter` group
  membership, `g:greeter:rX` ACLs on the home traversal path and the DMS
  state dirs, the 2770 greeter-owned `/var/cache/dms-greeter{,/users}`
  cache, and the `settings.json`/`session.json`/`colors.json` symlinks into
  the user's live DMS state;
- enables greetd as the fallback graphical login, skipping (with a recorded
  skip) when another display manager is already enabled.

The sudo-free per-user preview slot (`dms-greeter sync --profile`) runs as
a first-run checkpoint once the user's shell state exists — gated on a
capability probe, because the stable-channel `dms-greeter` is only the
greeter launcher and gained the sync subcommands later; on releases
without it the checkpoint completes and the greeter follows the theme
through the cache symlinks alone.

## First-run contract

`modules/85-first-run.sh` keeps the independent-checkpoint model:

- `dms-theme` waits for the shell socket (`dms ipc call wallpaper get`) and
  then for the generated theme artifacts this install consumes (Ghostty
  `dankcolors`, `DankMatugen.colors`). There is no explicit "apply" IPC —
  DMS regenerates templates at startup and on theme changes — so artifact
  content is the completion signal: the Ghostty artifact is pre-seeded at
  the same path, so it only counts once its content diverges from the
  seed. Timeouts warn and retry at next login, bounded at three failed
  logins — after that the checkpoint completes with a warning instead of
  taxing every login, and the doctor checks surface the missing artifacts.
- `dms-gtk-theme` runs the shell payload's `gtk.sh apply` once the
  generated GTK colors exist, applying the same one-time GTK opt-in as
  the Settings button so GTK theming is automatic from the first login.
- `dms-greeter-profile` runs `dms-greeter sync --profile` unless the
  greeter action (or its user sync) was skip-recorded.

## Verification surface

- `tests/dms_theme.bats` + `tests/support/dms_theme.py` validate the
  vendored theme.json (structure and WCAG contrast on the flavor/accent
  pairs).
- `tests/packages_orchestration.bats` covers the greeter action;
  `tests/post_actions.bats` covers the seeds and first-run checkpoints;
  `tests/fedora_sources.bats` covers the COPR/Terra ownership rules.
- `dms doctor` runs best-effort in `zz doctor` diagnostics.
