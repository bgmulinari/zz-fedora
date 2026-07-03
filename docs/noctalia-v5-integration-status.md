# Noctalia v5 Integration Status

This is the living checkpoint for the Noctalia v5 integration. Update it every time this repo changes its Noctalia v5 packages, sources, config, Niri wiring, templates, tests, or assumptions.

Noctalia v5 is currently beta software and this branch is experimental. Treat this file as the handoff note for future work: compare this checkpoint with the then-current Noctalia v5 repo/docs before changing the integration again.

## Checkpoint: 2026-07-03

Repo branch: `noctalia-v5`

Current upstream and package validation:

- Upstream issue `#3250` now appears fixed in source. The refreshed local reference repo `/home/user/repos/noctalia` was at `a0d8efc30ead165a6a56349fdda3c722309c0745` (`feat(tray): add drawer_item_size configuration`).
- Current upstream `src/shell/hot_corners/hot_corners.cpp` guards `HotCorners::onConfigReload()` when `m_config` or `m_wayland` is null, which addresses the startup ordering crash identified below.
- Fedora package metadata was refreshed. COPR latest observed: `noctalia-git-5.0.0-0.242.git6b39dc8.fc44`. Terra latest observed: `noctalia-git-5.0.0^20260703git.6e7aa3b-1.fc44`.
- The COPR `0.242.git6b39dc8` RPM was downloaded and extracted without installing system-wide.
- The extracted `noctalia v5.0.0 (6b39dc8)` binary was run in the active Niri session with a fresh isolated XDG config/state/cache profile and an isolated `XDG_RUNTIME_DIR` symlinked to the real Wayland socket, while the existing Noctalia process stayed running.
- Result: the candidate created fresh `state/noctalia/settings.toml`, stayed alive until `timeout -s TERM 10s` stopped it with status `124`, and did not segfault.

Current repo wiring:

- The Fedora Noctalia action installs or `distro-sync`s `noctalia-git` from `copr:lionheartp/Hyprland`.
- Terra remains enabled for Ghostty, but the Terra source setup sets `terra.excludepkgs=noctalia-git` so normal DNF updates keep Noctalia on the validated LionHeartP COPR provider.
- Noctalia remains a custom action instead of a plain `dnf` package manifest because the package provider is part of the integration contract.

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
- Package in the coredump: `noctalia-git/5.0.0-0.240.gitad11b4b.fc44`.
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

- Use the validated COPR `noctalia-git` package.
- Do not add a static Noctalia state seed.
- Do not add a simple retry wrapper around Noctalia.
- Keep forcing the COPR provider and excluding Terra's `noctalia-git` package.
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
- Fedora source recommendation remains LionHeartP COPR with `dnf install noctalia-git`.
- Current Fedora build dependencies include `wireplumber-devel`; the RPM runtime dependencies now include `libwireplumber-0.5`, `libmd4c`, and `libtomlplusplus`.

Fedora package query on Fedora 44 with Terra and LionHeartP COPR enabled:

- COPR latest observed: `noctalia-git-5.0.0-0.240.gitad11b4b.fc44`.
- Terra latest observed: `noctalia-git-5.0.0^20260702git.8d2c688-1.fc44`.
- Installed local package during this checkpoint: `noctalia-git-5.0.0-0.222.gitd2d2f9b.fc44`.

Fresh-profile candidate test:

- Candidate tested without installing system-wide by downloading and extracting the COPR RPM `noctalia-git-5.0.0-0.240.gitad11b4b.fc44.x86_64`.
- Missing local runtime libraries for the extracted binary were supplied from downloaded Fedora RPMs `tomlplusplus-3.4.0-7.fc44.x86_64` and `md4c-0.5.1-5.fc44.x86_64` through `LD_LIBRARY_PATH`.
- The active pinned Noctalia instance was left running, so the test used an isolated `XDG_RUNTIME_DIR` with a symlink to the real Wayland socket to avoid the single-instance lock.
- Result: `noctalia v5.0.0 (ad11b4b)` segfaulted from fresh XDG config/state/cache.
- Logs showed `no config files found, using defaults`, wallpaper/bar creation, and freshly generated `state/noctalia/settings.toml` with `lockscreen_widgets` state immediately before SIGSEGV.
- `coredumpctl` recorded SIGSEGV for `/tmp/.../extract/usr/bin/noctalia`.

Follow-up crash triage:

- No exact upstream issue or PR was found for the fresh-state `lockscreen_widgets`/`HotCorners` startup crash when searching `noctalia-dev/noctalia` issues and PRs for `SIGSEGV`, `lockscreen_widgets`, `settings.toml`, `fresh config`, `hot corners`, and related terms.
- Nearby upstream crash issues exist, for example `#3213` (`libqalculate` SIGSEGV, fixed), `#3086` (wallpaper/settings crash), and `#3013` (NetworkManager D-Bus timeout crash), but they do not match this startup signature.
- COPR debuginfo for `noctalia-git-5.0.0-0.240.gitad11b4b.fc44` resolved the crash stack to:

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

- Keep the Fedora pin at `noctalia-git-5.0.0-0.222.gitd2d2f9b.fc<fedora-release>`.
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

- Installed through `packages/actions/base-noctalia-fedora.actions`.
- Action id: `noctalia-v5-fedora`.
- Package source: `copr:lionheartp/Hyprland`.
- Known-good build: `noctalia-git-5.0.0-0.222.gitd2d2f9b.fc<fedora-release>`.
- The action applies `dnf versionlock add` for the pinned package.

## Why The Pin Exists

On a fresh Fedora 44 VM under SDDM + Niri, latest packaged Noctalia v5 build `dfa00a4` crashed on first fresh-state startup. The visible result after login was Niri's gray background and cursor, with no Noctalia surfaces.

Observed details:

- Niri and SDDM were healthy.
- `spawn-at-startup "noctalia"` was correct.
- `noctalia v5.0.0 (dfa00a4)` segfaulted after creating wallpaper/bar and while writing/reloading fresh lockscreen widget state.
- The crash reproduced with both Terra and COPR packages for `dfa00a4`.
- Disabling the setup wizard did not fix it.
- A retry wrapper worked only because the first crash wrote enough state for the second launch, but that was rejected as the wrong solution.
- COPR build `noctalia-git-5.0.0-0.222.gitd2d2f9b.fc44` started cleanly from an isolated fresh XDG config/state/cache profile.

Current decision:

- Keep Niri launching plain `noctalia`.
- Pin to the known-good Fedora COPR build until a newer v5 build starts cleanly from fresh state.
- Remove the pin when upstream/package behavior is verified healthy.

## Current Integration Shape

No v4 migration or compatibility path exists or should be added. This branch is a clean v5 integration.

Niri:

- Managed autostart remains `spawn-at-startup "noctalia"`.
- Niri keybindings call `noctalia msg ...` directly.
- `~/.config/niri/noctalia.kdl` is seeded only when absent.

Noctalia config:

- No `~/.config/noctalia/*.toml` files are seeded.
- The baseline intentionally starts from upstream Noctalia v5 defaults.
- GUI/runtime overrides remain app-managed in `~/.local/state/noctalia/settings.toml`.
- Local verification on the validated `6b39dc8` COPR build showed it starts from an isolated empty XDG config/state/cache profile with `no config files found, using defaults`.
- Upstream defaults are therefore left intact for now, including the default shell font (`sans-serif`), setup wizard behavior, polkit setting, theme, wallpaper, and screenshot settings.

Templates:

- No Noctalia v5 built-in templates are pre-enabled by this repo yet.
- No community templates, v4 plugins, browser theming, QuickShell config, or migration shims are present.

Related managed files:

- `~/Wallpapers`
- `~/.config/niri/cfg/display.kdl`
- `~/.config/niri/noctalia.kdl`
- `~/.config/ghostty/themes/noctalia`

## Repo Wiring

Primary files:

- `bundles/fedora/base/noctalia.bundle`
- `packages/actions/base-noctalia-fedora.actions`
- `modules/35-custom-actions.sh`
- `modules/80-post-actions.sh`
- `modules/90-doctor.sh`
- `config/base-responsibility.tsv`
- `config/managed-config.tsv`
- `dotfiles/niri/.config/niri/cfg/autostart.kdl`
- `dotfiles/niri/.config/niri/cfg/keybinds.kdl`
- `templates/niri/noctalia.kdl`

Tests covering this checkpoint:

- `tests/planner.bats`
- `tests/package_modules.bats`
- `tests/post_actions.bats`
- `tests/doctor_hardening.bats`
- `tests/cli_smoke.bats`

Last validation run:

```bash
bash -n modules/35-custom-actions.sh
bash -n distros/fedora.sh
bats tests/sources_flatpak.bats
```

## Future Update Checklist

When revisiting Noctalia v5:

1. Check current upstream state in `~/repos/noctalia` and docs in `~/repos/noctalia-docs`.
2. Compare changes since the validated COPR commit `6b39dc8` and the previously crashing commits `dfa00a4`/`ad11b4b`.
3. Inspect current Fedora packages from `copr:lionheartp/Hyprland` and Terra, because both may provide `noctalia-git`.
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

5. If the package provider or install path changes, update the custom action/source-forcing strategy accordingly.
6. Re-check v5 docs for renamed config fields, template IDs, IPC commands, package names, source recommendations, and setup wizard behavior.
7. Keep the integration clean v5-only. Do not add v4 compatibility, plugin migration, or QuickShell fallback paths.
8. Update this file with the new checkpoint, package/build decision, VM/manual test result, and validation commands.

## Open Questions

- When Noctalia v5 publishes a stable release, decide whether Fedora should use a versioned stable package instead of `noctalia-git`.
- If this repo stops forcing COPR through the custom action, remove or revise the Terra `noctalia-git` exclude at the same time.
- Treat any future Noctalia config seed, including `setup_wizard_enabled = false`, fonts, polkit, wallpapers, or templates, as an explicit customization checkpoint rather than part of the current vanilla baseline.
