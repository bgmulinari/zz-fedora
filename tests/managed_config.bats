#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  DRY_RUN=0
  SKIP_USER_CONFIG=0
  run_cmd_as_user() {
    shift
    "$@"
  }
}

@test "seed_user_config_if_missing preserves an existing user file" {
  printf 'personal bashrc\n' >"$TARGET_HOME/.bashrc"

  run seed_user_config_if_missing "$ROOT_DIR/templates/shell/bashrc" "$TARGET_HOME/.bashrc"

  [ "$status" -eq 0 ]
  assert_equal "personal bashrc" "$(cat "$TARGET_HOME/.bashrc")"
}

@test "product links back up an existing file before linking the live ZZ default" {
  timestamp() {
    printf '20260101-000000\n'
  }
  mkdir -p "$TARGET_HOME/.config/ghostty"
  local destination="$TARGET_HOME/.config/ghostty/zz-defaults"
  local source="$ROOT_DIR/dotfiles/ghostty/.config/ghostty/config"
  printf 'personal defaults\n' >"$destination"

  run replace_user_path_with_product_link "$source" "$destination"

  [ "$status" -eq 0 ]
  [[ -L "$destination" ]]
  assert_equal "$(readlink -f "$source")" "$(readlink -f "$destination")"
  assert_equal "personal defaults" \
    "$(cat "$STATE_DIR/backups/20260101-000000$destination")"
}

@test "product link replacement surfaces a backup failure and preserves the target" {
  mkdir -p "$TARGET_HOME/.config/ghostty"
  local destination="$TARGET_HOME/.config/ghostty/zz-defaults"
  local source="$ROOT_DIR/dotfiles/ghostty/.config/ghostty/config"
  printf 'personal defaults\n' >"$destination"
  run_cmd_as_user() {
    shift
    if [[ "$1" == "mkdir" ]]; then
      printf 'mkdir: permission denied\n' >&2
      return 1
    fi
    "$@"
  }

  run replace_user_path_with_product_link "$source" "$destination"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not create backup directory"
  assert_equal "personal defaults" "$(cat "$destination")"
}

@test "skip user config leaves home paths alone while system rows still apply" {
  SKIP_USER_CONFIG=1
  mkdir -p "$PLAN_DIR/files"
  printf 'personal bashrc\n' >"$TARGET_HOME/.bashrc"
  {
    printf 'shell\t~/.bashrc\tseed-if-missing\tpreserve\ttemplates/shell/bashrc\t-\tShell\n'
    printf 'environment\t/usr/lib/environment.d/test.conf\tsystem-file\tregenerate\tdotfiles/environment/.config/environment.d/10-niri-gtk.conf\t-\tEnvironment\n'
  } >"$(managed_config_deployment_plan_file)"
  install_system_config_file() {
    printf '%s -> %s\n' "$1" "$2" >"$TEST_ROOT/system-install"
  }

  run apply_managed_config_plan

  [ "$status" -eq 0 ]
  assert_equal "personal bashrc" "$(cat "$TARGET_HOME/.bashrc")"
  assert_file_contains "$TEST_ROOT/system-install" "/usr/lib/environment.d/test.conf"
}
