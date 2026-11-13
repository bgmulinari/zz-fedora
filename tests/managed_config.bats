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

@test "seed replaces an untouched distro skeleton copy and backs it up" {
  timestamp() {
    printf '20260101-000000\n'
  }
  DISTRO_SKEL_DIR="$TEST_ROOT/skel"
  mkdir -p "$DISTRO_SKEL_DIR"
  printf '# .bashrc from the distro skeleton\n' >"$DISTRO_SKEL_DIR/.bashrc"
  cp "$DISTRO_SKEL_DIR/.bashrc" "$TARGET_HOME/.bashrc"

  run seed_user_config_if_missing "$ROOT_DIR/templates/shell/bashrc" "$TARGET_HOME/.bashrc"

  [ "$status" -eq 0 ]
  cmp -s "$ROOT_DIR/templates/shell/bashrc" "$TARGET_HOME/.bashrc"
  assert_equal '# .bashrc from the distro skeleton' \
    "$(cat "$STATE_DIR/backups/20260101-000000$TARGET_HOME/.bashrc")"
}

@test "seed preserves a skeleton copy the user has edited" {
  DISTRO_SKEL_DIR="$TEST_ROOT/skel"
  mkdir -p "$DISTRO_SKEL_DIR"
  printf '# .bashrc from the distro skeleton\n' >"$DISTRO_SKEL_DIR/.bashrc"
  printf '# .bashrc from the distro skeleton\nalias k=kubectl\n' >"$TARGET_HOME/.bashrc"

  run seed_user_config_if_missing "$ROOT_DIR/templates/shell/bashrc" "$TARGET_HOME/.bashrc"

  [ "$status" -eq 0 ]
  assert_contains "$(cat "$TARGET_HOME/.bashrc")" "alias k=kubectl"
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

@test "Claude Code component seeds attribution-free settings and preserves an edited file" {
  managed_config_required_command_available() {
    return 0
  }
  mkdir -p "$PLAN_DIR/files"
  : >"$(managed_config_deployment_plan_file)"
  append_managed_config_component claude-code

  run apply_managed_config_plan

  [ "$status" -eq 0 ]
  [ -f "$TARGET_HOME/.claude/settings.json" ]
  run /usr/bin/python3 -c '
import json, sys
settings = json.load(open(sys.argv[1]))
assert settings == {"attribution": {"commit": "", "pr": "", "sessionUrl": False}}, settings
' "$TARGET_HOME/.claude/settings.json"
  [ "$status" -eq 0 ]

  # Claude Code rewrites this file from its own menus, so a rerun must not
  # put the seed back over the user's version.
  printf '{"model": "opus", "attribution": {"commit": ""}}\n' >"$TARGET_HOME/.claude/settings.json"
  run apply_managed_config_plan
  [ "$status" -eq 0 ]
  assert_file_contains "$TARGET_HOME/.claude/settings.json" '"model": "opus"'
  refute_file_contains "$TARGET_HOME/.claude/settings.json" 'sessionUrl'
}

@test "Niri component seeds Xray preferences and leaves subsequent DMS edits intact" {
  managed_config_required_command_available() {
    return 0
  }
  mkdir -p "$PLAN_DIR/files"
  : >"$(managed_config_deployment_plan_file)"
  append_managed_config_component niri

  run apply_managed_config_plan

  [ "$status" -eq 0 ]
  local layout="$TARGET_HOME/.config/niri/dms/layout.kdl"
  [ -f "$layout" ]
  [ ! -L "$layout" ]
  assert_file_contains "$layout" 'xray false'
  assert_file_contains "$layout" '// bar-xray off'

  printf '// DMS regenerated layout after the user enabled Xray\n' >"$layout"
  run apply_managed_config_plan
  [ "$status" -eq 0 ]
  assert_equal '// DMS regenerated layout after the user enabled Xray' "$(cat "$layout")"
}

@test "Zsh component links the product login environment" {
  managed_config_required_command_available() {
    return 0
  }
  mkdir -p "$PLAN_DIR/files"
  : >"$(managed_config_deployment_plan_file)"
  append_managed_config_component zsh

  run apply_managed_config_plan

  [ "$status" -eq 0 ]
  [ -f "$TARGET_HOME/.zshrc" ]
  [[ -L "$TARGET_HOME/.zprofile" ]]
  assert_equal \
    "$(readlink -f "$ROOT_DIR/dotfiles/zsh/.zprofile")" \
    "$(readlink -f "$TARGET_HOME/.zprofile")"
}

@test "Shell component replaces the distro Bash login profile with the product link" {
  timestamp() {
    printf '20260101-000000\n'
  }
  mkdir -p "$PLAN_DIR/files"
  : >"$(managed_config_deployment_plan_file)"
  printf '# .bash_profile from /etc/skel\n' >"$TARGET_HOME/.bash_profile"
  append_managed_config_component shell

  run apply_managed_config_plan

  [ "$status" -eq 0 ]
  [[ -L "$TARGET_HOME/.bash_profile" ]]
  assert_equal \
    "$(readlink -f "$ROOT_DIR/dotfiles/shell/.bash_profile")" \
    "$(readlink -f "$TARGET_HOME/.bash_profile")"
  assert_equal '# .bash_profile from /etc/skel' \
    "$(cat "$STATE_DIR/backups/20260101-000000$TARGET_HOME/.bash_profile")"
}

@test "skip user config leaves home paths alone while system rows still apply" {
  SKIP_USER_CONFIG=1
  mkdir -p "$PLAN_DIR/files"
  printf 'personal bashrc\n' >"$TARGET_HOME/.bashrc"
  {
    printf 'shell\t~/.bashrc\tseed-if-missing\tpreserve\ttemplates/shell/bashrc\t-\tShell\n'
    printf 'environment\t/usr/lib/environment.d/test.conf\tsystem-file\tregenerate\tdotfiles/environment/.config/environment.d/10-zz-desktop.conf\t-\tEnvironment\n'
  } >"$(managed_config_deployment_plan_file)"
  install_system_config_file() {
    printf '%s -> %s\n' "$1" "$2" >"$TEST_ROOT/system-install"
  }

  run apply_managed_config_plan

  [ "$status" -eq 0 ]
  assert_equal "personal bashrc" "$(cat "$TARGET_HOME/.bashrc")"
  assert_file_contains "$TEST_ROOT/system-install" "/usr/lib/environment.d/test.conf"
}

write_systemd_drop_in_rows() {
  mkdir -p "$PLAN_DIR/files"
  {
    printf 'greeter-gpu-wait\t/usr/lib/systemd/system/zz-test.service.d/a.conf\tsystem-file\tregenerate\tdotfiles/greetd/50-zz-gpu-ready.conf\t-\tDrop-in\n'
    printf 'greeter-gpu-wait\t/usr/lib/systemd/system/zz-test.service.d/b.conf\tsystem-file\tregenerate\tdotfiles/greetd/50-zz-gpu-ready.conf\t-\tDrop-in\n'
  } >"$(managed_config_deployment_plan_file)"
}

@test "a changed systemd system drop-in reloads systemd once after the apply pass" {
  write_systemd_drop_in_rows
  install_file_if_changed() { INSTALL_FILE_CHANGED=1; }
  run_cmd_as_root() { printf '%s\n' "$*" >>"$TEST_ROOT/root-commands"; }

  apply_managed_config_plan

  assert_equal "systemctl daemon-reload" "$(cat "$TEST_ROOT/root-commands")"
}

@test "a repeated apply with unchanged systemd drop-ins does not reload systemd" {
  write_systemd_drop_in_rows
  install_file_if_changed() { INSTALL_FILE_CHANGED=0; }
  run_cmd_as_root() { printf '%s\n' "$*" >>"$TEST_ROOT/root-commands"; }

  apply_managed_config_plan

  [ ! -e "$TEST_ROOT/root-commands" ]
}

@test "system files outside the systemd unit directories do not reload systemd" {
  mkdir -p "$PLAN_DIR/files"
  printf 'environment\t/usr/lib/environment.d/zz-test.conf\tsystem-file\tregenerate\tdotfiles/environment/.config/environment.d/10-zz-desktop.conf\t-\tEnvironment\n' \
    >"$(managed_config_deployment_plan_file)"
  install_file_if_changed() { INSTALL_FILE_CHANGED=1; }
  run_cmd_as_root() { printf '%s\n' "$*" >>"$TEST_ROOT/root-commands"; }

  apply_managed_config_plan

  [ ! -e "$TEST_ROOT/root-commands" ]
}

@test "install_file_if_changed reports whether it installed the file" {
  local source="$TEST_ROOT/source.conf" destination="$TARGET_HOME/dest.conf"
  printf 'v1\n' >"$source"

  install_file_if_changed user "$source" "$destination"
  assert_equal 1 "$INSTALL_FILE_CHANGED"
  assert_equal v1 "$(cat "$destination")"

  install_file_if_changed user "$source" "$destination"
  assert_equal 0 "$INSTALL_FILE_CHANGED"

  printf 'v2\n' >"$source"
  backup_user_file_if_needed() { :; }
  install_file_if_changed user "$source" "$destination"
  assert_equal 1 "$INSTALL_FILE_CHANGED"
  assert_equal v2 "$(cat "$destination")"
}
