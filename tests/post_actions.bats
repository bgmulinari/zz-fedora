#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "skip user config preserves target-user files during post-actions" {
  build_test_plan
  SKIP_USER_CONFIG=1
  DRY_RUN=0
  mkdir -p "$TARGET_HOME/.config/niri" "$TARGET_HOME/.config/ghostty"
  printf 'personal niri\n' >"$TARGET_HOME/.config/niri/config.kdl"
  printf 'personal ghostty\n' >"$TARGET_HOME/.config/ghostty/config"

  run module_80_post_actions

  [ "$status" -eq 0 ]
  assert_contains "$output" "Skipping target-user configuration, assets, defaults, and services"
  assert_equal "personal niri" "$(cat "$TARGET_HOME/.config/niri/config.kdl")"
  assert_equal "personal ghostty" "$(cat "$TARGET_HOME/.config/ghostty/config")"
}

@test "post-actions registers the first-run hook and report before any failable seed" {
  for fn in install_zz_launcher configure_default_applications \
    install_bundled_wallpapers install_starship_config \
    install_ghostty_theme_seed_if_missing \
    install_niri_dms_colors_seed_if_missing install_niri_dms_binds_seed_if_missing \
    configure_flatpak_theme_access \
    enable_user_services register_first_run_hook write_managed_files_report \
    install_dms_state_seeds_if_missing; do
    eval "$fn() { printf '$fn\n' >>'$TEST_ROOT/order.log'; }"
  done
  install_qt_theme_config() {
    printf 'install_qt_theme_config\n' >>"$TEST_ROOT/order.log"
    die "Could not back up example before replacing it"
  }

  run module_80_post_actions

  [ "$status" -ne 0 ]
  assert_file_line "$TEST_ROOT/order.log" "register_first_run_hook"
  assert_file_line "$TEST_ROOT/order.log" "write_managed_files_report"
  hook_line="$(grep -n '^register_first_run_hook$' "$TEST_ROOT/order.log" | cut -d: -f1)"
  seed_line="$(grep -n '^install_qt_theme_config$' "$TEST_ROOT/order.log" | cut -d: -f1)"
  [ "$hook_line" -lt "$seed_line" ]
  # The DMS state seeds are a first-login correctness guarantee: they
  # must land before any failable seed can cut the step short.
  dms_seed_line="$(grep -n '^install_dms_state_seeds_if_missing$' "$TEST_ROOT/order.log" | cut -d: -f1)"
  first_failable_line="$(grep -n '^configure_default_applications$' "$TEST_ROOT/order.log" | cut -d: -f1)"
  [ "$dms_seed_line" -lt "$first_failable_line" ]
  # The die really cut the step short: nothing after the failing seed ran.
  refute_file_line "$TEST_ROOT/order.log" "configure_flatpak_theme_access"
  refute_file_line "$TEST_ROOT/order.log" "enable_user_services"
}

@test "default application setup applies selected MIME defaults" {
  build_test_plan "desktop=audio-player,text-editor,video-player"
  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$(printf '%q ' "$@")" >>"$TEST_ROOT/commands.log"
  }

  run_without_bats_debug_trap configure_default_applications

  assert_file_contains "$TEST_ROOT/commands.log" "xdg-mime default org.gnome.Showtime.desktop video/mp4"
  assert_file_contains "$TEST_ROOT/commands.log" "xdg-mime default org.gnome.Showtime.desktop video/x-matroska"
  assert_file_contains "$TEST_ROOT/commands.log" "xdg-mime default org.gnome.Decibels.desktop audio/mpeg"
  assert_file_contains "$TEST_ROOT/commands.log" "xdg-mime default org.gnome.TextEditor.desktop text/plain"
  assert_file_contains "$TEST_ROOT/commands.log" "xdg-mime default org.gnome.Nautilus.desktop application/zip"
}

@test "update mode reapplies MIME defaults only for packages that remain installed" {
  build_test_plan "desktop=audio-player"
  UPDATE_MODE=1
  DRY_RUN=0
  fedora_package_installed() {
    [[ "$1" == "nautilus" ]]
  }
  have_cmd() {
    return 1
  }
  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$(printf '%q ' "$@")" >>"$TEST_ROOT/commands.log"
  }

  run_without_bats_debug_trap configure_default_applications_from_tsv

  assert_file_contains "$TEST_ROOT/commands.log" "xdg-mime default org.gnome.Nautilus.desktop application/zip"
  refute_file_contains "$TEST_ROOT/commands.log" "org.gnome.Decibels.desktop"
}

@test "minimal desktop app profile skips full desktop MIME defaults but keeps terminal defaults" {
  DESKTOP_APP_PROFILE=minimal
  build_test_plan

  run configure_default_applications

  [ "$status" -eq 0 ]
  assert_contains "$output" "xdg-terminals.list"
  refute_contains "$output" "xdg-mime default org.gnome.Nautilus.desktop"
  refute_contains "$output" "xdg-mime default org.gnome.Papers.desktop"
  refute_contains "$output" "xdg-mime default org.gnome.Showtime.desktop"
}

@test "selected browser default falls back to MIME when xdg-settings fails" {
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*"
    [[ "$1" == "xdg-settings" ]] && return 1
    return 0
  }
  TARGET_USER=test-user

  run set_default_browser firefox.desktop

  [ "$status" -eq 0 ]
  assert_contains "$output" "user:test-user:xdg-mime default firefox.desktop text/html"
  assert_contains "$output" "user:test-user:xdg-mime default firefox.desktop x-scheme-handler/http"
  assert_contains "$output" "user:test-user:xdg-mime default firefox.desktop x-scheme-handler/https"
  refute_contains "$output" "Could not set default browser"
}

@test "selected browser default is skipped when no browser was selected" {
  set_category_override browsers ""
  PREFERRED_BROWSER=""
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/browser-default-commands.log"
  }

  configure_selected_browser_default

  [[ ! -e "$TEST_ROOT/browser-default-commands.log" ]]
}

@test "single selected browser becomes the default browser" {
  set_category_override browsers "firefox"
  PREFERRED_BROWSER=""
  TARGET_USER=test-user
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/browser-default-commands.log"
  }

  configure_selected_browser_default

  assert_file_contains "$TEST_ROOT/browser-default-commands.log" "user:test-user:xdg-mime default firefox.desktop text/html"
  assert_file_contains "$TEST_ROOT/browser-default-commands.log" "user:test-user:xdg-settings set default-web-browser firefox.desktop"
}

@test "preferred browser controls default when multiple browsers are selected" {
  set_category_override browsers "firefox,brave"
  PREFERRED_BROWSER="brave"
  TARGET_USER=test-user
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/browser-default-commands.log"
  }

  configure_selected_browser_default

  assert_file_contains "$TEST_ROOT/browser-default-commands.log" "user:test-user:xdg-mime default brave-browser.desktop text/html"
  refute_file_contains "$TEST_ROOT/browser-default-commands.log" "firefox.desktop"
}

@test "update mode preserves browser defaults when the saved browser was removed" {
  set_category_override browsers "firefox"
  PREFERRED_BROWSER=""
  UPDATE_MODE=1
  DRY_RUN=0
  TARGET_USER=test-user
  TARGET_HOME="$TEST_ROOT/browser-home"
  mkdir -p "$TARGET_HOME"
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/browser-default-commands.log"
  }

  run configure_selected_browser_default

  [ "$status" -eq 0 ]
  assert_contains "$output" "saved browser is not installed: firefox.desktop"
  [[ ! -e "$TEST_ROOT/browser-default-commands.log" ]]
}

@test "Starship seed includes fallback ZZ palette" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/starship-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_starship_config

  assert_file_contains "$TARGET_HOME/.config/starship.toml" 'palette = "zz"'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '# >>> ZZ STARSHIP PALETTE >>>'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '[palettes.zz]'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" 'surface0 = "#313244"'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '# <<< ZZ STARSHIP PALETTE <<<'
}

@test "Starship rerun repairs existing ZZ palette reference" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/starship-existing-home"
  mkdir -p "$TARGET_HOME/.config"
  printf 'palette = "zz"\nformat = "$character"\n' >"$TARGET_HOME/.config/starship.toml"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_starship_config

  assert_file_contains "$TARGET_HOME/.config/starship.toml" 'format = "$character"'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '# >>> ZZ STARSHIP PALETTE >>>'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '[palettes.zz]'
}

@test "Ghostty theme seed provides a valid fallback theme when absent" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/ghostty-theme-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_ghostty_theme_seed_if_missing

  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/dankcolors" 'palette = 0=#11111b'
  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/dankcolors" 'background = #1e1e2e'
  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/dankcolors" 'selection-foreground = #cdd6f4'
}

@test "Ghostty theme seed preserves an existing user theme" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/ghostty-existing-theme-home"
  mkdir -p "$TARGET_HOME/.config/ghostty/themes"
  printf 'background = #000000\n' >"$TARGET_HOME/.config/ghostty/themes/dankcolors"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_ghostty_theme_seed_if_missing

  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/dankcolors" 'background = #000000'
  refute_file_contains "$TARGET_HOME/.config/ghostty/themes/dankcolors" 'palette = 0=#11111b'
}

@test "Niri keybinds seed lands in the only fragment the DMS UI reads" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/niri-binds-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_niri_dms_binds_seed_if_missing

  local binds="$TARGET_HOME/.config/niri/dms/binds.kdl"
  assert_file_contains "$binds" 'dms ipc call spotlight toggle'
  assert_file_contains "$binds" 'spawn "ghostty" "+new-window"'
  assert_file_contains "$binds" 'spawn "nautilus" "--new-window"'
  # Attributes DMS round-trips through its Settings UI.
  assert_file_contains "$binds" 'allow-when-locked=true'
  assert_file_contains "$binds" 'cooldown-ms=150'
  assert_file_contains "$binds" 'allow-inhibiting=false'
}

@test "Niri keybinds seed preserves binds the user changed in the DMS UI" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/niri-binds-existing-home"
  mkdir -p "$TARGET_HOME/.config/niri/dms"
  printf 'binds {\n    Mod+Return { spawn "kitty"; }\n}\n' \
    >"$TARGET_HOME/.config/niri/dms/binds.kdl"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_niri_dms_binds_seed_if_missing

  assert_file_contains "$TARGET_HOME/.config/niri/dms/binds.kdl" 'spawn "kitty"'
  refute_file_contains "$TARGET_HOME/.config/niri/dms/binds.kdl" 'dms ipc call spotlight toggle'
}

@test "product Niri tree ships no binds so the DMS UI is the single keybind surface" {
  # DMS parses only ~/.config/niri/dms/binds.kdl. A binds block anywhere in the
  # product tree would be invisible to Settings -> Keybinds and would collide
  # with the seeded fragment, so this placement is a contract, not a detail.
  if grep -rl 'binds {' "$ROOT_DIR/dotfiles/niri" >"$TEST_ROOT/product-binds.txt" 2>&1; then
    printf 'binds blocks found in the product Niri tree:\n' >&2
    cat "$TEST_ROOT/product-binds.txt" >&2
    return 1
  fi
  assert_file_contains "$ROOT_DIR/templates/niri/dms-binds.kdl" 'binds {'
  refute_file_contains "$ROOT_DIR/dotfiles/niri/.config/niri/defaults.kdl" 'keybinds.kdl'
}

@test "Niri entrypoint includes every DMS fragment in the form DMS detects" {
  local config="$ROOT_DIR/dotfiles/niri/.config/niri/config.kdl"
  # KeybindsService matches the literal pattern include.*"dms/binds.kdl", so a
  # "./dms/..." path fails detection and makes DMS rewrite the user entrypoint.
  assert_file_contains "$config" 'include optional=true "dms/binds.kdl"'
  refute_file_contains "$config" '"./dms/'
  local fragment
  for fragment in layout alttab binds cursor outputs windowrules wpblur; do
    assert_file_contains "$config" "include optional=true \"dms/${fragment}.kdl\""
  done
  assert_file_contains "$config" 'include "dms/colors.kdl"'
  # DMS has no writer for input.kdl; the include resolved to nothing.
  refute_file_contains "$config" 'dms/input.kdl'
}

@test "DMS state seeds select the managed theme and wallpaper before first login" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/dms-seed-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_dms_state_seeds_if_missing
  # Repeated runs must not disturb the seeded state.
  install_dms_state_seeds_if_missing

  local settings="$TARGET_HOME/.config/DankMaterialShell/settings.json"
  local session="$TARGET_HOME/.local/state/DankMaterialShell/session.json"
  assert_equal "registry" "$(jq -r '.currentThemeCategory' "$settings")"
  assert_equal "custom" "$(jq -r '.currentThemeName' "$settings")"
  assert_equal "$TARGET_HOME/.config/DankMaterialShell/themes/catppuccin/theme.json" \
    "$(jq -r '.customThemeFile' "$settings")"
  assert_equal "mocha" "$(jq -r '.registryThemeVariants.catppuccin.dark.flavor' "$settings")"
  assert_equal "blue" "$(jq -r '.registryThemeVariants.catppuccin.dark.accent' "$settings")"
  assert_equal "latte" "$(jq -r '.registryThemeVariants.catppuccin.light.flavor' "$settings")"
  assert_equal "JetBrainsMono Nerd Font" "$(jq -r '.monoFontFamily' "$settings")"
  assert_equal "Yaru-blue" "$(jq -r '.iconThemeDark' "$settings")"
  assert_equal "$TARGET_HOME/.local/share/backgrounds/CraterBlue.jpg" \
    "$(jq -r '.wallpaperPath' "$session")"
  assert_equal "false" "$(jq -r '.isLightMode' "$session")"
  # The colors placeholder keeps the greeter cache symlink from dangling.
  assert_equal "{}" "$(jq -c '.' "$TARGET_HOME/.cache/DankMaterialShell/dms-colors.json")"
}

@test "DMS state seeds preserve existing user state" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/dms-seed-existing-home"
  mkdir -p "$TARGET_HOME/.config/DankMaterialShell" "$TARGET_HOME/.local/state/DankMaterialShell"
  printf '{"currentThemeName":"user-picked"}\n' >"$TARGET_HOME/.config/DankMaterialShell/settings.json"
  printf '{"wallpaperPath":"/tmp/user-picked.jpg"}\n' >"$TARGET_HOME/.local/state/DankMaterialShell/session.json"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_dms_state_seeds_if_missing

  assert_equal "user-picked" "$(jq -r '.currentThemeName' "$TARGET_HOME/.config/DankMaterialShell/settings.json")"
  assert_equal "/tmp/user-picked.jpg" "$(jq -r '.wallpaperPath' "$TARGET_HOME/.local/state/DankMaterialShell/session.json")"
}

@test "DMS state seeds are skipped with --skip-user-config" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/dms-seed-skip-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  SKIP_USER_CONFIG=1
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_dms_state_seeds_if_missing

  [ ! -e "$TARGET_HOME/.config/DankMaterialShell/settings.json" ]
  [ ! -e "$TARGET_HOME/.local/state/DankMaterialShell/session.json" ]
}

@test "qt6ct config uses the DMS KColorScheme" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/qtct-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_qt6ct_config

  assert_file_contains "$TARGET_HOME/.config/qt6ct/qt6ct.conf" "color_scheme_path=$TARGET_HOME/.local/share/color-schemes/DankMatugen.colors"
  assert_file_contains "$TARGET_HOME/.config/qt6ct/qt6ct.conf" "icon_theme=Yaru-blue"
}

@test "bundled wallpapers are seeded without replacing user files" {
  TARGET_HOME="$TEST_ROOT/wallpaper-home"
  DRY_RUN=0
  mkdir -p "$TARGET_HOME/.local/share/backgrounds"
  printf 'user-selected image\n' >"$TARGET_HOME/.local/share/backgrounds/SilentPeaks.jpg"

  install_bundled_wallpapers

  assert_equal "user-selected image" "$(cat "$TARGET_HOME/.local/share/backgrounds/SilentPeaks.jpg")"
  [[ "$(find "$TARGET_HOME/.local/share/backgrounds" -maxdepth 1 -type f -name '*.jpg' | wc -l)" -eq 16 ]]
  cmp -s "$ROOT_DIR/assets/wallpapers/PROVENANCE.md" "$TARGET_HOME/.local/share/backgrounds/PROVENANCE.md"

  local wallpaper_name
  while IFS= read -r wallpaper_name; do
    [[ "$wallpaper_name" == "SilentPeaks.jpg" ]] && continue
    cmp -s "$ROOT_DIR/assets/wallpapers/$wallpaper_name" "$TARGET_HOME/.local/share/backgrounds/$wallpaper_name"
  done < <(find "$ROOT_DIR/assets/wallpapers" -maxdepth 1 -type f -name '*.jpg' -printf '%f\n' | sort)

  install_bundled_wallpapers
  [[ "$(find "$TARGET_HOME/.local/share/backgrounds" -maxdepth 1 -type f -name '*.jpg' | wc -l)" -eq 16 ]]
}

@test "first-run creates marker, removes autostart hook, and stays idempotent" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/first-run-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  stub_dms_shell_payload
  setup_fake_bin
  write_fake_command dms-greeter <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--help" ]] && printf 'Commands:\n  sync    Sync greeter profile data\n'
exit 0
EOF
  PATH="$FAKE_BIN:$PATH"
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/first-run-commands.log"
    if [[ "$*" == "dms ipc call wallpaper get" ]]; then
      stub_dms_theme_artifacts
      return 0
    fi
    if [[ "$*" == "dms-greeter sync --profile" ]]; then
      return 0
    fi
    case "$1" in
      mkdir|rm|sh|install|cp)
        "$@"
        ;;
      *)
        return 0
        ;;
    esac
  }

  register_first_run_hook
  assert_file_contains "$TARGET_HOME/.config/autostart/zz-first-run.desktop" \
    "Exec=$TARGET_HOME/.local/bin/zz first-run --use-saved"

  run_without_bats_debug_trap module_85_first_run
  [[ -f "$(first_run_marker)" ]]
  [[ ! -e "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]
  [[ -f "$(first_run_action_marker session-services)" ]]
  [[ -f "$(first_run_action_marker user-directories)" ]]
  [[ -f "$(first_run_action_marker desktop-interface)" ]]
  [[ -f "$(first_run_action_marker desktop-defaults)" ]]
  [[ -f "$(first_run_action_marker dms-theme)" ]]
  [[ -f "$(first_run_action_marker dms-greeter-profile)" ]]
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "systemctl --user daemon-reload"
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "systemctl --user enable --now app-com.mitchellh.ghostty.service"
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "systemctl --user add-wants niri.service dms.service"
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "systemctl --user start dms.service"
  refute_file_contains "$TEST_ROOT/first-run-commands.log" "systemctl --user enable --now dms.service"
  assert_file_contains "$TEST_ROOT/first-run-commands.log" \
    "gsettings set org.gnome.desktop.interface cursor-theme $(desktop_cursor_theme_name)"
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "gsettings set org.gnome.desktop.interface cursor-size 24"
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "dms ipc call wallpaper get"
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "dms-greeter sync --profile"

  : >"$TEST_ROOT/first-run-commands.log"
  run_without_bats_debug_trap module_85_first_run
  [[ ! -s "$TEST_ROOT/first-run-commands.log" ]]
}

@test "first-run hook restores saved selection inputs in a fresh process" {
  build_test_plan "browser=firefox,brave"
  PREFERRED_BROWSER=brave
  DRY_RUN=0
  save_selections
  register_first_run_hook

  run bash -c '
    set -Eeuo pipefail
    root_dir="$1"
    source "$root_dir/lib/common.sh"
    source "$root_dir/lib/cli.sh"
    parse_cli first-run --use-saved
    [[ "$USE_SAVED_SELECTIONS" -eq 1 ]]
    load_saved_selections
    printf "preferred=%s\n" "$PREFERRED_BROWSER"
    effective_choice_ids browsers
  ' _ "$ROOT_DIR"

  [ "$status" -eq 0 ]
  assert_contains "$output" "preferred=brave"
  assert_contains "$output" "firefox"
  assert_contains "$output" "brave"
}

@test "first-run waits for the DMS shell before checking generated theme artifacts" {
  build_test_plan
  TARGET_USER="theme-user"
  TARGET_HOME="$TEST_ROOT/dms-theme-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  command_log="$TEST_ROOT/dms-theme-commands.log"
  readiness_attempts=0
  sleep() { :; }

  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$*" >>"$command_log"
    if [[ "$*" == "dms ipc call wallpaper get" ]]; then
      readiness_attempts=$((readiness_attempts + 1))
      if [[ "$readiness_attempts" -ge 3 ]]; then
        stub_dms_theme_artifacts
        return 0
      fi
      return 1
    fi
    return 0
  }

  apply_dms_theme

  assert_equal "3" "$readiness_attempts"
  [ -s "$TARGET_HOME/.config/ghostty/themes/dankcolors" ]
  [ -s "$TARGET_HOME/.local/share/color-schemes/DankMatugen.colors" ]
  assert_file_line "$command_log" "theme-user:dms ipc call wallpaper get"
}

@test "first-run theme checkpoint retries at next login when artifacts never appear" {
  build_test_plan
  TARGET_USER="theme-user"
  TARGET_HOME="$TEST_ROOT/dms-theme-timeout-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  sleep() { :; }

  run_cmd_as_user() {
    local user="$1"
    shift
    # The shell answers IPC but never generates the theme artifacts.
    [[ "$*" == "dms ipc call wallpaper get" ]]
  }

  local output status
  capture_without_bats_debug_trap output status apply_dms_theme

  [ "$status" -ne 0 ]
  assert_contains "$output" "DMS did not finish generating theme files"
  # The failed login is counted so a persistent failure can stop retrying.
  assert_equal "1" "$(first_run_action_attempt_count dms-theme)"
}

@test "first-run theme wait does not accept the seeded Ghostty fallback as generated" {
  build_test_plan
  TARGET_USER="theme-user"
  TARGET_HOME="$TEST_ROOT/dms-theme-seeded-home"
  mkdir -p "$TARGET_HOME/.config/ghostty/themes" "$TARGET_HOME/.local/share/color-schemes"
  # The pre-first-run seed occupies the exact path DMS later overwrites;
  # bare existence must not satisfy the generation gate.
  cp "$ROOT_DIR/templates/ghostty/dankcolors" "$TARGET_HOME/.config/ghostty/themes/dankcolors"
  printf '[General]\nColorScheme=DankMatugen\n' >"$TARGET_HOME/.local/share/color-schemes/DankMatugen.colors"
  DRY_RUN=0
  sleep() { :; }

  run_cmd_as_user() {
    local user="$1"
    shift
    [[ "$*" == "dms ipc call wallpaper get" ]]
  }

  local output status
  capture_without_bats_debug_trap output status apply_dms_theme

  [ "$status" -ne 0 ]
  assert_contains "$output" "DMS did not finish generating theme files"

  # Once the artifact content diverges from the seed, the wait completes.
  printf 'palette = 0=#11111b\n' >"$TARGET_HOME/.config/ghostty/themes/dankcolors"
  capture_without_bats_debug_trap output status apply_dms_theme
  [ "$status" -eq 0 ]
  assert_equal "0" "$(first_run_action_attempt_count dms-theme)"
}

@test "first-run theme wait gives up after repeated failed logins" {
  build_test_plan
  TARGET_USER="theme-user"
  TARGET_HOME="$TEST_ROOT/dms-theme-give-up-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  command_log="$TEST_ROOT/dms-theme-give-up-commands.log"
  first_run_record_action_attempt dms-theme
  first_run_record_action_attempt dms-theme
  first_run_record_action_attempt dms-theme

  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$*" >>"$command_log"
    return 1
  }

  local output status
  capture_without_bats_debug_trap output status apply_dms_theme

  # After the retry budget the login stops paying the wait and the
  # checkpoint completes; the doctor checks surface the missing artifacts.
  [ "$status" -eq 0 ]
  assert_contains "$output" "did not complete after 3 logins"
  [[ ! -e "$command_log" ]]
}

@test "first-run applies the GTK color baseline through the shell's own applier" {
  build_test_plan
  TARGET_USER="theme-user"
  TARGET_HOME="$TEST_ROOT/dms-gtk-home"
  DRY_RUN=0
  command_log="$TEST_ROOT/dms-gtk-commands.log"

  local payload_dir="$TEST_ROOT/dms-shell-payload"
  mkdir -p "$TARGET_HOME/.config/gtk-4.0"
  stub_dms_shell_payload

  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$*" >>"$command_log"
  }

  # Before the shell generates the GTK colors, the baseline retries.
  local output status
  capture_without_bats_debug_trap output status apply_dms_gtk_baseline
  [ "$status" -ne 0 ]
  assert_contains "$output" "has not generated the GTK colors yet"

  printf '@define-color accent #89b4fa;\n' >"$TARGET_HOME/.config/gtk-4.0/dank-colors.css"
  apply_dms_gtk_baseline

  assert_file_contains "$command_log" \
    "theme-user:bash $payload_dir/scripts/gtk.sh $TARGET_HOME/.config apply false $payload_dir"
}

@test "first-run greeter profile sync completes when the installed CLI cannot sync" {
  build_test_plan
  TARGET_USER="theme-user"
  DRY_RUN=0
  command_log="$TEST_ROOT/dms-greeter-nosync-commands.log"
  # The stable-channel dms-greeter is only the launcher: no sync command.
  setup_fake_bin
  write_fake_command dms-greeter <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "--help" ]] && printf 'Usage: dms-greeter --command COMPOSITOR [OPTIONS]\n'
exit 0
EOF
  PATH="$FAKE_BIN:$PATH"

  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$*" >>"$command_log"
  }

  apply_dms_greeter_profile_sync

  [[ ! -e "$command_log" ]]
}

@test "first-run greeter profile sync is skipped when the greeter action was skipped" {
  build_test_plan
  TARGET_USER="theme-user"
  DRY_RUN=0
  command_log="$TEST_ROOT/dms-greeter-profile-commands.log"
  record_system_skip action dms-greeter "existing display manager: gdm.service"

  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$*" >>"$command_log"
  }

  apply_dms_greeter_profile_sync

  [[ ! -e "$command_log" ]]
}

@test "managed Zed settings select the DMS theme variants" {
  local settings_file="$ROOT_DIR/dotfiles/zed/.config/zed/settings.json"

  assert_file_contains "$settings_file" '"light": "DankShell Light"'
  assert_file_contains "$settings_file" '"dark": "DankShell Dark"'
}

@test "Flatpak theme access override is applied as user override" {
  build_test_plan
  setup_fake_bin
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/flatpak-theme-home"
  DRY_RUN=0
  mkdir -p "$TARGET_HOME"

  write_fake_command flatpak <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$FLATPAK_COMMAND_LOG"
EOF
  PATH="$FAKE_BIN:$PATH"
  export FLATPAK_COMMAND_LOG="$COMMAND_LOG"

  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$COMMAND_LOG"
    "$@"
  }

  configure_flatpak_theme_access

  assert_file_contains "$COMMAND_LOG" "user:test-user:flatpak override --user"
  assert_file_contains "$COMMAND_LOG" "--filesystem=xdg-config/gtk-3.0:ro"
  assert_file_contains "$COMMAND_LOG" "--filesystem=xdg-config/gtk-4.0:ro"
  assert_file_contains "$COMMAND_LOG" "--filesystem=xdg-config/qt6ct:ro"
  assert_file_contains "$COMMAND_LOG" "--filesystem=xdg-config/kdeglobals:ro"
  assert_file_contains "$COMMAND_LOG" "--filesystem=xdg-data/color-schemes:ro"
}
