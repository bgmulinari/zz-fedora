#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-linux-setup-zz-cli.XXXXXX)"
DIRTY_SENTINEL="$ROOT_DIR/.zz-cli-dirty-test"
trap 'rm -rf "$TEST_ROOT"; rm -f "$DIRTY_SENTINEL"' EXIT

export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export LOG_DIR="$TEST_ROOT/logs"

help_output="$(bash "$ROOT_DIR/bin/zz" --help)"
! grep -F 'zz wizard' <<<"$help_output" >/dev/null
! grep -F 'zz install' <<<"$help_output" >/dev/null
! grep -F 'zz plan' <<<"$help_output" >/dev/null
grep -F 'zz logs' <<<"$help_output" >/dev/null
grep -F 'zz debug' <<<"$help_output" >/dev/null
grep -F 'zz first-run' <<<"$help_output" >/dev/null
grep -F 'zz defaults' <<<"$help_output" >/dev/null
grep -F 'zz dotnet' <<<"$help_output" >/dev/null
grep -F 'zz update' <<<"$help_output" >/dev/null
! grep -F 'zz repair' <<<"$help_output" >/dev/null

commands_json="$(bash "$ROOT_DIR/bin/zz" commands --json)"
[[ "${commands_json:0:1}" == "[" ]]
! grep -F '"name":"wizard"' <<<"$commands_json" >/dev/null
! grep -F '"name":"install"' <<<"$commands_json" >/dev/null
! grep -F '"name":"plan"' <<<"$commands_json" >/dev/null
grep -F '"name":"dotnet"' <<<"$commands_json" >/dev/null
grep -F '"name":"first-run"' <<<"$commands_json" >/dev/null
grep -F '"name":"defaults"' <<<"$commands_json" >/dev/null
grep -F '"name":"update"' <<<"$commands_json" >/dev/null
grep -F '"usage":"zz dotnet <devcert> [options]"' <<<"$commands_json" >/dev/null
grep -F '"usage":"zz doctor [options]"' <<<"$commands_json" >/dev/null

mkdir -p "$TEST_ROOT/home/.local/bin"
ln -sfn "$ROOT_DIR/bin/zz" "$TEST_ROOT/home/.local/bin/zz"
symlink_commands_json="$("$TEST_ROOT/home/.local/bin/zz" commands --json)"
grep -F '"name":"doctor"' <<<"$symlink_commands_json" >/dev/null
grep -F '"name":"logs"' <<<"$symlink_commands_json" >/dev/null

unknown_output="$(
  set +e
  bash "$ROOT_DIR/bin/zz" does-not-exist 2>&1
)" || true
grep -F 'Unknown zz command: does-not-exist' <<<"$unknown_output" >/dev/null

mkdir -p "$LOG_DIR"
printf 'test log\n' >"$LOG_DIR/example.log"
ln -sfn "$LOG_DIR/example.log" "$LOG_DIR/latest.log"
[[ "$(bash "$ROOT_DIR/bin/zz" logs)" == "$LOG_DIR/example.log" ]]
grep -F 'test log' < <(bash "$ROOT_DIR/bin/zz" logs --tail --lines 1) >/dev/null

debug_bundle="$(bash "$ROOT_DIR/bin/zz" debug)"
[[ -f "$debug_bundle" ]]
tar -tzf "$debug_bundle" | grep -F './manifest.txt' >/dev/null

printf 'zz cli ok\n'
