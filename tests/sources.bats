#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "required source failure aborts sources module before optional sources" {
  source_list="$TEST_ROOT/required-source-failure.list"
  printf 'required-source\noptional-source\n' >"$source_list"
  source_plan_files() {
    printf '%s\n' "$source_list"
  }
  source_required_for_install() {
    [[ "$1" == "required-source" ]]
  }
  fedora_enable_sources() {
    printf 'enable:%s\n' "$1"
    return 1
  }
  enable_source_best_effort() {
    printf 'optional:%s\n' "$1"
  }

  run module_10_sources

  [ "$status" -ne 0 ]
  assert_contains "$output" "enable:required-source"
  refute_contains "$output" "optional:optional-source"
}

@test "update mode enables required sources and skips optional sources" {
  source_list="$TEST_ROOT/update-sources.list"
  printf 'required-source\noptional-source\n' >"$source_list"
  source_plan_files() {
    printf '%s\n' "$source_list"
  }
  source_required_for_install() {
    [[ "$1" == "required-source" ]]
  }
  fedora_enable_sources() {
    printf 'enable:%s\n' "$1"
  }
  UPDATE_MODE=1

  run module_10_sources

  [ "$status" -eq 0 ]
  assert_contains "$output" "enable:required-source"
  assert_contains "$output" "Skipping optional software sources in update mode"
  refute_contains "$output" "enable:optional-source"
}

@test "Fedora vendor and RPM Fusion source setup imports keys before repo installs" {
  DRY_RUN=0
  fedora_repo_enabled() {
    return 1
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
  }
  rpm() {
    [[ "$*" == "-E %fedora" ]] && printf '%s\n' "$MINIMUM_FEDORA_RELEASE"
  }

  set +e
  output="$({
    fedora_enable_sources vendor:google-chrome
    fedora_enable_sources rpmfusion-free
    fedora_enable_sources rpmfusion-nonfree
  } 2>&1)"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  assert_contains "$output" "root:bash -c rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null"
  assert_contains "$output" "root:rpm --import https://download1.rpmfusion.org/free/fedora/RPM-GPG-KEY-rpmfusion-free-fedora-2020"
  assert_contains "$output" "root:dnf install -y --setopt=localpkg_gpgcheck=1 https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${MINIMUM_FEDORA_RELEASE}.noarch.rpm"
  assert_contains "$output" "root:rpm --import https://download1.rpmfusion.org/nonfree/fedora/RPM-GPG-KEY-rpmfusion-nonfree-fedora-2020"
  assert_contains "$output" "root:dnf install -y --setopt=localpkg_gpgcheck=1 https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${MINIMUM_FEDORA_RELEASE}.noarch.rpm"
}

@test "Claude Desktop preflight uses an ephemeral signed repository" {
  dnf() {
    printf '%s\n' "$*"
  }

  run claude_desktop_repository_package_metadata

  [ "$status" -eq 0 ]
  assert_contains "$output" "--assumeyes"
  assert_contains "$output" '--repofrompath=claude-desktop-unofficial-preflight,https://pkg.claude-desktop-debian.dev/rpm/$basearch'
  assert_contains "$output" "--setopt=claude-desktop-unofficial-preflight.repo_gpgcheck=1"
  assert_contains "$output" "--repo=claude-desktop-unofficial-preflight"
  assert_contains "$output" "claude-desktop-unofficial.x86_64"
}

@test "Claude Desktop repository accepts the exact package identity" {
  DRY_RUN=0
  claude_desktop_repository_package_metadata() {
    printf 'claude-desktop-unofficial|x86_64|1.19367.0|3.2.1.fc42|claude-desktop-unofficial-1.19367.0-3.2.1.fc42.src.rpm\n'
  }

  run verify_claude_desktop_repository_package x86_64

  [ "$status" -eq 0 ]
  assert_contains "$output" "Verified exact Claude Desktop repository package: claude-desktop-unofficial-1.19367.0-3.2.1.fc42.x86_64"
}

@test "Claude Desktop repository rejects the wrong architecture" {
  DRY_RUN=0

  run verify_claude_desktop_repository_package aarch64

  [ "$status" -ne 0 ]
  assert_contains "$output" "requires x86_64; detected aarch64"
}

@test "Claude Desktop repository rejects an unexpected RPM identity" {
  DRY_RUN=0
  claude_desktop_repository_package_metadata() {
    printf '%s\n' "$CLAUDE_TEST_METADATA"
  }

  CLAUDE_TEST_METADATA='claude-desktop|x86_64|1.19367.0|3.2.1.fc42|claude-desktop-1.19367.0-3.2.1.fc42.src.rpm'
  run verify_claude_desktop_repository_package x86_64

  [ "$status" -ne 0 ]
  assert_contains "$output" "unexpected package identity"

  CLAUDE_TEST_METADATA='claude-desktop-unofficial|x86_64|1.19367.0|3.2.1.fc45|claude-desktop-unofficial-1.19367.0-3.2.1.fc45.src.rpm'
  run verify_claude_desktop_repository_package x86_64

  [ "$status" -eq 0 ]
  assert_contains "$output" "claude-desktop-unofficial-1.19367.0-3.2.1.fc45.x86_64"
}

@test "Claude Desktop repository is not activated when preflight fails" {
  DRY_RUN=0
  command_log="$TEST_ROOT/claude-source-commands.log"
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
  }
  claude_desktop_repository_package_metadata() {
    printf 'claude-desktop-unofficial|x86_64|1.19367.0|3.2.1.fc42|unexpected-source-1.19367.0-3.2.1.fc42.src.rpm\n'
  }

  run configure_claude_desktop_repository

  [ "$status" -ne 0 ]
  assert_file_contains "$command_log" "rpm --import https://pkg.claude-desktop-debian.dev/KEY.gpg"
  assert_file_contains "$command_log" "rm -f /etc/yum.repos.d/claude-desktop-unofficial.repo"
  refute_contains "$(<"$command_log")" "install -Dm0644"
}
