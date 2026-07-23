#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "post-actions registers the first-run hook and report before any failable seed" {
  for fn in install_zz_launcher configure_default_applications \
    install_bundled_wallpapers install_starship_config \
    install_ghostty_theme_seed_if_missing install_niri_display_seed_if_missing \
    install_niri_noctalia_seed_if_missing configure_flatpak_theme_access \
    enable_user_services register_first_run_hook write_managed_files_report \
    install_noctalia_state_seeds_if_missing; do
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
  # The Noctalia state seeds are a first-login correctness guarantee: they
  # must land before any failable seed can cut the step short.
  noctalia_seed_line="$(grep -n '^install_noctalia_state_seeds_if_missing$' "$TEST_ROOT/order.log" | cut -d: -f1)"
  first_failable_line="$(grep -n '^configure_default_applications$' "$TEST_ROOT/order.log" | cut -d: -f1)"
  [ "$noctalia_seed_line" -lt "$first_failable_line" ]
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

@test "Starship seed includes fallback Noctalia palette" {
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

  assert_file_contains "$TARGET_HOME/.config/starship.toml" 'palette = "noctalia"'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '# >>> NOCTALIA STARSHIP PALETTE >>>'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '[palettes.noctalia]'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" 'surface0 = "#313244"'
  assert_file_contains "$TARGET_HOME/.config/starship.toml" '# <<< NOCTALIA STARSHIP PALETTE <<<'
}

@test "Starship rerun repairs existing Noctalia palette reference" {
  build_test_plan
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

  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/noctalia" 'palette = 0=#11111b'
  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/noctalia" 'background = #1e1e2e'
  assert_file_contains "$TARGET_HOME/.config/ghostty/themes/noctalia" 'selection-foreground = #cdd6f4'
}

@test "Ghostty theme seed preserves existing Noctalia theme" {
  build_test_plan
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

@test "Noctalia state seeds mark first-run setup complete before first login" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/noctalia-marker-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_noctalia_state_seeds_if_missing
  # Repeated runs must not disturb the seeded state.
  install_noctalia_state_seeds_if_missing

  [ -f "$TARGET_HOME/.local/state/noctalia/.setup-complete" ]
  assert_file_contains "$TARGET_HOME/.local/state/noctalia/settings.toml" 'config_version = 2'
  # The sidecar carries the managed default wallpaper so sidecar migrations
  # (including future config_version bumps) cannot drop it.
  assert_file_contains "$TARGET_HOME/.local/state/noctalia/settings.toml" '[wallpaper.default]'
  assert_file_contains "$TARGET_HOME/.local/state/noctalia/settings.toml" 'path = "~/.local/share/backgrounds/Alpenglow.jpg"'
}

@test "Noctalia state seeds preserve existing user state" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/noctalia-marker-existing-home"
  mkdir -p "$TARGET_HOME/.local/state/noctalia"
  printf 'user-owned\n' >"$TARGET_HOME/.local/state/noctalia/.setup-complete"
  printf 'config_version = 2\n\n[wallpaper.default]\npath = "/tmp/user-picked.jpg"\n' >"$TARGET_HOME/.local/state/noctalia/settings.toml"
  DRY_RUN=0
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_noctalia_state_seeds_if_missing

  assert_file_contains "$TARGET_HOME/.local/state/noctalia/.setup-complete" 'user-owned'
  assert_file_contains "$TARGET_HOME/.local/state/noctalia/settings.toml" 'user-picked.jpg'
}

@test "Noctalia state seeds are skipped with --skip-dotfiles" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/noctalia-marker-skip-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  SKIP_DOTFILES=1
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_noctalia_state_seeds_if_missing

  [ ! -e "$TARGET_HOME/.local/state/noctalia/.setup-complete" ]
  [ ! -e "$TARGET_HOME/.local/state/noctalia/settings.toml" ]
}

@test "managed Noctalia config disables the built-in setup wizard" {
  grep -Eq '^setup_wizard_enabled = false$' "$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml"
}

@test "qt6ct config uses Noctalia KColorScheme" {
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

  assert_file_contains "$TARGET_HOME/.config/qt6ct/qt6ct.conf" "color_scheme_path=$TARGET_HOME/.local/share/color-schemes/noctalia.colors"
}

@test "managed Noctalia templates use KColorScheme without Qt palette output" {
  config="$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml"

  run python3 - "$config" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)

builtin_ids = config["theme"]["templates"]["builtin_ids"]
assert "kcolorscheme" in builtin_ids
assert "qt" not in builtin_ids
PY

  [ "$status" -eq 0 ]
}

@test "managed Ghostty template waits for activation and reloads through systemd" {
  config="$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml"
  reload_hook="$ROOT_DIR/dotfiles/noctalia/.local/bin/noctalia-reload-ghostty"
  state_file="$TEST_ROOT/ghostty-service-states"
  setup_fake_bin

  run python3 - "$config" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)

templates = config["theme"]["templates"]
assert "ghostty" not in templates["builtin_ids"]
assert templates["user"]["ghostty"] == {
    "input_path": "$XDG_CONFIG_HOME/noctalia/templates/ghostty",
    "output_path": "$XDG_CONFIG_HOME/ghostty/themes/noctalia",
    "post_hook": "$HOME/.local/bin/noctalia-reload-ghostty",
}
PY
  [ "$status" -eq 0 ]

  write_fake_command systemctl <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'systemctl:%s\n' "$*" >>"$GHOSTTY_RELOAD_COMMAND_LOG"
if [[ "$*" == "--user show --property=ActiveState --value app-com.mitchellh.ghostty.service" ]]; then
  if [[ -n "${GHOSTTY_RELOAD_STATE_FILE:-}" ]]; then
    mapfile -t states <"$GHOSTTY_RELOAD_STATE_FILE"
    printf '%s\n' "${states[0]}"
    if (("${#states[@]}" > 1)); then
      printf '%s\n' "${states[@]:1}" >"$GHOSTTY_RELOAD_STATE_FILE"
    fi
  else
    printf '%s\n' "${GHOSTTY_RELOAD_STATE:-active}"
  fi
  exit 0
fi
[[ "$*" == "--user reload app-com.mitchellh.ghostty.service" ]]
EOF
  write_fake_command sleep <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'sleep:%s\n' "$*" >>"$GHOSTTY_RELOAD_COMMAND_LOG"
EOF

  GHOSTTY_RELOAD_COMMAND_LOG="$COMMAND_LOG" \
    PATH="$FAKE_BIN:$PATH" \
    "$reload_hook"

  assert_file_contains "$COMMAND_LOG" \
    "systemctl:--user show --property=ActiveState --value app-com.mitchellh.ghostty.service"
  assert_file_contains "$COMMAND_LOG" \
    "systemctl:--user reload app-com.mitchellh.ghostty.service"
  refute_file_contains "$COMMAND_LOG" "sleep:"

  : >"$COMMAND_LOG"
  printf 'activating\nactive\n' >"$state_file"
  GHOSTTY_RELOAD_STATE_FILE="$state_file" \
    GHOSTTY_RELOAD_COMMAND_LOG="$COMMAND_LOG" \
    PATH="$FAKE_BIN:$PATH" \
    "$reload_hook"

  assert_file_contains "$COMMAND_LOG" \
    "sleep:0.1"
  [ "$(grep -Fc "systemctl:--user show --property=ActiveState --value app-com.mitchellh.ghostty.service" "$COMMAND_LOG")" -eq 2 ]
  assert_file_contains "$COMMAND_LOG" \
    "systemctl:--user reload app-com.mitchellh.ghostty.service"

  : >"$COMMAND_LOG"
  GHOSTTY_RELOAD_STATE=inactive \
    GHOSTTY_RELOAD_COMMAND_LOG="$COMMAND_LOG" \
    PATH="$FAKE_BIN:$PATH" \
    "$reload_hook"

  assert_file_contains "$COMMAND_LOG" \
    "systemctl:--user show --property=ActiveState --value app-com.mitchellh.ghostty.service"
  refute_file_contains "$COMMAND_LOG" "sleep:"
  refute_file_contains "$COMMAND_LOG" \
    "systemctl:--user reload app-com.mitchellh.ghostty.service"
}

@test "Noctalia icon theme sync maps accent to closest installed Yaru theme" {
  setup_fake_bin
  TARGET_HOME="$TEST_ROOT/icon-theme-home"
  mkdir -p \
    "$TARGET_HOME/.cache/noctalia" \
    "$TARGET_HOME/.local/share/icons/Yaru-blue" \
    "$TARGET_HOME/.local/share/icons/Yaru-red"
  printf '#f85149\n' >"$TARGET_HOME/.cache/noctalia/icon-theme-accent"

  write_fake_command gsettings <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'gsettings:%s\n' "$*" >>"$ICON_THEME_COMMAND_LOG"
EOF
  write_fake_command systemctl <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'systemctl:%s\n' "$*" >>"$ICON_THEME_COMMAND_LOG"
EOF
  write_fake_command dbus-update-activation-environment <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'dbus:%s:%s\n' "${QS_ICON_THEME:-}" "$*" >>"$ICON_THEME_COMMAND_LOG"
EOF
  write_fake_command kwriteconfig6 <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
file=""
group=""
key=""
value="${*: -1}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --file)
      file="$2"
      shift 2
      ;;
    --group)
      group="$2"
      shift 2
      ;;
    --key)
      key="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$HOME/.config"
{
  printf '[%s]\n' "$group"
  printf '%s=%s\n' "$key" "$value"
} >"$HOME/.config/$file"
printf 'kwriteconfig6:%s:%s:%s:%s\n' "$file" "$group" "$key" "$value" >>"$ICON_THEME_COMMAND_LOG"
EOF

  HOME="$TARGET_HOME" \
    XDG_CACHE_HOME="$TARGET_HOME/.cache" \
    ICON_THEME_COMMAND_LOG="$COMMAND_LOG" \
    PATH="$FAKE_BIN:$PATH" \
    "$ROOT_DIR/dotfiles/noctalia/.local/bin/noctalia-sync-icon-theme"

  assert_file_contains "$COMMAND_LOG" 'gsettings:set org.gnome.desktop.interface icon-theme Yaru-red'
  assert_file_contains "$COMMAND_LOG" 'systemctl:--user set-environment QS_ICON_THEME=Yaru-red'
  assert_file_contains "$COMMAND_LOG" 'dbus:Yaru-red:--systemd QS_ICON_THEME'
  assert_file_contains "$TARGET_HOME/.config/qt6ct/qt6ct.conf" 'icon_theme=Yaru-red'
  assert_file_contains "$TARGET_HOME/.config/kdeglobals" 'Theme=Yaru-red'
}

@test "Noctalia icon theme sync leaves settings unchanged when no Yaru theme is installed" {
  setup_fake_bin
  TARGET_HOME="$TEST_ROOT/icon-theme-missing-home"
  mkdir -p "$TARGET_HOME/.cache/noctalia"
  printf '#f85149\n' >"$TARGET_HOME/.cache/noctalia/icon-theme-accent"

  for cmd in gsettings systemctl dbus-update-activation-environment kwriteconfig6; do
    write_fake_command "$cmd" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$0 $*" >>"$ICON_THEME_COMMAND_LOG"
EOF
  done

  HOME="$TARGET_HOME" \
    XDG_CACHE_HOME="$TARGET_HOME/.cache" \
    XDG_DATA_DIRS="$TEST_ROOT/icon-theme-missing-data" \
    ICON_THEME_COMMAND_LOG="$COMMAND_LOG" \
    PATH="$FAKE_BIN:$PATH" \
    "$ROOT_DIR/dotfiles/noctalia/.local/bin/noctalia-sync-icon-theme"

  [[ ! -e "$COMMAND_LOG" ]]
  [[ ! -e "$TARGET_HOME/.config/qt6ct/qt6ct.conf" ]]
  [[ ! -e "$TARGET_HOME/.config/kdeglobals" ]]
}

@test "Niri display config is seeded only when absent" {
  build_test_plan
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
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/first-run-commands.log"
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
  assert_file_contains "$TARGET_HOME/.config/autostart/zz-first-run.desktop" "Exec=$TARGET_HOME/.local/bin/zz first-run"

  run_without_bats_debug_trap module_85_first_run
  [[ -f "$(first_run_marker)" ]]
  [[ ! -e "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "systemctl --user daemon-reload"
  assert_file_contains "$TEST_ROOT/first-run-commands.log" "systemctl --user enable --now app-com.mitchellh.ghostty.service"

  : >"$TEST_ROOT/first-run-commands.log"
  run_without_bats_debug_trap module_85_first_run
  [[ ! -s "$TEST_ROOT/first-run-commands.log" ]]
}

@test "managed Noctalia app themes render synchronously and skip without managed config" {
  build_test_plan "browser=firefox" "dev=vscode"
  TARGET_USER="theme-user"
  DRY_RUN=0
  command_log="$TEST_ROOT/noctalia-app-theme-commands.log"
  palette_file="$TARGET_HOME/.config/noctalia/palettes/catppuccin-mocha-blue.json"
  config_file="$TARGET_HOME/.config/noctalia/config.toml"
  pywalfox_config="$XDG_STATE_HOME/noctalia/community-templates/pywalfox/template.toml"
  vscode_config="$XDG_STATE_HOME/noctalia/community-templates/vscode/template.toml"
  mkdir -p "$(dirname "$palette_file")" "$(dirname "$pywalfox_config")" "$(dirname "$vscode_config")"
  touch "$palette_file" "$config_file" "$pywalfox_config" "$vscode_config"

  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$*" >>"$command_log"
  }

  apply_managed_noctalia_app_themes

  assert_file_contains "$command_log" \
    "theme-user:noctalia theme --theme-json $palette_file --default-mode dark -c $pywalfox_config"
  assert_file_contains "$command_log" \
    "theme-user:noctalia theme --theme-json $palette_file --default-mode dark -c $vscode_config"

  rm -f "$config_file"
  : >"$command_log"
  apply_managed_noctalia_app_themes
  [[ ! -s "$command_log" ]]
}

@test "managed Zed settings select the enabled Noctalia theme variants" {
  local settings_file="$ROOT_DIR/dotfiles/zed/.config/zed/settings.json"
  local noctalia_config="$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml"

  assert_file_contains "$settings_file" '"light": "Noctalia Light"'
  assert_file_contains "$settings_file" '"dark": "Noctalia Dark"'
  assert_file_contains "$noctalia_config" '"zed",'
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
