#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
}

@test "direct internal apply is rejected" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/install.sh" apply --dry-run --no-tui

  [ "$status" -ne 0 ]
  assert_contains "$output" "apply is internal"
}

@test "zz exposes post-install commands only" {
  run bash "$ROOT_DIR/bin/zz" --help
  [ "$status" -eq 0 ]
  refute_contains "$output" "zz wizard"
  refute_contains "$output" "zz install"
  refute_contains "$output" "zz plan"
  refute_contains "$output" "zz repair"
  assert_contains "$output" "zz logs"
  assert_contains "$output" "zz debug"
  assert_contains "$output" "zz first-run"
  assert_contains "$output" "zz defaults"
  assert_contains "$output" "zz dotnet"
  assert_contains "$output" "zz update"
  assert_contains "$output" "zz refresh"

  run bash "$ROOT_DIR/bin/zz" commands --json
  [ "$status" -eq 0 ]
  [[ "${output:0:1}" == "[" ]]
  refute_contains "$output" '"name":"wizard"'
  refute_contains "$output" '"name":"install"'
  refute_contains "$output" '"name":"plan"'
  assert_contains "$output" '"name":"dotnet"'
  assert_contains "$output" '"name":"first-run"'
  assert_contains "$output" '"name":"defaults"'
  assert_contains "$output" '"name":"update"'
  assert_contains "$output" '"name":"refresh"'
  assert_contains "$output" '"usage":"zz dotnet <devcert> [options]"'
  assert_contains "$output" '"usage":"zz doctor [options]"'
  assert_contains "$output" '"usage":"zz refresh <config-path> | zz refresh --list"'
}

@test "zz resolves subcommands through a symlinked launcher and rejects unknown commands" {
  mkdir -p "$TEST_ROOT/home/.local/bin"
  ln -sfn "$ROOT_DIR/bin/zz" "$TEST_ROOT/home/.local/bin/zz"

  run "$TEST_ROOT/home/.local/bin/zz" commands --json
  [ "$status" -eq 0 ]
  assert_contains "$output" '"name":"doctor"'
  assert_contains "$output" '"name":"logs"'

  run bash "$ROOT_DIR/bin/zz" does-not-exist
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown zz command: does-not-exist"
}

@test "zz logs prints and tails the latest install log" {
  mkdir -p "$LOG_DIR"
  printf 'test log\n' >"$LOG_DIR/example.log"
  ln -sfn "$LOG_DIR/example.log" "$LOG_DIR/latest.log"

  run bash "$ROOT_DIR/bin/zz" logs
  [ "$status" -eq 0 ]
  assert_equal "$LOG_DIR/example.log" "$output"

  run bash "$ROOT_DIR/bin/zz" logs --tail --lines 1
  [ "$status" -eq 0 ]
  assert_contains "$output" "test log"
}

@test "zz debug collects a sanitized support bundle with a manifest" {
  debug_bundle="$(bash "$ROOT_DIR/bin/zz" debug)"

  [[ -f "$debug_bundle" ]]
  tar -tzf "$debug_bundle" | grep -F './manifest.txt' >/dev/null
}

@test "privileged module and lib commands use the scoped run_cmd helpers" {
  violations="$(grep -RInE '(^|[[:space:]])(run_cmd[[:space:]]+sudo|sudo[[:space:]]+)(dnf|systemctl|chsh|rpm|usermod|python3|install|cp|tee|awk)\b' \
    "$ROOT_DIR/modules" "$ROOT_DIR/lib" \
    | grep -Fv 'lib/idempotency.sh' \
    | grep -Fv 'DRY-RUN:' \
    || true)"

  if [[ -n "$violations" ]]; then
    printf 'raw privileged commands must use run_cmd_as_root or run_cmd_as_user:\n%s\n' "$violations" >&2
    return 1
  fi
}

@test "install rejects unknown commands by name with usage" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/install.sh" bogus-command --dry-run --no-tui

  [ "$status" -eq 1 ]
  assert_contains "$output" "Unknown command: 'bogus-command'"
  assert_contains "$output" "Usage:"
}

@test "install help is generated from the command catalog" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/install.sh" --help

  [ "$status" -eq 0 ]
  assert_contains "$output" "[wizard|install|check|doctor|first-run|defaults|print-plan|list-profiles|list-choices|list-sources] [options]"
  assert_contains "$output" "--update"
  local command_name
  for command_name in wizard install check doctor first-run defaults print-plan list-profiles list-choices list-sources; do
    grep -E "^  ${command_name}[[:space:]]" <<<"$output" >/dev/null || {
      printf 'usage does not describe command: %s\n' "$command_name" >&2
      return 1
    }
  done
  if grep -E '^  apply[[:space:]]|\|apply[|\]]' <<<"$output" >/dev/null; then
    printf 'internal apply command must stay hidden from usage\n' >&2
    return 1
  fi
}

@test "install list-profiles exposes desktop app profiles" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/install.sh" list-profiles --dry-run --no-tui

  [ "$status" -eq 0 ]
  assert_contains "$output" "base"
  assert_contains "$output" "desktop-app:auto"
  assert_contains "$output" "desktop-app:full"
  assert_contains "$output" "desktop-app:minimal"
}

@test "print-plan fails fast when the catalog references an unregistered action" {
  local repo_copy="$TEST_ROOT/repo-copy"
  mkdir -p "$repo_copy/assets/wallpapers"
  # Copy the working tree, not HEAD, so uncommitted catalog and action work is
  # exercised too: untracked-but-not-ignored files are included, and files
  # deleted from the working tree are dropped even while still in the index.
  git -C "$ROOT_DIR" ls-files -z --cached --others --exclude-standard -- . ':!assets' \
    | while IFS= read -r -d '' path; do
      [[ -e "$ROOT_DIR/$path" ]] && printf '%s\0' "$path"
    done \
    | tar --null -cf - -C "$ROOT_DIR" -T - \
    | tar -xf - -C "$repo_copy"
  printf '\n[[install]]\nbackend = "action"\nactions = ["not-a-registered-action"]\n' \
    >>"$repo_copy/catalog/units/media/codecs.toml"

  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$repo_copy/install.sh" print-plan --dry-run --skip-user-config --no-tui

  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown custom action 'not-a-registered-action'"
  assert_contains "$output" "no register_action row declares it"
}

run_post_install_command() {
  env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/install.sh" "$1" --dry-run --no-tui
}

@test "first-run and defaults dry-runs take and release the installer lock" {
  local lock_file="$XDG_STATE_HOME/zz-fedora/install.lock"
  local command_name
  for command_name in first-run defaults; do
    run run_post_install_command "$command_name"
    [ "$status" -eq 0 ]
    [[ -f "$lock_file" ]]
    flock -n "$lock_file" true
  done
}

@test "first-run and defaults refuse to run while the installer lock is held" {
  local lock_file="$XDG_STATE_HOME/zz-fedora/install.lock"
  local held_marker="$TEST_ROOT/lock-held"
  mkdir -p "$(dirname "$lock_file")"

  (
    exec {lock_fd}>"$lock_file"
    flock "$lock_fd"
    : >"$held_marker"
    # exec so the lock fd owner is the pid killed below.
    exec sleep 60
  ) >/dev/null 2>&1 3>&- &
  local holder_pid=$!
  local attempts=0
  until [[ -f "$held_marker" ]]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ]
    sleep 0.1
  done

  local command_name
  for command_name in defaults first-run; do
    run run_post_install_command "$command_name"
    [ "$status" -ne 0 ]
    assert_contains "$output" "Another zz-fedora process is running"
  done

  kill "$holder_pid"
  wait "$holder_pid" 2>/dev/null || true
  flock -n "$lock_file" true
}
