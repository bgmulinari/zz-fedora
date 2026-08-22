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

The niri entrypoint includes every DMS-writable fragment the Settings UI
manages at runtime — `dms/colors.kdl` (matugen), plus optional
`dms/layout.kdl`, `dms/input.kdl`, `dms/cursor.kdl`, `dms/outputs.kdl`,
and `dms/windowrules.kdl` — because each Settings page gates itself on
`dms config resolve-include` and goes read-only when its fragment is not
included. `dms/binds.kdl` and `dms/alttab.kdl` are intentionally not
included: the repository owns keybinds, and the alttab fragment only adds
a cosmetic recent-windows radius already covered by the colors seed.
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
- Editors select the matugen-generated themes by name: VS Code
  `Dynamic Base16 DankShell` (extension `danklinux.dms-theme`), Zed
  `DankShell Dark` / `DankShell Light`.
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
a first-run checkpoint once the user's shell state exists.

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
