#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "Terra source excludes the Noctalia Greeter package provider" {
  DRY_RUN=0
  fedora_repo_enabled() {
    return 0
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
  }
  rpm() {
    [[ "$*" == "-E %fedora" ]] && printf '44\n'
  }

  run fedora_enable_sources terra

  [ "$status" -eq 0 ]
  assert_contains "$output" "root:dnf config-manager setopt terra.repo_gpgcheck=0"
  assert_contains "$output" "root:dnf config-manager setopt terra.excludepkgs=noctalia-greeter"
}
