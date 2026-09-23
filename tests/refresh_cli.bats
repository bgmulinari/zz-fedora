#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  setup_fake_bin
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
  run env HOME="$TARGET_HOME" PATH="$FAKE_BIN:$PATH" bash "$ROOT_DIR/bin/zz" refresh "$@"
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
