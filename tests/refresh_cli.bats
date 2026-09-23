#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  setup_fake_bin
  # A short private runtime dir keeps the unix socket path under the length
  # limit and the theme helper away from a real DMS backend on the host.
  RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zz-rt.XXXXXX")"
  THEME_FILE="$TARGET_HOME/.config/DankMaterialShell/themes/catppuccin/theme.json"
  mkdir -p "$(dirname "$THEME_FILE")"
  printf '{"id":"catppuccin"}\n' >"$THEME_FILE"
}

teardown() {
  rm -rf "$RUNTIME_DIR"
}

# Serve one themes.install request on the DMS backend socket.
start_fake_dms_backend() {
  local socket="$RUNTIME_DIR/danklinux-1.sock"
  /usr/bin/python3 "$ROOT_DIR/tests/support/fake_dms_backend.py" "$socket" "$TARGET_HOME" &
  local attempt
  for ((attempt = 0; attempt < 50; attempt++)); do
    [[ -S "$socket" ]] && return 0
    sleep 0.1
  done
  return 1
}

# systemctl stub that logs each call and answers is-active with the given
# status for dms.service.
fake_dms_unit() {
  write_fake_command systemctl <<STUB
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >>"$COMMAND_LOG"
[[ "\$*" != *is-active* ]] || exit $1
STUB
}

run_refresh() {
  run env -u WAYLAND_DISPLAY -u DISPLAY -u DMS_SOCKET HOME="$TARGET_HOME" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" PATH="$FAKE_BIN:$PATH" bash "$ROOT_DIR/bin/zz" refresh "$@"
}

@test "zz refresh lists only user-owned seeded configs" {
  run env HOME="$TARGET_HOME" bash "$ROOT_DIR/bin/zz" refresh --list

  [ "$status" -eq 0 ]
  assert_contains "$output" "niri/config.kdl"
  assert_contains "$output" "ghostty/config"
  assert_contains "$output" ".bashrc"
  assert_contains "$output" "DankMaterialShell/settings.json"
  assert_contains "$output" "DankMaterialShell/plugin_settings.json"
  assert_contains "$output" ".local/state/DankMaterialShell/session.json"
  assert_contains "$output" "dms "
  refute_contains "$output" "ghostty/zz-defaults"
}

@test "zz refresh backs up a changed file before installing the current default" {
  mkdir -p "$TARGET_HOME/.config/ghostty"
  printf 'personal setting\n' >"$TARGET_HOME/.config/ghostty/config"

  run env HOME="$TARGET_HOME" bash "$ROOT_DIR/bin/zz" refresh ghostty/config

  [ "$status" -eq 0 ]
  assert_contains "$output" "Saved backup as"
  assert_equal "$(cat "$ROOT_DIR/templates/ghostty/config")" \
    "$(cat "$TARGET_HOME/.config/ghostty/config")"
  local backup
  backup="$(find "$TARGET_HOME/.config/ghostty" -maxdepth 1 -name 'config.bak.*' -print -quit)"
  [ -n "$backup" ]
  assert_equal "personal setting" "$(cat "$backup")"
}

@test "zz refresh does not create a backup when the file already matches" {
  mkdir -p "$TARGET_HOME/.config/ghostty"
  cp "$ROOT_DIR/templates/ghostty/config" "$TARGET_HOME/.config/ghostty/config"

  run env HOME="$TARGET_HOME" bash "$ROOT_DIR/bin/zz" refresh ghostty/config

  [ "$status" -eq 0 ]
  assert_contains "$output" "already matches"
  run find "$TARGET_HOME/.config/ghostty" -maxdepth 1 -name 'config.bak.*' -print
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "zz refresh materializes a matching symlink as a user-owned file" {
  mkdir -p "$TARGET_HOME/.config/btop"
  ln -s "$ROOT_DIR/dotfiles/btop/.config/btop/btop.conf" \
    "$TARGET_HOME/.config/btop/btop.conf"

  run env HOME="$TARGET_HOME" bash "$ROOT_DIR/bin/zz" refresh btop/btop.conf

  [ "$status" -eq 0 ]
  assert_contains "$output" "Saved backup as"
  [[ -f "$TARGET_HOME/.config/btop/btop.conf" ]]
  [[ ! -L "$TARGET_HOME/.config/btop/btop.conf" ]]
  assert_equal "$(cat "$ROOT_DIR/dotfiles/btop/.config/btop/btop.conf")" \
    "$(cat "$TARGET_HOME/.config/btop/btop.conf")"
  local backup
  backup="$(find "$TARGET_HOME/.config/btop" -maxdepth 1 -name 'btop.conf.bak.*' -print -quit)"
  [ -n "$backup" ]
}

@test "zz refresh rejects ZZ-managed link paths" {
  run env HOME="$TARGET_HOME" bash "$ROOT_DIR/bin/zz" refresh ghostty/zz-defaults

  [ "$status" -ne 0 ]
  assert_contains "$output" "Not a refreshable ZZ config"
}

@test "zz refresh renders the DMS settings seed and restarts a running shell" {
  fake_dms_unit 0
  local settings="$TARGET_HOME/.config/DankMaterialShell/settings.json"
  mkdir -p "$(dirname "$settings")"
  printf '{"cornerRadius": 3}\n' >"$settings"

  run_refresh DankMaterialShell/settings.json

  [ "$status" -eq 0 ]
  assert_contains "$output" "Saved backup as"
  assert_equal "$TARGET_HOME/.config/DankMaterialShell/themes/catppuccin/theme.json" \
    "$(jq -r '.customThemeFile' "$settings")"
  assert_equal "$(jq -r '.cornerRadius' "$ROOT_DIR/templates/dms/settings-seed.json")" \
    "$(jq -r '.cornerRadius' "$settings")"
  assert_file_contains "$COMMAND_LOG" "systemctl --user restart dms.service"
}

@test "zz refresh renders the DMS session seed with the default wallpaper" {
  fake_dms_unit 3

  run_refresh .local/state/DankMaterialShell/session.json

  [ "$status" -eq 0 ]
  assert_contains "$output" "Installed the current ZZ default"
  assert_equal "$TARGET_HOME/.local/share/backgrounds/Alpenglow.jpg" \
    "$(jq -r '.wallpaperPath' "$TARGET_HOME/.local/state/DankMaterialShell/session.json")"
  refute_file_contains "$COMMAND_LOG" "restart"
}

@test "zz refresh enables only the DMS plugins the saved plan carries" {
  fake_dms_unit 3
  mkdir -p "$XDG_STATE_HOME/zz-fedora/plan/config"
  printf 'dms\n' >"$XDG_STATE_HOME/zz-fedora/plan/config/components.list"

  run_refresh DankMaterialShell/plugin_settings.json

  [ "$status" -eq 0 ]
  local plugins="$TARGET_HOME/.config/DankMaterialShell/plugin_settings.json"
  assert_equal true "$(jq -r '.zzMenu.enabled' "$plugins")"
  assert_equal null "$(jq -r '.protonManager' "$plugins")"
}

@test "zz refresh leaves the DMS shell alone when the settings already match" {
  fake_dms_unit 0
  run_refresh DankMaterialShell/settings.json
  [ "$status" -eq 0 ]
  : >"$COMMAND_LOG"

  run_refresh DankMaterialShell/settings.json

  [ "$status" -eq 0 ]
  assert_contains "$output" "already matches"
  refute_file_contains "$COMMAND_LOG" "restart"
}

@test "zz refresh dms resets every DMS file with one shell restart" {
  fake_dms_unit 0

  run_refresh dms

  [ "$status" -eq 0 ]
  [[ -f "$TARGET_HOME/.config/DankMaterialShell/settings.json" ]]
  [[ -f "$TARGET_HOME/.config/DankMaterialShell/plugin_settings.json" ]]
  [[ -f "$TARGET_HOME/.local/state/DankMaterialShell/session.json" ]]
  assert_equal 1 "$(grep -c 'restart dms.service' "$COMMAND_LOG")"
}

@test "zz refresh still restarts the DMS shell when a later path is rejected" {
  fake_dms_unit 0

  run_refresh DankMaterialShell/settings.json ghostty/zz-defaults

  [ "$status" -ne 0 ]
  assert_contains "$output" "Not a refreshable ZZ config"
  assert_file_contains "$COMMAND_LOG" "systemctl --user restart dms.service"
}

@test "zz refresh reinstalls a removed DMS theme before restarting the shell" {
  fake_dms_unit 0
  run_refresh DankMaterialShell/settings.json
  [ "$status" -eq 0 ]
  rm -rf "$(dirname "$THEME_FILE")"
  : >"$COMMAND_LOG"
  start_fake_dms_backend

  run_refresh dms

  [ "$status" -eq 0 ]
  assert_contains "$output" "Installed the Catppuccin theme"
  assert_equal catppuccin "$(jq -r '.id' "$THEME_FILE")"
  assert_file_contains "$COMMAND_LOG" "systemctl --user restart dms.service"
}

@test "zz refresh reports a DMS theme it cannot reinstall" {
  fake_dms_unit 3
  rm -rf "$(dirname "$THEME_FILE")"

  run_refresh DankMaterialShell/settings.json

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not install the Catppuccin theme"
  [[ -f "$TARGET_HOME/.config/DankMaterialShell/settings.json" ]]
}
