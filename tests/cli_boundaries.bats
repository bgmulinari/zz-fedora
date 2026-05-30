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
  assert_contains "$output" "zz logs"
  assert_contains "$output" "zz debug"
  assert_contains "$output" "zz first-run"
  assert_contains "$output" "zz defaults"
  assert_contains "$output" "zz update"

  run bash "$ROOT_DIR/bin/zz" commands --json
  [ "$status" -eq 0 ]
  [[ "${output:0:1}" == "[" ]]
  refute_contains "$output" '"name":"wizard"'
  refute_contains "$output" '"name":"install"'
  refute_contains "$output" '"name":"plan"'
  assert_contains "$output" '"name":"first-run"'
  assert_contains "$output" '"name":"update"'
  assert_contains "$output" '"usage":"zz doctor [options]"'
}
