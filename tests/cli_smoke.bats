#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
}

@test "print-plan JSON emits machine-readable plan without log prefix" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/install.sh" print-plan --dry-run --skip-user-config --format json

  [ "$status" -eq 0 ]
  [[ "${output:0:1}" == "{" ]]
  assert_contains "$output" '"project":"ZZ Fedora"'
  assert_contains "$output" '"platform":"fedora"'
  assert_contains "$output" '"selected_bundles":'
  assert_contains "$output" '"source_details":'
  assert_contains "$output" '"native_packages":'
  assert_contains "$output" '"config_components":'
  assert_contains "$output" '"base_rationale":'
  assert_contains "$output" '"bats"'
  assert_contains "$output" '"dnf5-plugins"'
  assert_contains "$output" '"niri"'
  assert_contains "$output" '"noctalia-greeter"'
  assert_contains "$output" '"noctalia"'
  assert_contains "$output" '"copr:lionheartp/Hyprland"'
  assert_contains "$output" '"browsers-firefox"'
  assert_contains "$output" '"code"'
  assert_contains "$output" '"artifact:discord"'
  assert_contains "$output" '"discord"'
  refute_contains "$output" '"browsers-chromium"'
  refute_contains "$output" '"browsers-chrome"'
  refute_contains "$output" '"browsers-brave"'
  refute_contains "$output" '"browsers-zen-copr"'
  refute_contains "$output" '"browsers-helium-copr"'
  refute_contains "$output" "Log file:"
  [[ ! -e "$XDG_CONFIG_HOME/zz-fedora/selections.conf" ]]
}
