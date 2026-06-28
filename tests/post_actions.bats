#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
  DISTRO=fedora
  load_adapter
}

@test "default application setup applies MIME defaults and omits guarded handlers" {
  build_fedora_plan
  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$(printf '%q ' "$@")" >>"$TEST_ROOT/commands.log"
  }

  configure_default_applications

  assert_file_contains "$TEST_ROOT/commands.log" "xdg-mime default mpv.desktop video/mp4"
  assert_file_contains "$TEST_ROOT/commands.log" "xdg-mime default mpv.desktop video/x-matroska"
  assert_file_contains "$TEST_ROOT/commands.log" "xdg-mime default nvim.desktop text/plain"
  refute_file_contains "$TEST_ROOT/commands.log" "x-scheme-handler/mailto"
}

@test "minimal desktop app profile skips full desktop MIME defaults but keeps terminal defaults" {
  DESKTOP_APP_PROFILE=minimal
  build_fedora_plan

  run configure_default_applications

  [ "$status" -eq 0 ]
  assert_contains "$output" "xdg-terminals.list"
  refute_contains "$output" "xdg-mime default org.gnome.Nautilus.desktop"
  refute_contains "$output" "xdg-mime default org.gnome.Evince.desktop"
  refute_contains "$output" "xdg-mime default mpv.desktop"
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
  build_fedora_plan
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
  build_fedora_plan "browser=firefox"
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
  build_fedora_plan "browser=firefox,brave"
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

@test "Noctalia v5 config seeds wallpaper, polkit, and built-in templates" {
  build_fedora_plan
  TARGET_HOME="$TEST_ROOT/settings-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0

  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_noctalia_config_if_missing

  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" 'polkit_agent = true'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" 'save_to_file = true'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" 'directory = "'"$TARGET_HOME"'/Wallpapers"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" 'path = "'"$TARGET_HOME"'/Wallpapers/BlueTide.jpg"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" 'builtin = "Noctalia"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" '"niri"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" '"ghostty"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" '"starship"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" '"btop"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" '"gtk3"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" '"gtk4"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" '"qt"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" '"kcolorscheme"'
}

@test "Starship seed includes fallback Noctalia palette" {
  build_fedora_plan
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

  assert_file_contains "$TARGET_HOME/.config/starship.toml" 'palette = "noctalia"'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '# >>> NOCTALIA STARSHIP PALETTE >>>'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '[palettes.noctalia]'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" 'surface0 = "#313244"'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '# <<< NOCTALIA STARSHIP PALETTE <<<'
}

@test "Starship rerun repairs existing Noctalia palette reference" {
  build_fedora_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/starship-existing-home"
  mkdir -p "$TARGET_HOME/.config"
  printf 'palette = "noctalia"\nformat = "$character"\n' >"$TARGET_HOME/.config/starship.toml"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_starship_config

  assert_file_contains "$TARGET_HOME/.config/starship.toml" 'format = "$character"'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '# >>> NOCTALIA STARSHIP PALETTE >>>'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '[palettes.noctalia]'
}

@test "Ghostty theme seed provides valid Noctalia theme when absent" {
  build_fedora_plan
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

  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/noctalia" 'palette = 0=#11111b'
  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/noctalia" 'background = #1e1e2e'
  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/noctalia" 'selection-foreground = #cdd6f4'
}

@test "Ghostty theme seed preserves existing Noctalia theme" {
  build_fedora_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/ghostty-existing-theme-home"
  mkdir -p "$TARGET_HOME/.config/ghostty/themes"
  printf 'background = #000000\n' >"$TARGET_HOME/.config/ghostty/themes/noctalia"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_ghostty_theme_seed_if_missing

  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/noctalia" 'background = #000000'
  refute_file_contains "$TARGET_HOME/.config/ghostty/themes/noctalia" 'palette = 0=#11111b'
}

@test "Noctalia v5 config seed preserves existing config" {
  build_fedora_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/plugins-home"
  mkdir -p "$TARGET_HOME/.config/noctalia"
  printf '[theme]\nbuiltin = "Custom"\n' >"$TARGET_HOME/.config/noctalia/config.toml"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_noctalia_config_if_missing

  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" 'builtin = "Custom"'
}

@test "Niri display config is seeded only when absent" {
  build_fedora_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/niri-display-home"
  mkdir -p "$TARGET_HOME/.config/niri/cfg"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_niri_display_seed_if_missing

  assert_file_contains "$TARGET_HOME/.config/niri/cfg/display.kdl" 'output "DP-1"'

  printf 'custom display\n' >"$TARGET_HOME/.config/niri/cfg/display.kdl"
  install_niri_display_seed_if_missing

  assert_file_contains "$TARGET_HOME/.config/niri/cfg/display.kdl" "custom display"
}

@test "bundled wallpapers are installed idempotently" {
  TARGET_HOME="$TEST_ROOT/wallpaper-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0

  install_bundled_wallpapers

  local wallpaper_name
  while IFS= read -r wallpaper_name; do
    cmp -s "$ROOT_DIR/assets/wallpapers/$wallpaper_name" "$TARGET_HOME/Wallpapers/$wallpaper_name"
  done < <(find "$ROOT_DIR/assets/wallpapers" -maxdepth 1 -type f -printf '%f\n' | sort)
}

@test "first-run creates marker, removes autostart hook, and stays idempotent" {
  build_fedora_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/first-run-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  install_noctalia_config_if_missing() { :; }
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/first-run-commands.log"
    case "$1" in
      mkdir|rm|sh)
        "$@"
        ;;
      *)
        return 0
        ;;
    esac
  }

  register_first_run_hook
  assert_file_contains "$TARGET_HOME/.config/autostart/zz-first-run.desktop" "Exec=$TARGET_HOME/.local/bin/zz first-run"

  module_80_first_run
  [[ -f "$(first_run_marker)" ]]
  [[ ! -e "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "systemctl --user daemon-reload"
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "systemctl --user enable --now app-com.mitchellh.ghostty.service"

  : >"$TEST_ROOT/first-run-commands.log"
  module_80_first_run
  [[ ! -s "$TEST_ROOT/first-run-commands.log" ]]
}

@test "post-actions seed Noctalia settings before first-run hook" {
  build_fedora_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/post-actions-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0

  install_zz_launcher() { :; }
  configure_default_applications() { :; }
  install_bundled_wallpapers() { :; }
  install_starship_config() { :; }
  install_ghostty_theme_seed_if_missing() { :; }
  install_niri_noctalia_seed_if_missing() { :; }
  install_qt_theme_config() { :; }
  configure_flatpak_theme_access() { :; }
  register_first_run_hook() { :; }
  write_managed_files_report() { :; }
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  module_80_post_actions

  [[ -f "$TARGET_HOME/.config/noctalia/config.toml" ]]
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" 'polkit_agent = true'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" 'save_to_file = true'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" 'directory = "'"$TARGET_HOME"'/Wallpapers"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/config.toml" '"ghostty"'
}

@test "Flatpak theme access override is applied as user override" {
  build_fedora_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/flatpak-theme-home"
  DRY_RUN=0
  fake_bin="$TEST_ROOT/flatpak-theme-bin"
  command_log="$TEST_ROOT/flatpak-theme-commands.log"
  mkdir -p "$TARGET_HOME" "$fake_bin"

  cat >"$fake_bin/flatpak" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$FLATPAK_COMMAND_LOG"
EOF
  chmod +x "$fake_bin/flatpak"
  PATH="$fake_bin:$PATH"
  export FLATPAK_COMMAND_LOG="$command_log"

  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$command_log"
    "$@"
  }

  configure_flatpak_theme_access

  assert_file_contains "$command_log" "user:test-user:flatpak override --user"
  assert_file_contains "$command_log" "--filesystem=xdg-config/gtk-3.0:ro"
  assert_file_contains "$command_log" "--filesystem=xdg-config/gtk-4.0:ro"
  assert_file_contains "$command_log" "--filesystem=xdg-config/qt5ct:ro"
  assert_file_contains "$command_log" "--filesystem=xdg-config/qt6ct:ro"
  assert_file_contains "$command_log" "--filesystem=xdg-config/kdeglobals:ro"
  assert_file_contains "$command_log" "--filesystem=xdg-data/color-schemes:ro"
}
