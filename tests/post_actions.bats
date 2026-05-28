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

@test "Noctalia settings seed terminal, wallpaper, and selected template integrations" {
  build_fedora_plan "browser=zen-copr" "dev=vscode,neovim"
  TARGET_HOME="$TEST_ROOT/settings-home"
  mkdir -p "$TARGET_HOME/.config/noctalia" "$TARGET_HOME/.config/Code/User"
  DRY_RUN=0

  update_noctalia_settings

  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"terminalCommand": "ghostty +new-window -e"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"directory": "'"$TARGET_HOME"'/Wallpapers"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"id": "ghostty"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"id": "starship"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"id": "yazi"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"id": "qt"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"id": "kcolorscheme"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"id": "code"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"id": "zenBrowser"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"enableUserTheming": true'
}

@test "Noctalia plugins seed enabled plugin state when absent" {
  build_fedora_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/plugins-home"
  mkdir -p "$TARGET_HOME/.config/noctalia"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_noctalia_plugins_seed_if_missing

  assert_file_contains "$TARGET_HOME/.config/noctalia/plugins.json" '"polkit-agent"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/plugins.json" '"display-settings"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/plugins.json" '"keybind-cheatsheet"'
}

@test "wallpaper state is installed idempotently" {
  TARGET_HOME="$TEST_ROOT/wallpaper-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0

  install_noctalia_wallpaper_state

  local wallpaper_name
  while IFS= read -r wallpaper_name; do
    cmp -s "$ROOT_DIR/assets/wallpapers/$wallpaper_name" "$TARGET_HOME/Wallpapers/$wallpaper_name"
  done < <(find "$ROOT_DIR/assets/wallpapers" -maxdepth 1 -type f -printf '%f\n' | sort)
  assert_file_contains "$TARGET_HOME/.cache/noctalia/wallpapers.json" '"defaultWallpaper": "'"$TARGET_HOME"'/Wallpapers/BlueTide.jpg"'
}

@test "Firefox Pywalfox policy and compatibility symlink are created for Firefox selections" {
  build_fedora_plan "browser=firefox"
  TARGET_HOME="$TEST_ROOT/firefox-home"
  mkdir -p "$TARGET_HOME/.config/mozilla/firefox"
  printf '[Profile0]\nPath=test.default\nIsRelative=1\n' >"$TARGET_HOME/.config/mozilla/firefox/profiles.ini"
  FIREFOX_DISTRIBUTION_DIR="$TEST_ROOT/firefox/distribution"
  DRY_RUN=0

  install_firefox_pywalfox_extension_policy
  jq -e '.policies.ExtensionSettings["pywalfox@frewacom.org"].installation_mode == "normal_installed"' "$FIREFOX_DISTRIBUTION_DIR/policies.json" >/dev/null
  jq -e '.policies.ExtensionSettings["pywalfox@frewacom.org"].install_url == "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"' "$FIREFOX_DISTRIBUTION_DIR/policies.json" >/dev/null

  ensure_firefox_profile_compat_for_pywalfox
  assert_equal "$TARGET_HOME/.config/mozilla/firefox" "$(readlink "$TARGET_HOME/.mozilla/firefox")"
}

@test "first-run creates marker, removes autostart hook, and stays idempotent" {
  build_fedora_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/first-run-home"
  mkdir -p "$TARGET_HOME/.config/noctalia"
  printf '{}\n' >"$TARGET_HOME/.config/noctalia/settings.json"
  DRY_RUN=0
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
  build_fedora_plan "browser=zen-copr" "dev=vscode,neovim"
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/post-actions-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0

  install_zz_launcher() { :; }
  configure_default_applications() { :; }
  patch_noctalia_starship_template_apply_if_needed() { :; }
  install_noctalia_wallpaper_state() { :; }
  install_starship_config() { :; }
  install_niri_noctalia_seed_if_missing() { :; }
  install_noctalia_plugins_seed_if_missing() { :; }
  install_qt_theme_config() { :; }
  configure_flatpak_theme_access() { :; }
  install_pywalfox_native_host() { :; }
  install_vscode_noctalia_extension() { :; }
  register_first_run_hook() { :; }
  write_managed_files_report() { :; }
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  module_80_post_actions

  [[ -f "$TARGET_HOME/.config/noctalia/settings.json" ]]
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"terminalCommand": "ghostty +new-window -e"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"directory": "'"$TARGET_HOME"'/Wallpapers"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"id": "zenBrowser"'
  assert_file_contains "$TARGET_HOME/.config/noctalia/settings.json" '"enableUserTheming": true'
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
