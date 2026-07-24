#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
}

@test "zz refresh lists only user-owned seeded configs" {
  run env HOME="$TARGET_HOME" bash "$ROOT_DIR/bin/zz" refresh --list

  [ "$status" -eq 0 ]
  assert_contains "$output" "niri/config.kdl"
  assert_contains "$output" "ghostty/config"
  assert_contains "$output" ".bashrc"
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

@test "zz refresh rejects product-owned link paths" {
  run env HOME="$TARGET_HOME" bash "$ROOT_DIR/bin/zz" refresh ghostty/zz-defaults

  [ "$status" -ne 0 ]
  assert_contains "$output" "Not a refreshable ZZ config"
}
