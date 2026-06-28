# Noctalia v5 Integration Status

This is the living checkpoint for the Noctalia v5 integration. Update it every time this repo changes its Noctalia v5 packages, sources, config, Niri wiring, templates, tests, or assumptions.

Noctalia v5 is currently alpha software and this branch is experimental. Treat this file as the handoff note for future work: compare this checkpoint with the then-current Noctalia v5 repo/docs before changing the integration again.

## Checkpoint: 2026-06-28

Repo branch: `noctalia-v5`

Relevant repo commits:

- `71176fc Switch Noctalia integration to v5`
- `081e5f8 Pin Noctalia v5 to working Fedora build`

Reference repos:

- `~/repos/noctalia`
- `~/repos/noctalia-docs`

Current Fedora package state:

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

- Seeded only when absent at `~/.config/noctalia/config.toml`.
- GUI/runtime overrides remain in `~/.local/state/noctalia/settings.toml`.
- The seed includes:
  - `font_family = "JetBrainsMono Nerd Font"`
  - `polkit_agent = true`
  - `telemetry_enabled = false`
  - screenshot defaults through Noctalia v5 IPC
  - wallpaper directory `~/Wallpapers`
  - default wallpaper `~/Wallpapers/BlueTide.jpg`
  - builtin theme `Noctalia`
  - built-in template IDs selected from the install plan

Templates:

- Always enabled when relevant: `niri`, `ghostty`, `starship`, `btop`.
- Full desktop profile also enables: `gtk3`, `gtk4`, `qt`, `kcolorscheme`.
- Community templates are disabled.
- No v4 plugins, browser theming, QuickShell config, or migration shims are present.

Related managed files:

- `~/Wallpapers`
- `~/.config/noctalia/config.toml`
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
bash -n modules/35-custom-actions.sh modules/80-post-actions.sh modules/90-doctor.sh lib/planner.sh lib/readiness.sh distros/fedora.sh
bats tests/planner.bats tests/package_modules.bats tests/post_actions.bats tests/doctor_hardening.bats tests/cli_smoke.bats
./tests/smoke.sh
```

## Future Update Checklist

When revisiting Noctalia v5:

1. Check current upstream state in `~/repos/noctalia` and docs in `~/repos/noctalia-docs`.
2. Compare changes since pinned commit `d2d2f9b` and since crashing commit `dfa00a4`.
3. Inspect current Fedora packages from `copr:lionheartp/Hyprland` and Terra, because both may provide `noctalia-git`.
4. Test the candidate build in a live Niri session with a fresh isolated profile:

   ```bash
   base="$(mktemp -d)"
   mkdir -p "$base/config/noctalia" "$base/state" "$base/cache"
   cp ~/.config/noctalia/config.toml "$base/config/noctalia/config.toml"
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

5. If the new build survives fresh state, remove or update the package pin and versionlock logic.
6. Re-check v5 docs for renamed config fields, template IDs, IPC commands, package names, source recommendations, and setup wizard behavior.
7. Keep the integration clean v5-only. Do not add v4 compatibility, plugin migration, or QuickShell fallback paths.
8. Update this file with the new checkpoint, package/build decision, VM/manual test result, and validation commands.

## Open Questions

- When Noctalia v5 publishes a stable release, decide whether Fedora should use a versioned stable package instead of `noctalia-git`.
- If Terra continues to ship `noctalia-git`, decide whether repo priority/excludes are needed after the pin is removed.
- Revisit whether `setup_wizard_enabled = false` should be seeded for declarative installs once the upstream first-run crash is gone. It is documented as valid for preseeded deployments, but it was not the fix for the crash.
