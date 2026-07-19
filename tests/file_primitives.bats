#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "backup_target_path mirrors the destination under a timestamped backups root" {
  timestamp() {
    printf '20260101-000000\n'
  }

  run backup_target_path /etc/example/config.toml

  [ "$status" -eq 0 ]
  assert_equal "$STATE_DIR/backups/20260101-000000/etc/example/config.toml" "$output"
}

@test "chown_state_path_to_owner hands the created chain to the state owner up to the state root" {
  STATE_OWNER_USER="$(id -un)"
  owner_group="$(id -gn)"
  state_owner_fixup_required() {
    return 0
  }
  chown() {
    printf 'chown %s\n' "$*" >>"$TEST_ROOT/chown.log"
  }

  chown_state_path_to_owner "$STATE_DIR/backups/20260101-000000/etc/greetd"

  assert_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group $STATE_DIR/backups/20260101-000000/etc/greetd"
  assert_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group $STATE_DIR/backups/20260101-000000/etc"
  assert_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group $STATE_DIR/backups/20260101-000000"
  assert_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group $STATE_DIR/backups"
  assert_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group $STATE_DIR"
  refute_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group $(dirname "$STATE_DIR")"
}

@test "chown_state_path_to_owner terminates on trailing-slash root shapes without escaping" {
  STATE_OWNER_USER="$(id -un)"
  owner_group="$(id -gn)"
  state_owner_fixup_required() {
    return 0
  }
  chown() {
    printf 'chown %s\n' "$*" >>"$TEST_ROOT/chown.log"
  }

  # The ensure_state_dirs shape: a reassigned trailing-slash root passed as
  # the path itself must chown exactly the normalized root, never its parent
  # or /.
  state_root="$STATE_DIR"
  STATE_DIR="$STATE_DIR/"
  chown_state_path_to_owner "$STATE_DIR"
  assert_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group $state_root"
  refute_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group $state_root/"
  refute_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group $(dirname "$state_root")"
  refute_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group /"

  # A relative trailing-slash root must terminate (no dirname-of-. spin) and
  # never chown "." or walk above the root.
  : >"$TEST_ROOT/chown.log"
  STATE_DIR="relative-state/"
  chown_state_path_to_owner "relative-state/"
  chown_state_path_to_owner "relative-state/backups/20260101-000000"
  assert_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group relative-state"
  assert_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group relative-state/backups/20260101-000000"
  refute_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group ."
  refute_file_line "$TEST_ROOT/chown.log" "chown -h $STATE_OWNER_USER:$owner_group /"
}

@test "chown_state_path_to_owner argument syntax works against the real chown" {
  STATE_OWNER_USER="$(id -un)"
  state_owner_fixup_required() {
    return 0
  }
  mkdir -p "$STATE_DIR/backups/20260101-000000"

  run chown_state_path_to_owner "$STATE_DIR/backups/20260101-000000"

  [ "$status" -eq 0 ]
  refute_contains "$output" "WARN: could not hand"
  assert_equal "$(id -un)" "$(stat -c %U "$STATE_DIR/backups/20260101-000000")"
}

@test "normalize_dir_var strips every trailing slash but keeps the filesystem root" {
  value="/tmp/example///"
  normalize_dir_var value
  assert_equal "/tmp/example" "$value"

  value="/"
  normalize_dir_var value
  assert_equal "/" "$value"
}

@test "state dir assignments strip trailing slashes from environment overrides" {
  run bash -c "export STATE_DIR='$TEST_ROOT/state-slash///'; source '$ROOT_DIR/lib/common.sh'; printf 'STATE_DIR=%s\n' \"\$STATE_DIR\""

  [ "$status" -eq 0 ]
  assert_contains "$output" "STATE_DIR=$TEST_ROOT/state-slash"
  refute_contains "$output" "STATE_DIR=$TEST_ROOT/state-slash/"
}

@test "ensure_state_dirs hands root-created state directories to the state owner" {
  STATE_OWNER_USER="$(id -un)"
  state_owner_fixup_required() {
    return 0
  }
  chown() {
    printf 'chown %s\n' "$*" >>"$TEST_ROOT/chown.log"
  }

  ensure_state_dirs

  for dir in "$STATE_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$LOG_DIR"; do
    [[ -d "$dir" ]]
    assert_file_contains "$TEST_ROOT/chown.log" " $dir"
  done
  # PLAN_DIR is created but deliberately not handed over here: plan_reset
  # recreates it in installer context and the exit-time restore covers it.
  [[ -d "$PLAN_DIR" ]]
  refute_file_contains "$TEST_ROOT/chown.log" " $PLAN_DIR"
}

@test "backup_file_if_needed hands a root-context backup to the state owner as it is created" {
  DRY_RUN=0
  STATE_OWNER_USER="$(id -un)"
  state_owner_fixup_required() {
    return 0
  }
  chown() {
    printf 'chown %s\n' "$*" >>"$TEST_ROOT/chown.log"
  }
  timestamp() {
    printf '20260101-000000\n'
  }
  destination="$TEST_ROOT/etc/greetd/config.toml"
  mkdir -p "$(dirname "$destination")"
  printf 'greetd config\n' >"$destination"

  backup_file_if_needed "$destination"

  backup_path="$STATE_DIR/backups/20260101-000000$destination"
  assert_equal "greetd config" "$(cat "$backup_path")"
  assert_file_contains "$TEST_ROOT/chown.log" " $backup_path"
  assert_file_contains "$TEST_ROOT/chown.log" " $STATE_DIR/backups"
}

@test "state ownership fixup is a no-op without a non-root state owner" {
  chown() {
    printf 'chown %s\n' "$*" >>"$TEST_ROOT/chown.log"
  }

  # The owner guard runs first (before any EUID or id checks), so an empty
  # or root STATE_OWNER_USER short-circuits regardless of the current uid.
  STATE_OWNER_USER=""
  ensure_state_dirs
  chown_state_path_to_owner "$STATE_DIR/backups/20260101-000000"
  STATE_OWNER_USER="root"
  chown_state_path_to_owner "$STATE_DIR/backups/20260101-000000"

  [[ ! -e "$TEST_ROOT/chown.log" ]]
}

@test "backup_target_path adds an incrementing suffix when the timestamped path already exists" {
  timestamp() {
    printf '20260101-000000\n'
  }
  destination="$TEST_ROOT/etc/example.conf"
  base_path="$STATE_DIR/backups/20260101-000000$destination"

  run backup_target_path "$destination"
  assert_equal "$base_path" "$output"

  mkdir -p "$(dirname "$base_path")"
  : >"$base_path"
  run backup_target_path "$destination"
  assert_equal "$base_path.1" "$output"

  : >"$base_path.1"
  run backup_target_path "$destination"
  assert_equal "$base_path.2" "$output"
}

@test "same-second backups of one destination keep every copy" {
  DRY_RUN=0
  timestamp() {
    printf '20260101-000000\n'
  }
  destination="$TEST_ROOT/etc/example.conf"
  mkdir -p "$(dirname "$destination")"
  printf 'first version\n' >"$destination"
  backup_file_if_needed "$destination"
  printf 'second version\n' >"$destination"
  backup_file_if_needed "$destination"

  base_path="$STATE_DIR/backups/20260101-000000$destination"
  assert_equal "first version" "$(cat "$base_path")"
  assert_equal "second version" "$(cat "$base_path.1")"
}

@test "backup_file_if_needed fails with the backup cause when the backup directory cannot be created" {
  DRY_RUN=0
  destination="$TEST_ROOT/etc/example.conf"
  mkdir -p "$(dirname "$destination")"
  printf 'root content\n' >"$destination"
  run_cmd() {
    if [[ "$1" == "mkdir" ]]; then
      printf 'mkdir: cannot create directory: Permission denied\n' >&2
      return 1
    fi
    "$@"
  }

  run backup_file_if_needed "$destination"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not create backup directory"
  refute_contains "$output" "Backed up $destination"
}

@test "backup_file_if_needed fails with the backup cause when the copy fails" {
  DRY_RUN=0
  destination="$TEST_ROOT/etc/example.conf"
  mkdir -p "$(dirname "$destination")"
  printf 'root content\n' >"$destination"
  run_cmd() {
    if [[ "$1" == "cp" ]]; then
      printf 'cp: cannot create regular file: Permission denied\n' >&2
      return 1
    fi
    "$@"
  }

  run backup_file_if_needed "$destination"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not back up $destination"
  refute_contains "$output" "Backed up $destination"
}

@test "install_file_if_changed user installs, backs up, and skips unchanged files" {
  DRY_RUN=0
  TARGET_USER="file-user"
  source_file="$TEST_ROOT/source.conf"
  destination="$TARGET_HOME/.config/example/example.conf"
  printf 'managed content\n' >"$source_file"
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/commands.log"
    "$@"
  }

  install_file_if_changed user "$source_file" "$destination"
  assert_equal "managed content" "$(cat "$destination")"
  assert_file_contains "$TEST_ROOT/commands.log" "user:file-user:install -D -m 0644 $source_file $destination"

  : >"$TEST_ROOT/commands.log"
  run install_file_if_changed user "$source_file" "$destination"
  [ "$status" -eq 0 ]
  assert_contains "$output" "Unchanged file: $destination"
  [[ ! -s "$TEST_ROOT/commands.log" ]]

  printf 'user-edited content\n' >"$destination"
  install_file_if_changed user "$source_file" "$destination"
  assert_equal "managed content" "$(cat "$destination")"
  backup_copy="$(find "$STATE_DIR/backups" -type f -name 'example.conf')"
  [[ -n "$backup_copy" ]]
  assert_equal "user-edited content" "$(cat "$backup_copy")"
  assert_file_contains "$TEST_ROOT/commands.log" "user:file-user:cp -a $destination"
}

@test "backup_user_file_if_needed fails with the backup cause when the backup directory cannot be created" {
  DRY_RUN=0
  TARGET_USER="file-user"
  destination="$TARGET_HOME/.config/example/example.conf"
  mkdir -p "$(dirname "$destination")"
  printf 'user content\n' >"$destination"
  run_cmd_as_user() {
    shift
    if [[ "$1" == "mkdir" ]]; then
      printf 'mkdir: cannot create directory: Permission denied\n' >&2
      return 1
    fi
    "$@"
  }

  run backup_user_file_if_needed "$destination"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not create backup directory"
  refute_contains "$output" "Backed up $destination"
  assert_equal "user content" "$(cat "$destination")"
}

@test "backup_user_file_if_needed fails with the backup cause when the copy fails" {
  DRY_RUN=0
  TARGET_USER="file-user"
  destination="$TARGET_HOME/.config/example/example.conf"
  mkdir -p "$(dirname "$destination")"
  printf 'user content\n' >"$destination"
  run_cmd_as_user() {
    shift
    if [[ "$1" == "cp" ]]; then
      printf 'cp: cannot create regular file: Permission denied\n' >&2
      return 1
    fi
    "$@"
  }

  run backup_user_file_if_needed "$destination"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not back up $destination"
  refute_contains "$output" "Backed up $destination"
}

@test "install_file_if_changed user does not overwrite the destination when the backup fails" {
  DRY_RUN=0
  TARGET_USER="file-user"
  source_file="$TEST_ROOT/source.conf"
  destination="$TARGET_HOME/.config/example/example.conf"
  printf 'managed content\n' >"$source_file"
  mkdir -p "$(dirname "$destination")"
  printf 'user-edited content\n' >"$destination"
  run_cmd_as_user() {
    shift
    if [[ "$1" == "mkdir" ]]; then
      printf 'mkdir: cannot create directory: Permission denied\n' >&2
      return 1
    fi
    "$@"
  }

  run install_file_if_changed user "$source_file" "$destination"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Could not create backup directory"
  assert_equal "user-edited content" "$(cat "$destination")"
}

@test "install_file_if_changed dry-run previews the install without writing" {
  DRY_RUN=1
  source_file="$TEST_ROOT/dry-source.conf"
  destination="$TARGET_HOME/.config/dry/dry.conf"
  printf 'managed content\n' >"$source_file"

  run install_file_if_changed user "$source_file" "$destination"

  [ "$status" -eq 0 ]
  assert_contains "$output" "DRY-RUN:"
  assert_contains "$output" "$destination"
  [[ ! -e "$destination" ]]
}

@test "install_file_if_changed rejects an unknown context" {
  printf 'content\n' >"$TEST_ROOT/context-source.conf"

  run install_file_if_changed nobody "$TEST_ROOT/context-source.conf" "$TARGET_HOME/context.conf"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Unsupported install context: nobody"
}

@test "write_root_file stages stdin and installs through the root context" {
  DRY_RUN=0
  destination="$TEST_ROOT/etc/example.repo"
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$TEST_ROOT/commands.log"
    "$@"
  }

  write_root_file 0644 "$destination" <<'EOF'
[example]
enabled=1
EOF

  assert_equal "$(printf '[example]\nenabled=1')" "$(cat "$destination")"
  assert_file_contains "$TEST_ROOT/commands.log" "root:install -D -m 0644"

  : >"$TEST_ROOT/commands.log"
  output="$(write_root_file 0644 "$destination" 2>&1 <<'EOF'
[example]
enabled=1
EOF
)"
  assert_contains "$output" "Unchanged file: $destination"
  [[ ! -s "$TEST_ROOT/commands.log" ]]
  [[ -z "$(find "$CACHE_DIR" -maxdepth 1 -name 'root-file.*' -print -quit)" ]]
}
