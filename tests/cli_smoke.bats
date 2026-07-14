#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
}

@test "print-plan JSON emits machine-readable plan without log prefix" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/install.sh" print-plan --dry-run --skip-dotfiles --format json

  [ "$status" -eq 0 ]
  [[ "${output:0:1}" == "{" ]]
  assert_contains "$output" '"project":"ZZ Fedora"'
  assert_contains "$output" '"platform":"fedora"'
  assert_contains "$output" '"selected_bundles":'
  assert_contains "$output" '"source_details":'
  assert_contains "$output" '"native_packages":'
  assert_contains "$output" '"base_rationale":'
  assert_contains "$output" '"bats"'
  assert_contains "$output" '"dnf5-plugins"'
  assert_contains "$output" '"niri"'
  assert_contains "$output" '"noctalia-greeter"'
  assert_contains "$output" '"noctalia-v5"'
  assert_contains "$output" '"copr:lionheartp/Hyprland"'
  assert_contains "$output" '"browser-firefox"'
  assert_contains "$output" '"code"'
  assert_contains "$output" '"com.discordapp.Discord"'
  refute_contains "$output" '"browser-chromium"'
  refute_contains "$output" '"browser-chrome"'
  refute_contains "$output" '"browser-brave"'
  refute_contains "$output" '"browser-zen-copr"'
  refute_contains "$output" '"browser-helium-copr"'
  refute_contains "$output" "Log file:"
  [[ ! -e "$XDG_CONFIG_HOME/zz-fedora/selections.conf" ]]
}
