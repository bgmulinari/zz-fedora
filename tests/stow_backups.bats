#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "stow_backup_existing_target moves a pre-existing file into the timestamped backup" {
  DRY_RUN=0
  timestamp() {
    printf '20260101-000000\n'
  }
  run_cmd_as_user() {
    shift
    "$@"
  }
  printf 'existing bashrc\n' >"$TARGET_HOME/.bashrc"

  run stow_backup_existing_target .bashrc

  [ "$status" -eq 0 ]
  [[ ! -e "$TARGET_HOME/.bashrc" ]]
  assert_equal "existing bashrc" "$(cat "$STATE_DIR/backups/20260101-000000$TARGET_HOME/.bashrc")"
}

@test "stow_backup_existing_target fails with the backup cause when the backup directory cannot be created" {
  DRY_RUN=0
  printf 'existing bashrc\n' >"$TARGET_HOME/.bashrc"
  run_cmd_as_user() {
    shift
    if [[ "$1" == "mkdir" ]]; then
      printf 'mkdir: cannot create directory: Permission denied\n' >&2
      return 1
    fi
    "$@"
  }

  run stow_backup_existing_target .bashrc

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not create dotfile backup directory"
  [[ -e "$TARGET_HOME/.bashrc" ]]
}

@test "stow_backup_existing_target fails with the backup cause when the move fails" {
  DRY_RUN=0
  printf 'existing bashrc\n' >"$TARGET_HOME/.bashrc"
  run_cmd_as_user() {
    shift
    if [[ "$1" == "mv" ]]; then
      printf 'mv: cannot move: No such file or directory\n' >&2
      return 1
    fi
    "$@"
  }

  run stow_backup_existing_target .bashrc

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not back up $TARGET_HOME/.bashrc"
}

@test "stow_apply_plan surfaces a backup failure instead of the misleading stow conflict message" {
  DRY_RUN=0
  mkdir -p "$PLAN_DIR/stow"
  printf 'shell\n' >"$PLAN_DIR/stow/packages.list"
  printf 'existing bashrc\n' >"$TARGET_HOME/.bashrc"
  run_cmd_as_user() {
    shift
    if [[ "$1" == "mkdir" ]]; then
      printf 'mkdir: cannot create directory: Permission denied\n' >&2
      return 1
    fi
    "$@"
  }

  run stow_apply_plan

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not create dotfile backup directory"
  refute_contains "$output" "Stow reported conflicts"
}
