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
