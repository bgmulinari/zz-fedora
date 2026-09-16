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

DMS 1.6 embeds the Quickshell UI in the `dms` binary; the old
`/usr/share/quickshell/dms` payload is not a packaging contract. At runtime
the CLI materializes the UI under `$XDG_RUNTIME_DIR/danklinux-shell/`.
`dms_shell_dir` resolves the active revision from the structured
`dms doctor --json` result, which supplies both the `scripts/` appliers used
at first login and the `Common/settings` specs used by the seed-diff tool.

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
native, replacing the usual cliphist/swaylock/swayidle/mako stack. The
`dms.service` user unit takes the `org.freedesktop.Notifications` bus name;
never install another notification daemon alongside it. `wl-clipboard`
stays in the base only as the `wl-copy` bridge the screenshot annotation
editor publishes through; the COPR `dms` package does not depend on it.

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
`dms/input.kdl`, `dms/outputs.kdl`, `dms/windowrules.kdl`, and
`dms/wpblur.kdl` — because
each Settings page gates itself on `dms config resolve-include` and goes
read-only when its fragment is not included. Fragment paths are written
without a `./` prefix: `KeybindsService` detects its own include with the
literal pattern `include.*"dms/binds.kdl"`, and the `./` form fails that
match, which makes DMS offer to "repair" the user-owned entrypoint by
backing it up and appending its own include line.

DMS 1.6 generates `dms/input.kdl` from its mouse, touchpad, and keyboard
settings. Those device directives live only in the generated fragment: DMS
represents disabled boolean options by omitting their KDL nodes, so an earlier
product-owned `tap`, `natural-scroll`, or `numlock` would prevent the Settings
toggle from turning it off. `cfg/input.kdl` retains only the behavior DMS does
not model (`focus-follows-mouse` and `workspace-auto-back-and-forth`). The
portable seed pins `keyboardNumlock = true` so moving ownership does not change
ZZ's default.

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

The screenshot defaults use the DMS 1.6 native CLI (`dms screenshot`) rather
than the legacy niri IPC shim. Print captures the focused output, Ctrl+Print
and Mod+Shift+S select a region, and Alt+Print captures the focused window.
This keeps the shipped binds on the path that supports 10-bit buffers,
cross-output selection, last-region geometry, cursor capture, and scroll
capture.

DMS has no annotation step of its own, so every screenshot bind pipes the capture
(`dms screenshot ... --stdout`) into satty, the annotation editor the
`base-screenshot-tools` unit installs. With `--stdout` DMS writes neither a
file nor the clipboard nor a notification; satty owns all three through the
seeded `~/.config/satty/config.toml`: Enter copies, saves to the same
`~/Pictures/Screenshots` path niri uses, and closes; Escape discards. A
cancelled region selection produces no image, and satty exits on the empty
input without opening a window. On niri the window capture is
also copied by the compositor itself, which DMS cannot disable; satty's copy
replaces it once the annotation is confirmed. A seeded window rule floats
the satty window so a small region capture does not open as a tiled column.

Window rules are seeded into `dms/windowrules.kdl` the way keybinds are
seeded into `dms/binds.kdl`, and for the same reason: Settings → Window
Rules only lists rules it reaches by following `include` lines literally
from `config.kdl`, and the `~/.zz/...` include of the product defaults is
never tilde-expanded, so a `window-rule` in `cfg/rules.kdl` was applied by
niri but invisible to the UI. `cfg/rules.kdl` now carries layer rules only.
The generic corner-radius rule that used to live there was dead config as
well: DMS always emits its own `geometry-corner-radius` rule into
`dms/layout.kdl`, which loads later and wins.

Colors are DMS's alone: `dms/colors.kdl` loads after `cfg/layout.kdl`, so
any color set there is dead config.

Gaps are the opposite: DMS models its value as an *override* on top of the
niri config, so the product baseline belongs in `cfg/layout.kdl` rather than
being expressed as an override. Border widths look like the same case but are
not, and the difference decides where each value has to live:

- **Gaps.** Only `niriLayoutGapsOverride = -2`, the UI's "Off" mode, makes
  DMS omit its `gaps` line. `-1` ("Auto") is not a deferral — it writes
  `max(4, bar spacing)`, which is `4` under this bar. So the seed pins `-2`.
- **Border and focus-ring.** There is no equivalent off mode. DMS writes both
  widths unconditionally from `niriLayoutBorderSize`, falling back to `2` even
  when the UI's "Override Border Size" toggle is off, so a width in
  `cfg/layout.kdl` is always dead config. ZZ accepts the upstream `-1` default
  and therefore does not pin a redundant seed value. A different product
  width would have to be selected through the Settings UI or pinned in the
  seed.

DMS writes one width to both `border` and `focus-ring`, so the two cannot
differ once it is running.

Display configuration is DMS-owned through `dms/outputs.kdl` (Settings →
Displays); there is no separate manual display seed. When something must
beat the DMS-managed configuration, the user-owned `config.kdl`
entrypoint can declare an output block above the includes — niri uses the
first matching output section.

## Theme seeding

The default look is the official Catppuccin registry theme, mocha flavor
with the blue accent (latte + blue in light mode).

- Catppuccin is downloaded at first login through DMS's `themes.install`
  backend request, the same operation used by Settings → Browse Themes.
  ZZ does not bundle or product-link theme files. DMS owns the downloaded
  `~/.config/DankMaterialShell/themes/catppuccin/` directory, including previews.
  Registry updates and removal remain available in DMS Settings.
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
  managed default wallpaper; dark mode and an empty pinned-app list inherit
  their upstream defaults and are not redundantly serialized.
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
  apps follow the theme with no manual step. Their icon theme is Breeze
  Dark rather than Yaru: KDE's icon loader falls back to Breeze for the
  KDE icon names Yaru lacks (`go-previous`, `view-list-icons`) and only
  recolors those SVGs under a theme that declares `FollowsColorScheme`,
  and Yaru's own symbolic icons carry a fixed grey fill that only GTK
  recolors, so Yaru leaves Qt toolbars with dark glyphs on dark windows.
- GTK/libadwaita apps follow the theme through the upstream one-time
  opt-in: the `dms-gtk-theme` first-run checkpoint runs the shell's own
  `scripts/gtk.sh apply` (what the Settings "Apply GTK Colors" button
  invokes) from the runtime-extracted shell payload. For GTK4 that imports
  the generated `dank-colors.css` from the user `gtk.css`; for GTK3 it
  copies adw-gtk3 into `~/.local/share/themes` and drops the global import,
  because the colors are appended to that copy by `gtk.sh patch`. The shell
  only runs `patch` after a matugen worker pass, and the worker does not run
  again at login while the theme is unchanged, so the checkpoint runs
  `patch` itself right after `apply` (plus the gtk-theme gsettings flip the
  shell uses to make running GTK3 apps reload). After that, DMS's automatic
  `patch`/regeneration passes keep GTK apps synchronized on every theme
  change.
- Flatpaks reach the same files through a global `flatpak override`
  applied at install time: `xdg-config/gtk-3.0` and `gtk-4.0` for the
  generated colors and the GTK4 import, `xdg-data/themes` so GTK3 apps find
  the patched adw-gtk3 copy ahead of the pristine `org.gtk.Gtk3theme`
  runtime extension, `xdg-config/qt6ct`, `xdg-config/kdeglobals`, and
  `xdg-data/color-schemes` for Qt. The host `QT_QPA_PLATFORMTHEME=qt6ct` is
  forwarded into sandboxes where no qt6ct plugin exists, so the override
  also sets `QT_QPA_PLATFORMTHEME=kde`: the KDE runtime's platform theme
  reads kdeglobals and the DankMatugen color scheme, giving Qt Flatpaks the
  palette host Qt apps use.
- The icon theme follows the accent automatically (ported from the
  previous shell's icon sync): a ZZ matugen drop-in
  (`~/.config/matugen/dms/configs/zz-icon-theme.toml` — DMS appends every
  `*.toml` in that directory, under its `configDir` of `~/.config`, to
  its merged matugen config) renders the primary color to
  `~/.cache/DankMaterialShell/icon-theme-accent`, and its post-hook runs
  `zz-sync-icon-theme`, which picks the hue-nearest Yaru variant and
  applies it to gsettings and the shell's own icon settings through the
  settings IPC; qt6ct and kdeglobals keep Breeze and are not touched. DMS itself covers the companion
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
  the markers opts out). The prompt uses a fixed Powerline layout with native
  Starship modules and direct DMS color mappings, without custom separator
  commands. Every theme uses DMS's generated colors directly. The helper
  derives `on_surface0`, `on_peach`, `on_green`, `on_teal`, `on_blue`, and
  `on_mauve` for segment text. All sections share exactly two theme shades,
  `text` (DMS `on_background`) and `base` (DMS `background`), choosing
  whichever has the higher contrast against each background. There are no per-section overrides or white/black fallbacks;
  achievable contrast depends on the theme's pair of shades.
  The language, Docker, and clock backgrounds use terminal slots 14, 4, and
  11 respectively. Backgrounds and separators keep the generated colors. Existing user-owned
  layouts adopt these foreground tokens through `zz refresh starship.toml`.
  The static palette in `templates/starship.toml` is only a pre-render fallback.
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
  The registered `zz-firefox-theme-host` adapter sends the current palette
  when the extension connects, then hands native messaging to Pywalfox.
  This initializes fresh profiles automatically: upstream Pywalfox's startup
  fetch otherwise runs only after the user has applied a theme once.
- Every other browser choice includes a `browser-theme:<choice>` action.
  Zen's native profile registry is read from `~/.config/zen/profiles.ini`
  or `~/.zen/profiles.ini`; before its first launch the action registers a
  default profile. Each registered profile enables user stylesheets and
  imports `~/.config/DankMaterialShell/zen.css` before personal CSS rules.
  This is the [upstream DMS Zen integration](https://github.com/AvengeMedia/DankLinux-Docs/blob/master/docs/dankmaterialshell/application-themes.mdx),
  not Pywalfox. Fresh installs load the CSS on their first launch. An already
  running Zen needs a restart after setup or later palette changes; live
  palette updates are not supported by this integration.
- Chrome, Chromium, Brave, and Helium use Chromium's native
  `BrowserThemeColor` machine policy. The `browser-theme` configuration component
  installs a matugen drop-in that renders `colors.background.default.hex` to
  `~/.cache/DankMaterialShell/browser-theme.color`. Its post-hook writes the color
  policy and asks running browsers to reload it with
  `--refresh-platform-policy --no-startup-window`, without restarting them.
  Chromium derives its browser colors from this seed; it does not receive an
  exact copy of every DMS palette entry.
- The browser action enrolls the selected policy directory by creating
  `zz-theme.json`: `/etc/chromium/policies/managed` for Fedora Chromium and
  Helium, `/etc/opt/chrome/policies/managed` for Chrome, and
  `/etc/brave/policies/managed` for Brave. The first install uses the current DMS
  background when available, otherwise the shipped default's background until
  DMS first renders. Profile preferences and profile locks are not modified.
- `/usr/lib/zz/browser-theme-policy` is a root-owned script, updated as managed system configuration. A scoped
  sudoers rule allows wheel users to invoke that fixed script with `/usr/bin/bash`
  and pass exactly one six-digit hex color.
  The helper accepts no paths, verifies root ownership and non-writable parents,
  atomically replaces only enrolled `zz-theme.json` files, and leaves other
  policies alone. The unprivileged post-hook runs the browser reload commands
  only for browsers with a running default profile. No browser starts merely
  because the theme changed.
- These policies apply to every profile and make the browser report that its
  theme is managed. Chromium and Helium share their policy directory. As with
  other machine policies, multiple desktop users share the most recently applied
  color. Removing `zz-theme.json` opts that policy directory out of future sync.
- The integration follows the native-policy approach in
  [Omarchy quattro](https://github.com/omacom/omarchy/blob/2fbac0c8e88eca704af1650ce721a494bd11a3d0/bin/omarchy-theme-set-browser).
  Only `BrowserThemeColor` is emitted: Helium 0.17.0.1 accepts it but reports
  Omarchy's `BrowserColorScheme` policy as unknown. DMS's mode-aware background
  supplies the light/dark seed instead.

## Plugins

ZZ ships DMS plugins from the checkout rather than through the plugin
registry: each plugin lives under
`dotfiles/dms/.config/DankMaterialShell/plugins/<Name>/` and is
product-linked as a whole directory into
`~/.config/DankMaterialShell/plugins/<Name>`. DMS lists a symlinked plugin
directory like a real one, and linking the directory (not each file) means
files added later reach existing installs on the next `zz update zz` without
new managed-config rows. The system tier under
`/etc/xdg/quickshell/dms-plugins` is deliberately unused: `system-file` mode
copies single files, so updates would stop flowing, and the user tier would
shadow it anyway.

Enablement is data DMS 1.6 keeps in
`~/.config/DankMaterialShell/plugin_settings.json`, keyed by plugin id. The
base `dms` component carries a `seed-if-missing` row for that file with no
source: it is rendered, like `settings.json`, by the DMS state seeding in
`lib/dms.sh` from `templates/dms/plugin-settings-seed.json`, which enables
every shipped plugin, minus the ids whose plugin component the plan left
out. One rendered seed on the base component is what lets two plugins share
the file (a managed-config path may appear only once) while a deselected
choice still seeds nothing for itself. DMS consults the flag only when it
discovers the plugin directory, which on a fresh install happens at first
login, after both the links and the seeds are in place.

Unlike the other seeds, plugin defaults are not one-shot: a plugin ZZ starts
shipping after an install is on by default there too. After the seeds,
post-actions runs `dms_apply_plugin_defaults` (`lib/dms.sh`), which adds the
planned ids the live `plugin_settings.json` lacks as enabled (every key the
user has set, disabled ones included, is kept), inserts each planned bar
widget into the live `settings.json` bar the way the seed places it (before
the first seed neighbor still in that section, else after the last
preceding one, else at the end, in the bar named `default`), and, when the
target user's shell answers IPC, asks it to rescan and enable the new ids so
they load without a re-login. A widget is placed once per plugin, recorded
in `~/.local/state/zz-fedora/dms-placed-widgets`, so a widget the user
removes afterwards stays removed; DMS watches both files, so a running
shell picks the edits up. The seed-diff tool does not cover plugin
settings, and `zz refresh` does not list the file (rendered seeds have no
source to restore from). A bar widget therefore needs its id in a
`barConfigs` section of `templates/dms/settings-seed.json` for both paths;
the settings emitter strips the ids of shipped plugins whose component is
not in the plan, because DMS lists an unresolved widget id as an
unavailable entry in the bar editor.

Shipped plugins:

- **ZZ menu** (`zzMenu`, base, component `dms`): the desktop's command
  menu, a composite plugin with a bar widget and a launcher surface. The
  bar button's popout is the menu proper (`ZzMenuPanel.qml`): groups open
  as submenus with a breadcrumb and a back arrow, the keyboard drives it
  (arrows, Enter, Backspace or Left to go up, Escape), and typing narrows
  the current group first and everything below it after that. Like the
  launcher it has two homes: the bar button drops it under the pill, and
  the Super+Z bind opens the same panel in a centered `DankModal` over a
  dimmed background through the shell's widget IPC
  (`dms ipc call widget toggleWith zzMenu root`; `openWith zzMenu <group>`
  opens a group). The rows: the `zz` commands, Niri chores the shell has no page
  for (edit the personal overrides, validate and reload the config, hotkey
  overlay, pick-a-window facts for window rules, outputs, compositor log), the shell itself
  (restart, rescan plugins, shell log), system monitors, and documentation
  links. The menu is data: `menu.json` in the plugin directory, an object
  keyed by dotted ids where the dots are the tree, overlaid entry by entry
  with `~/.config/zz-fedora/menu.json`. `scripts/zz-menu-inventory`
  (`/usr/bin/python3`, stdlib) merges the two, evaluates every `when` guard
  in one shell batch, expands the providers (`refresh` from
  `zz refresh --list`; `apps` from `zz app list --json`, one subgroup per
  category with rows that install or remove by state), and prints the groups
  (with their parent) and rows;
  `ZzMenuInventory.qml`, shared by both surfaces, runs it and the rows. The
  launcher surface behind the `zz` trigger is search only: the launcher
  closes after any plugin item executes and cannot hold a submenu open, so
  there each row carries its group path in the subtitle and as search
  words, and the top-level groups are the launcher's categories. A row
  marked `terminal` runs through `scripts/zz-menu-run`, which opens
  `xdg-terminal-exec` (falling back to `ghostty`) and holds the window
  until a key is pressed so output and sudo prompts stay visible, except
  after Ctrl-C; a row that also says `hold: false` (an editor, a monitor,
  the coding agent) gets a window that closes when the program exits.
  Other rows run detached in a login shell. It is base because a ZZ desktop without its
  own menu is incomplete and it needs no wizard visibility; the doctor
  reads its manifest through the link. A test keeps `menu.json` in step
  with `bin/zz.d/` and the updater's target list.
- **Agent usage** (`agentUsage`, unit `ai-agent-usage`, component
  `dms-plugin-agent-usage`): a bar pill plus popout showing Claude Code and
  Codex rate limits with reset countdowns, tokens per day for the last week,
  and the all-time token split by model. The widget only displays records:
  `scripts/update-usage` inside the plugin runs one stdlib-Python collector
  per agent (`/usr/bin/python3`, the unit's only package) and writes
  `~/.local/state/zz-fedora/agent-usage/<agent>.json`, which the QML watches
  through `FileView`. Claude limits come from Anthropic's OAuth usage
  endpoint with the signed-in CLI's token; Codex limits from the Codex
  app-server RPC. Both keep their last probe under
  `~/.cache/zz-fedora/agent-usage/` so a popout opened twice in a row does
  not probe twice and a failed probe keeps the last known numbers whose
  window has not reset. The pill collapses out of the bar until a record carries
  usage, which is why it sits in the default bar layout. Optional
  multi-device aggregation merges JSON snapshots from a user-chosen synced
  folder; rate limits are never merged.

- **Proton manager** (`protonManager`, unit
  `gaming-proton-manager`, component `dms-plugin-proton-manager`)
  replaces the optional external Proton manager in the gaming catalog. Selected
  installs enable its daemon through the plan-filtered plugin seed and link
  `dotfiles/dms/.config/DankMaterialShell/plugins/ProtonManager/proton-manager.desktop`
  into the user application directory. **Proton Manager** appears under **Apps**
  in the DMS launcher; its desktop entry calls the daemon through plugin IPC to
  open a normal `DankFloatingWindow`, like System Monitor, with move/resize
  controls and normal focus switching. Closing unloads the UI once idle; read-only
  requests are cancelled, while explicit mutations finish before unloading. It has no bar widget or launcher-plugin results. Its product-linked
  directory is
  `dotfiles/dms/.config/DankMaterialShell/plugins/ProtonManager/`.
  The themed manager discovers native and Flatpak Steam, Heroic, Lutris, Bottles
  and WineZGUI destinations. Source pickers offer multiple Proton forks, Wine
  variants and launcher-supported DXVK/VKD3D components, with CPU filtering,
  release notes and progress. Steam offers game search and numeric App IDs,
  active and per-game selections. Missing or incompatible selected builds fail with a clear launch error.
  Fedora Python 3 performs the work outside the QML event loop. An authenticated
  `gh` CLI is used opportunistically for GitHub metadata, with anonymous HTTPS as
  the fallback. Persistent page caching and rate-limit cooldowns reduce API traffic. No Steam config
  files are rewritten. First use registers **Proton Manager** and requires one Steam
  restart plus opt-in in each game's Compatibility settings; subsequent changes
  route the next launch through a fixed Steam runtime contract. Builds needing
  another runtime must be selected directly in Steam. The wrapper executes
  installed builds in place, preserves launch arguments, and verifies the
  runtime contract again at launch. JSON changes are atomic and mutations are
  serialized per launcher destination. Downloads verify published SHA-512/SHA-256
  checksums or asset digests; older assets without checksums are labelled HTTPS only.
  Downloads reject unsafe archive paths/links and publish only after safe extraction;
  cancellation cleans staging. Removal is restricted to unreferenced plugin-installed
  builds while Steam and games are closed. Other launchers also require closing
  the launcher and clearing references in its settings before removal. Non-Steam
  runner selection stays in the owning launcher; Wine prefixes are not modified.
  See the plugin's README for supported sources, first use,
  storage, download limits and offline behavior.

## Greeter

`dms-greeter` (greetd), maintained in the standalone
`AvengeMedia/dank-greeter` repository since DMS 1.6, replaces the previous
shell-specific greeter. The
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
a first-run checkpoint once the user's shell state exists. The capability
probe remains as protection against an incomplete or independently packaged
greeter; without the command, the checkpoint completes and the greeter still
follows the theme through the cache symlinks.

## First-run contract

`modules/85-first-run.sh` keeps the independent-checkpoint model:

- `dms-registry-theme` installs Catppuccin through the running DMS backend
  when the seeded default is still selected and its file is missing. It
  verifies the downloaded theme and restarts DMS once to load it. A failed
  request leaves the checkpoint pending; already installed themes and user
  theme selections are left alone. The theme-generation checkpoint runs
  only after registry installation succeeds.
- `dms-theme` waits for the shell socket (`dms ipc call wallpaper get`) and
  then for the generated theme artifacts this install consumes (Ghostty
  `dankcolors`, `DankMatugen.colors`). There is no explicit "apply" IPC —
  DMS regenerates templates at startup and on theme changes — so artifact
  content is the completion signal: the Ghostty artifact is pre-seeded at
  the same path, so it only counts once its content diverges from the
  seed. Timeouts warn and retry at next login, bounded at three failed
  logins — after that the checkpoint completes with a warning instead of
  taxing every login, and the doctor checks surface the missing artifacts.
- `dms-gtk-theme` resolves the embedded shell's runtime payload and runs its
  `gtk.sh apply` followed by `gtk.sh patch` once the generated GTK colors
  exist, applying the same one-time GTK opt-in as the Settings button plus
  the GTK3 color patch the shell would otherwise defer to the next theme
  change, so GTK theming is automatic from the first login.
- `dms-greeter-profile` runs `dms-greeter sync --profile` unless the
  greeter action (or its user sync) was skip-recorded.

## Verification surface

- `tests/dms_theme.bats` and `tests/support/dms_registry_theme.py` cover
  registry requests, downloaded-file verification, retries, and idempotency.
- `tests/dms_plugins.bats` + `tests/support/dms_plugin.py` validate the
  shipped plugin manifests against the upstream schema, the catalog wiring,
  the enablement seed, and the collectors against fixture transcripts.
- `tests/packages_orchestration.bats` covers the greeter action;
  `tests/post_actions.bats` covers the seeds and first-run checkpoints;
  `tests/fedora_sources.bats` covers the COPR/Terra ownership rules.
- `dms doctor` runs best-effort in `zz doctor` diagnostics.
