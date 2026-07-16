# Noctalia v5 Integration Status

This is the living checkpoint for the Noctalia v5 integration. Update it every time this repo changes its Noctalia v5 packages, sources, config, Niri wiring, templates, tests, or assumptions.

## 2026-07-12 native Niri Outputs plugin

- Added the local `local/niri-outputs` Noctalia v5 plugin under the managed `noctalia` Stow package. It provides a lightweight bar launcher, optional Control Center shortcut, and fixed-size panel that attaches to the bar and opens near its launcher by default. The panel queries Niri when opened, refreshed, reset, or reconciled after keep or restore; no plugin process polls in the background.
- The panel reads connected outputs and their modes from `niri msg -j outputs`, then exposes native Noctalia controls for enablement, mode, scale, transform, logical position, automatic horizontal arrangement, and VRR.
- Preview renders the draft into temporary KDL under `$XDG_RUNTIME_DIR` and switches Niri once to a temporary top-level config beside the normal config. That file copies `~/.config/niri/config.kdl` but replaces its managed `display.kdl` include, preserving every other relative include without including or watching the persistent output file. Revert and timeout switch once back to the normal config; no per-output IPC commands or captured-state replay are used. Preview never modifies the persistent output file, so restarting Niri or rebooting naturally returns to the normal configuration. A detached watchdog exists only during the confirmation window and retries the single switch back if necessary.
- Keep copies the already validated temporary output include into `~/.config/niri/cfg/display.kdl`, backs up an existing file as `display.kdl.previous`, and switches Niri back to the normal top-level config. Each switch waits for a successful `ConfigLoaded` event because Niri queues `load-config-file` parsing asynchronously.
- The plugin owns the complete dedicated output file, `display.kdl`, and writes the connected outputs represented by the panel. Advanced or disconnected settings not represented by the panel can be recovered from the `.previous` backup but are not merged into the generated file.
- The managed Noctalia config enables plugin version 0.1.1, targets plugin API 3, and places its launcher in the default bar. The English fallback catalog owns all static Luau UI copy, manifest setting labels, localized mode metadata, pluralized countdown text, and backend error grammar; connector names, modes, paths, and diagnostic details remain runtime values. Plugin code is portable; connected output names, geometry, temporary preview files, and generated KDL remain local hardware state and are not committed.
- Added `tests/noctalia_niri_outputs_plugin.bats` for managed wiring, manifest surfaces, translation-key coverage, Niri JSON normalization, temporary config previews, explicit config-path restoration, detached timeout rollback, persistence, atomic output/preview queries, panel preview-state reconciliation, and last-output protection.

## 2026-07-11 wallpaper asset replacement

- Removed the former wallpaper files because their redistribution provenance and licenses were not documented.
- Added sixteen license-cleared 6000×4000 photographs spanning mountains, desert, coast, forest, ice, water, architecture, night, and macro subjects. `assets/wallpapers/PROVENANCE.md` records every creator, source page, per-file license, source dimensions, processing step, and SHA-256 digest.
- Restored installer seeding, the managed-config policy, doctor coverage, and Noctalia's wallpaper directory. Seeding is non-destructive: a same-named user file is never replaced.
- Set `Alpenglow.jpg` as the portable initial default.

Noctalia v5 is the project's supported shell baseline. Treat this file as the handoff note for future work: compare this checkpoint with the then-current Noctalia v5 repo/docs before changing the integration again.

## Checkpoint: 2026-07-11

Repo branch: `noctalia-v5`

Fedora-only project restructure:

- The project is now named ZZ Fedora and only supports Fedora Linux. Catalogs were flattened from distro-qualified paths, so the Noctalia bundle now lives at `bundles/base/noctalia.bundle` and its action manifest at `packages/actions/base-noctalia.actions`.
- The Noctalia action IDs are now `noctalia-v5` and `noctalia-greeter`; the redundant Fedora suffixes were removed with the multi-distro abstraction.
- Fedora package/source operations now live directly in `lib/fedora.sh`; there is no runtime distro adapter selection.

Official Fedora package transition:

- Fedora 44 Updates now carries the official `noctalia` package. Stable currently has `noctalia-5.0.0~beta1-1.fc44`; `noctalia-5.0.0~beta2-1.fc44` entered Updates Testing on 2026-07-10 as Bodhi update `FEDORA-2026-e863a3e051`.
- Do not fall back to the stable beta1 build. It is the `v5.0.0-beta1` code previously reproduced as crashing on a true fresh state, and it does not understand `concave_edge_corners`.
- The `noctalia-v5` base action now installs the official Fedora `noctalia` package with `updates-testing` allowed while beta2 is there. Once beta2 is promoted, the same transaction naturally resolves it from stable Updates. Action verification requires `5.0.0~beta2` or newer so an installed beta1 cannot incorrectly skip the upgrade.
- The base Noctalia bundle no longer claims the LionHeartP COPR as its source. The COPR remains required for two separate packages that Fedora does not currently provide: `noctalia-greeter` and `qt6ct-kde`.
- The LionHeartP source descriptor and base rationale now describe only Noctalia Greeter and patched Qt integration. Terra's provider exclusion is limited to `noctalia-greeter`.
- Fedora beta2 does not currently provide the `desktop-notification-daemon` virtual capability that the former COPR shell package advertised. On this system, the official package transaction therefore adds `mako` to satisfy `system-config-printer`'s dependency. No repo autostart wiring was added for Mako, but Fedora packaging should be rechecked because D-Bus activation before Noctalia starts could claim the notification service first.

Config schema migration:

- The managed top-bar concave corners now use positive `radius_bottom_left = 10` and `radius_bottom_right = 10` values with `concave_edge_corners = true`.
- This preserves the prior visual shape while removing the beta2 warning that negative corner radii are deprecated.
- No Noctalia GUI state was promoted for this change. The override report shows the local `SilentPeaks.jpg` wallpaper selection, state-only idle behavior preferences, and generated monitor/widget state. These were outside this package/schema change and remain local.

Candidate validation:

- Downloaded and extracted the official `noctalia-5.0.0~beta2-1.fc44` RPM without installing it system-wide.
- `noctalia config validate` from the extracted beta2 package accepted the managed config with no warnings.
- The extracted `v5.0.0-beta2` binary was launched alongside the existing shell with isolated XDG config/state/cache/runtime paths and a symlink to the active Niri Wayland socket.
- With no initial config or `settings.toml`, beta2 generated fresh state and remained alive until `timeout -s TERM 10s` stopped it with status `124`. The earlier fresh-state crash did not reproduce.
- The previously installed COPR build also validated the migrated managed config without warnings.

## Checkpoint: 2026-07-04

Repo branch: `noctalia-v5`

Local Noctalia Greeter replacement:

- Reference repos checked for the greeter decision:
  - `/home/user/repos/noctalia`: `dd55eda0001c7f19296df785d6217aa8aa30efe4`
  - `/home/user/repos/noctalia-docs`: `633aabb00a208361a0ce833ec7ee8bf0ac69817e`
  - `/home/user/repos/noctalia-greeter`: `3dcf1e4f15be861de636bfd442da09db7db37ad2`
- Noctalia Greeter is a separate greetd greeter, not part of the main Noctalia shell process. greetd runs `noctalia-greeter-session`, which starts the bundled `noctalia-greeter-compositor` and then the greeter UI.
- The docs say to install `noctalia-greeter` from the distro when available, with `greetd`, D-Bus, and polkit available on the machine. The greeter stores admin-managed state in `/var/lib/noctalia-greeter/greeter.toml`.
- Fedora package metadata showed `noctalia-greeter-1.0.0-1.gite12f8f8.fc44` available from `copr:lionheartp/Hyprland`. Terra also carries older `noctalia-greeter` builds, so the Terra exclude covers `noctalia-greeter`.
- `base-login-manager` now runs the required `noctalia-greeter` action instead of installing `sddm`. The action installs/syncs the COPR greeter package, writes `/etc/greetd/config.toml` for `/usr/bin/noctalia-greeter-session`, prepares the `greeter` account and `/var/lib/noctalia-greeter`, patches `/etc/pam.d/greetd` for `pam_systemd.so` or `pam_elogind.so` when available, initializes `greeter.toml`, and enables `greetd.service`.
- The existing display-manager policy is preserved: if any display manager is already enabled, including SDDM, GDM, Plasma Login Manager, LightDM, Ly, or greetd, the Noctalia Greeter fallback action records a skip and does not install or enable another login manager.
- The managed Noctalia shell config enables `[shell.greeter_sync].auto_sync`, so once the greeter is installed the shell uses its native greeter sync path to mirror wallpaper, palette, theme mode, session actions, and monitor layout changes into `/var/lib/noctalia-greeter/appearance.json`. The privilege command remains unset because Noctalia's default `pkexec` or `run0` escalation is preferred when logind or elogind provides an in-session polkit prompt.

Local Settings UI override promotion:

- Promoted portable Noctalia Settings UI preferences into `dotfiles/noctalia/.config/noctalia/config.toml`: the default bar module order, `location.auto_locate`, compact clock format, hidden empty media widget, hidden network label, active-workspace taskbar filtering, taskbar window titles, and hidden weather condition text.
- Removed those promoted keys from `~/.local/state/noctalia/settings.toml` so the stowed config is again the source of truth.
- Removed the absolute `wallpaper.default.path` GUI override because it was equivalent to the managed portable wallpaper default.
- Left generated/local state in `~/.local/state/noctalia/settings.toml`, including `lockscreen_widgets`, `wallpaper.last`, and the `wallpaper.monitors.Virtual-1` entry. These still encode runtime or output-specific state and must not be stowed.
- Validation after the promotion: `noctalia config validate` passed, and the override report showed no remaining state keys overriding the managed dotfile.

Custom Catppuccin Mocha palette:

- Added `dotfiles/noctalia/.config/noctalia/palettes/catppuccin-mocha-blue.json` as a managed Noctalia v5 custom palette.
- The palette follows the local Catppuccin style guide's Mocha mappings for base/surface/text/terminal colors, assigns Catppuccin Blue as Noctalia's primary accent/link color, Catppuccin Green as the secondary/success role, and Catppuccin Yellow as the tertiary/warning/hover role so highlighted surfaces do not collapse into the primary accent color.
- The managed `[theme]` now uses `source = "custom"` with `custom_palette = "catppuccin-mocha-blue"`, keeping built-in Catppuccin as the fallback palette if the custom JSON is unavailable.
- Removed the live `[theme]` keys from `~/.local/state/noctalia/settings.toml`; otherwise the app-managed state would continue forcing `source = "builtin"` and hide the managed custom palette.

Starship prompt contrast:

- The managed Starship template now keeps top-level prompt settings before the fallback `[palettes.noctalia]` table so freshly seeded configs parse with a real top-level `format`.
- Prompt section text uses the rendered `surface0` token consistently. Section backgrounds use Noctalia Starship palette tokens (`text`, `blue`, `yellow`, `blue`, and `green`) so the prompt follows the active Noctalia theme instead of pinning fixed colors; language modules intentionally reuse the directory section color.
- Optional git and language separators are rendered through conditional Starship custom modules so empty git/language sections do not leave colored blocks behind.
- Added `tests/starship_theme.bats` and `tests/helpers/starship_contrast.py`; the test resolves Noctalia's Starship palette aliases against the built-in dark terminal palettes fixture, enforces the theme-token section order, verifies optional separators are conditional, rejects adjacent duplicate section colors, and checks a 4.0:1 minimum text contrast for the managed default palette plus Catppuccin. Adjacent section checks allow separation by either luminance contrast or RGB color distance because prompt block boundaries can be hue-distinct even when their luminance is close.

## Checkpoint: 2026-07-03

Repo branch: `noctalia-v5`

Current upstream and package validation:

- Upstream issue `#3250` now appears fixed in source. The refreshed local reference repo `/home/user/repos/noctalia` was at `a0d8efc30ead165a6a56349fdda3c722309c0745` (`feat(tray): add drawer_item_size configuration`).
- Noctalia v5 docs in `/home/user/repos/noctalia-docs` were rechecked for config layering. User-managed config belongs in `~/.config/noctalia/*.toml`; Noctalia-managed GUI/runtime overrides live in `~/.local/state/noctalia/settings.toml` and load last.
- The docs confirm split config is supported: Noctalia reads every root `*.toml` in `~/.config/noctalia/` sorted alphabetically, and `[include]` can pull in files or directories when a subdirectory layout is wanted.
- Current upstream `src/shell/hot_corners/hot_corners.cpp` guards `HotCorners::onConfigReload()` when `m_config` or `m_wayland` is null, which addresses the startup ordering crash identified below.
- Fedora package metadata was refreshed. Latest observed COPR shell build: `5.0.0-0.242.git6b39dc8.fc44`. Latest observed Terra shell build: `5.0.0^20260703git.6e7aa3b-1.fc44`.
- The COPR `0.242.git6b39dc8` RPM was downloaded and extracted without installing system-wide.
- The extracted `noctalia v5.0.0 (6b39dc8)` binary was run in the active Niri session with a fresh isolated XDG config/state/cache profile and an isolated `XDG_RUNTIME_DIR` symlinked to the real Wayland socket, while the existing Noctalia process stayed running.
- Result: the candidate created fresh `state/noctalia/settings.toml`, stayed alive until `timeout -s TERM 10s` stopped it with status `124`, and did not segfault.

Current repo wiring:

- At this checkpoint, the Fedora Noctalia action installed or `distro-sync`ed the shell from `copr:lionheartp/Hyprland`.
- Terra remained enabled for Ghostty, but its competing Noctalia shell provider was excluded so normal DNF updates kept Noctalia on the validated LionHeartP COPR provider.
- Noctalia remains a custom action instead of a plain `dnf` package manifest because the package provider is part of the integration contract.
- The base Noctalia bundle now stows `dotfiles/noctalia/.config/noctalia/config.toml` as the hardware-agnostic user config layer, including semi-transparent `0.9` bar, dock, notification, and OSD backgrounds.
- Qt application theming uses the built-in `kcolorscheme` template consumed by the managed `qt6ct` configuration. The normal `qt` template is disabled because upstream renders it to both Qt5 and Qt6 config roots, while this baseline no longer installs Qt5 theme support.
- The pre-v5 Yaru icon accent sync has been restored through a v5 user template. Noctalia renders `colors.primary.default.hex` to `~/.cache/noctalia/icon-theme-accent`, then `~/.local/bin/noctalia-sync-icon-theme` maps it to the closest installed Yaru accent and updates GTK, Qt 6, KDE globals, and `QS_ICON_THEME`.
- The repo still does not manage `~/.local/state/noctalia/settings.toml`; fresh-start lockscreen widget state includes output names and coordinates, so it remains generated state.

Prior crash investigation:

Fresh-state reboot result:

- Rebooting once on latest `ad11b4b` with the existing user state launched Noctalia successfully.
- The existing state already contained `[lockscreen_widgets]`, so that boot did not exercise a true fresh-state lockscreen widget bootstrap.
- The active state file was then renamed to `~/.local/state/noctalia/settings.toml.backup-20260702-233351` to force a fresh state path.
- On the next reboot, Noctalia failed on the first startup and created a new `~/.local/state/noctalia/settings.toml`.
- Starting again with that generated `settings.toml` present worked. The running process after the second start was plain `noctalia`, and the log showed normal startup.
- This explains why the crash can look intermittent: the first failed launch writes enough state for the next launch to succeed.

Confirmed crash signature from installed package:

- `coredumpctl` recorded SIGSEGV for `/usr/bin/noctalia` at `2026-07-02 23:34:58 -03`.
- Package in the coredump: the former COPR shell package, build `5.0.0-0.240.gitad11b4b.fc44`.
- The installed-package stack matched the earlier isolated extracted-RPM test:

  ```text
  std::_Function_handler<void (), Application::initBarDockAndLayout()::{lambda()#4}>::_M_invoke
  ConfigService::fireReloadCallbacks()
  ConfigService::setLockscreenWidgetsState(LockscreenWidgetsConfig const&)
  Application::initWidgetControllersAndCallbacks()
  Application::run(std::function<void ()>)
  ```

- Source review still points to an upstream startup ordering bug:
  - `Application::initBarDockAndLayout()` registers reload callbacks, including `m_hotCorners.onConfigReload()`.
  - `m_hotCorners.initialize(...)` does not run until the end of `Application::initWidgetControllersAndCallbacks()`.
  - `LockscreenWidgetsController::loadSnapshotFromConfig()` creates missing per-output login-box widgets and calls `saveSnapshotToConfig()`.
  - `ConfigService::setLockscreenWidgetsState()` writes `settings.toml`, reloads config, then calls `fireReloadCallbacks()`.
  - That can invoke `HotCorners::onConfigReload()` before `HotCorners` has a `ConfigService*`.

Generated state details:

- The fresh state file was hardware/session specific. It contained a login box for output `Virtual-1` with VM-specific geometry such as `cx = 932.0`, `cy = 1011.0`, and `output = "Virtual-1"`.
- Noctalia docs say user/dotfile config belongs in `~/.config/noctalia/*.toml`, while `~/.local/state/noctalia/settings.toml` is app-managed GUI/runtime override state.
- The v5 lockscreen widget schema requires concrete output names and coordinates for login-box placement. There is no documented hardware-agnostic token for this.
- A static Stow-managed `settings.toml` is therefore the wrong workaround.
- If we need an installer-side workaround before upstream fixes this, it should be a session-time first-run helper that generates state from the active Wayland outputs before launching Noctalia. A retry wrapper is still the wrong shape because it leaves a visible crash and coredump.

Upstream report:

- Created upstream issue: <https://github.com/noctalia-dev/noctalia/issues/3250>
- Issue title: `[BUG] First start can segfault when lockscreen widgets create settings.toml`
- The issue includes the installed-package coredump stack, the generated fresh `settings.toml`, Fedora/Niri environment details, duplicate-search notes, and the suspected reload-callback initialization order.

Current decision:

- Use the validated COPR shell package.
- Stow a curated `~/.config/noctalia/config.toml` user config.
- Do not add a static Noctalia state seed, and do not stow generated `settings.toml`.
- Do not add a simple retry wrapper around Noctalia.
- Keep forcing the COPR provider and excluding Terra's competing shell package.
- Before changing Noctalia provider or package wiring again, re-test the candidate from a true missing-`settings.toml` state.

## Checkpoint: 2026-07-02

Repo branch: `noctalia-v5`

Reference repo heads checked:

- `~/repos/noctalia`: `6e7aa3b4 feat(plugins): added support for Input focus`
- `~/repos/noctalia-docs`: `eb31c32 plugins: ui - focus`

Upstream state:

- Noctalia v5 is now documented as Beta.
- Current upstream release tag observed locally: `v5.0.0-beta1` at `ad11b4ba`.
- Niri docs still use `spawn-at-startup "noctalia"` and `noctalia msg ...` keybindings.
- Built-in template IDs still include `ghostty`, `starship`, `kcolorscheme`, and `niri`.
- Fedora source recommendation at this checkpoint remained the LionHeartP COPR shell package.
- Current Fedora build dependencies include `wireplumber-devel`; the RPM runtime dependencies now include `libwireplumber-0.5`, `libmd4c`, and `libtomlplusplus`.

Fedora package query on Fedora 44 with Terra and LionHeartP COPR enabled:

- Latest observed COPR shell build: `5.0.0-0.240.gitad11b4b.fc44`.
- Latest observed Terra shell build: `5.0.0^20260702git.8d2c688-1.fc44`.
- Installed local shell build during this checkpoint: `5.0.0-0.222.gitd2d2f9b.fc44`.

Fresh-profile candidate test:

- Candidate tested without installing system-wide by downloading and extracting COPR build `5.0.0-0.240.gitad11b4b.fc44.x86_64`.
- Missing local runtime libraries for the extracted binary were supplied from downloaded Fedora RPMs `tomlplusplus-3.4.0-7.fc44.x86_64` and `md4c-0.5.1-5.fc44.x86_64` through `LD_LIBRARY_PATH`.
- The active pinned Noctalia instance was left running, so the test used an isolated `XDG_RUNTIME_DIR` with a symlink to the real Wayland socket to avoid the single-instance lock.
- Result: `noctalia v5.0.0 (ad11b4b)` segfaulted from fresh XDG config/state/cache.
- Logs showed `no config files found, using defaults`, wallpaper/bar creation, and freshly generated `state/noctalia/settings.toml` with `lockscreen_widgets` state immediately before SIGSEGV.
- `coredumpctl` recorded SIGSEGV for `/tmp/.../extract/usr/bin/noctalia`.

Follow-up crash triage:

- No exact upstream issue or PR was found for the fresh-state `lockscreen_widgets`/`HotCorners` startup crash when searching `noctalia-dev/noctalia` issues and PRs for `SIGSEGV`, `lockscreen_widgets`, `settings.toml`, `fresh config`, `hot corners`, and related terms.
- Nearby upstream crash issues exist, for example `#3213` (`libqalculate` SIGSEGV, fixed), `#3086` (wallpaper/settings crash), and `#3013` (NetworkManager D-Bus timeout crash), but they do not match this startup signature.
- COPR debuginfo for build `5.0.0-0.240.gitad11b4b.fc44` resolved the crash stack to:

  ```text
  std::_Function_handler<void (), Application::initBarDockAndLayout()::{lambda()#6}>::_M_invoke
  ConfigService::setLockscreenWidgetsState(LockscreenWidgetsConfig const&)
  LockscreenWidgetsController::initialize(...)
  Application::initWidgetControllersAndCallbacks()
  ```

- Lambda `#6` in `Application::initBarDockAndLayout()` is the reload callback `m_configService.addReloadCallback([this]() { m_hotCorners.onConfigReload(); });`.
- At `ad11b4b`, `m_hotCorners.initialize(...)` runs later, at the end of `Application::initWidgetControllersAndCallbacks()`, after `m_lockscreenWidgetsController.initialize(...)`.
- On a fresh profile, `LockscreenWidgetsController::initialize()` normalizes the default login-box widget and calls `ConfigService::setLockscreenWidgetsState(...)`. That writes `settings.toml`, calls `loadAll()`, then fires reload callbacks while `m_hotCorners.m_config` is still null.
- `HotCorners::onConfigReload()` dereferences `m_config` without the null guard that `HotCorners::onOutputChange()` has. This makes the crash look like an upstream initialization-order regression, not an installer-side config mistake.
- The known-good `d2d2f9b` source initialized `m_hotCorners` in `initNotificationAndOsd()` before `initBarDockAndLayout()` registered the reload callback and before `initWidgetControllersAndCallbacks()` could write fresh lockscreen widget state. The later beta code moved hot-corner initialization to the end of `initWidgetControllersAndCallbacks()` so hot-corner surfaces stack above bar/dock.

Current decision:

- Keep the Fedora pin at COPR build `5.0.0-0.222.gitd2d2f9b.fc<fedora-release>`.
- Keep Niri launching plain `noctalia`; do not add a retry wrapper.
- Do not pre-seed Noctalia config to mask the crash.
- Re-test a newer candidate before removing the pin. Prefer a candidate that fixes or guards hot-corner reload before initialization, then validate with an exact same-runtime test after stopping the pinned instance or a clean VM login test.

## Checkpoint: 2026-06-28

Repo branch: `noctalia-v5`

Relevant repo commits:

- `71176fc Switch Noctalia integration to v5`
- `081e5f8 Pin Noctalia v5 to working Fedora build`

Reference repos:

- `~/repos/noctalia`
- `~/repos/noctalia-docs`

Fedora package state at this checkpoint:

- Installed through `packages/actions/base-noctalia.actions`.
- Action id: `noctalia-v5`.
- Package source: `copr:lionheartp/Hyprland`.
- Known-good COPR shell build: `5.0.0-0.222.gitd2d2f9b.fc<fedora-release>`.
- The action applies `dnf versionlock add` for the pinned package.

## Why The Pin Existed

On a fresh Fedora 44 VM under SDDM + Niri, latest packaged Noctalia v5 build `dfa00a4` crashed on first fresh-state startup. The visible result after login was Niri's gray background and cursor, with no Noctalia surfaces.

Observed details:

- Niri and SDDM were healthy.
- `spawn-at-startup "noctalia"` was correct.
- `noctalia v5.0.0 (dfa00a4)` segfaulted after creating wallpaper/bar and while writing/reloading fresh lockscreen widget state.
- The crash reproduced with both Terra and COPR packages for `dfa00a4`.
- Disabling the setup wizard did not fix it.
- A retry wrapper worked only because the first crash wrote enough state for the second launch, but that was rejected as the wrong solution.
- COPR shell build `5.0.0-0.222.gitd2d2f9b.fc44` started cleanly from an isolated fresh XDG config/state/cache profile.

Resolution as of 2026-07-11:

- Keep Niri launching plain `noctalia`.
- The pin was removed after the official Fedora beta2 package started cleanly from a true missing-`settings.toml` state.
- Avoid Fedora's beta1 build because it contains the previously reproduced startup bug; use the beta2 update path until beta2 reaches stable Updates.

## Current Integration Shape

No v4 migration or compatibility path exists or should be added. This branch is a clean v5 integration.

Niri:

- Managed autostart remains `spawn-at-startup "noctalia"`.
- Niri keybindings call `noctalia msg ...` directly.
- `~/.config/niri/noctalia.kdl` is seeded only when absent.

Noctalia config:

- `~/.config/noctalia/config.toml` is stowed from `dotfiles/noctalia/.config/noctalia/config.toml`.
- The managed config is intentionally portable: polkit agent, telemetry off, `~/.local/share/backgrounds`, the bundled `Alpenglow.jpg` wallpaper, custom Catppuccin Mocha Blue dark theme, default bar module order, selected widget display preferences, Noctalia bar end margin, semi-transparent shell surface backgrounds, selected built-in templates, and selected community templates.
- The managed config also declares `[theme.templates.user.icon_theme]` to restore the pre-v5 desktop icon accent sync without reintroducing v4 `user-templates.toml`.
- GUI/runtime overrides remain app-managed in `~/.local/state/noctalia/settings.toml` and load after the stowed config.
- Do not put lockscreen widgets, desktop widgets, monitor names, output names, connector lists, resolutions, coordinates, or generated setup state in the stowed config.
- Local verification of the official Fedora beta2 RPM showed it starts from an isolated empty XDG config/state/cache profile with `no config files found, using defaults` and remains alive until deliberately terminated.
- If future config grows beyond one file, keep extra root files as sorted `*.toml` files or use the documented `[include]` table for subdirectories.

Templates:

- Built-in templates enabled by the managed config: `niri`, `ghostty`, `starship`, `btop`, `gtk3`, `gtk4`, `qt`, and `kcolorscheme`.
- Community templates enabled by the managed config: `pywalfox`, `zen-browser`, `neovim`, `vscode`, `zed`, and `yazi`. No v4 plugins, QuickShell config, or migration shims are present.
- User templates enabled by the managed config: `icon_theme`.

Related managed files:

- `~/.local/share/backgrounds`
- `~/.config/noctalia/config.toml`
- `~/.config/noctalia/templates/icon-theme-accent`
- `~/.config/niri/cfg/display.kdl`
- `~/.config/niri/noctalia.kdl`
- `~/.config/ghostty/themes/noctalia`
- `~/.local/bin/noctalia-sync-icon-theme`

## Repo Wiring

Primary files:

- `bundles/base/noctalia.bundle`
- `packages/actions/base-noctalia.actions`
- `modules/35-custom-actions.sh`
- `modules/80-post-actions.sh`
- `modules/90-doctor.sh`
- `config/base-responsibility.tsv`
- `config/managed-config.tsv`
- `.agents/skills/promote-noctalia-config/SKILL.md`
- `.agents/skills/promote-noctalia-config/scripts/noctalia_override_report.py`
- `dotfiles/noctalia/.config/noctalia/config.toml`
- `dotfiles/noctalia/.config/noctalia/templates/icon-theme-accent`
- `dotfiles/noctalia/.local/share/noctalia/plugins/niri-outputs/`
- `dotfiles/noctalia/.local/bin/noctalia-sync-icon-theme`
- `dotfiles/niri/.config/niri/cfg/autostart.kdl`
- `dotfiles/niri/.config/niri/cfg/keybinds.kdl`
- `templates/niri/noctalia.kdl`

Tests covering this checkpoint:

- `tests/planner.bats`
- `tests/package_modules.bats`
- `tests/post_actions.bats`
- `tests/doctor_hardening.bats`
- `tests/cli_smoke.bats`
- `tests/noctalia_niri_outputs_plugin.bats`

Last validation run:

```bash
noctalia config validate
! rg -n 'Virtual-|DP-|HDMI-|output =|cx =|cy =|width =|height =' dotfiles/noctalia/.config/noctalia
python3 .agents/skills/promote-noctalia-config/scripts/noctalia_override_report.py
bash -n modules/35-custom-actions.sh modules/90-doctor.sh lib/fedora.sh
bats tests/fedora_sources.bats
bats --filter 'Noctalia v5 Fedora action' tests/package_modules.bats
bats --filter 'Fedora base plan includes protected base desktop bundles and rationale|minimal desktop app profile keeps Niri baseline' tests/planner.bats
bats --filter 'base responsibility and managed config policy|managed config conflicts and base rationale' tests/doctor_hardening.bats
bats tests/cli_smoke.bats
bats tests/noctalia_niri_outputs_plugin.bats
./tests/smoke.sh
```

## Future Update Checklist

When revisiting Noctalia v5:

1. Check current upstream state in `~/repos/noctalia` and docs in `~/repos/noctalia-docs`.
2. Compare changes since official `v5.0.0-beta2` and the previously crashing beta1 commit `ad11b4b`.
3. Inspect the official Fedora `noctalia` package first. Check the LionHeartP COPR and Terra only for `noctalia-greeter` and `qt6ct-kde` provider changes.
4. Test the candidate build in a live Niri session with a fresh isolated profile:

   ```bash
   base="$(mktemp -d)"
   mkdir -p "$base/config" "$base/state" "$base/cache"
   timeout -s TERM 8s env \
     HOME="$HOME" \
     XDG_CONFIG_HOME="$base/config" \
     XDG_STATE_HOME="$base/state" \
     XDG_CACHE_HOME="$base/cache" \
     XDG_RUNTIME_DIR="/run/user/$(id -u)" \
     WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
     DISPLAY="${DISPLAY:-:0}" \
     DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}" \
     noctalia
   ```

5. Once beta2 is stable in Fedora 44 Updates, remove the temporary `updates-testing` allowance from the shell action. If the greeter or `qt6ct-kde` enters Fedora, narrow or remove the remaining LionHeartP source wiring accordingly.
6. Re-check v5 docs for renamed config fields, template IDs, IPC commands, package names, source recommendations, and setup wizard behavior.
7. Keep the integration clean v5-only. Do not add v4 compatibility, plugin migration, or QuickShell fallback paths.
8. Update this file with the new checkpoint, package/build decision, VM/manual test result, and validation commands.

## Open Questions

- Decide whether the shell can become a plain `dnf` base manifest after beta2 reaches Fedora stable, or whether keeping the action is useful for explicit package verification.
- Recheck whether Fedora's `noctalia` package gains the `desktop-notification-daemon` and `PolicyKit-authentication-agent` virtual provides that the COPR package declared; remove any resulting Mako fallback if it becomes unnecessary.
- Re-evaluate the remaining COPR when Fedora gains `noctalia-greeter` or `qt6ct-kde`.
- Treat future Noctalia config changes, including `setup_wizard_enabled = false`, lockscreen settings, widgets, weather, plugins, browser theming, or community templates, as explicit customization checkpoints.
