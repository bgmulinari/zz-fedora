#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "Terra source cannot replace the DMS stack from the DankLinux COPRs" {
  DRY_RUN=0
  fedora_repo_enabled() {
    return 0
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
  }
  rpm() {
    [[ "$*" == "-E %fedora" ]] && printf '%s\n' "$MINIMUM_FEDORA_RELEASE"
  }

  run fedora_enable_sources terra

  [ "$status" -eq 0 ]
  assert_contains "$output" "root:dnf config-manager setopt terra.repo_gpgcheck=0"
  assert_contains "$output" "root:dnf config-manager setopt terra.excludepkgs=quickshell,quickshell-git,noctalia-qs,matugen,dgop,danksearch,dms,dms-cli,dms-greeter"
}

@test "DankLinux COPR and dependency aliases cannot replace Terra Ghostty" {
  DRY_RUN=0
  fedora_repo_enabled() {
    return 1
  }
  dnf() {
    [[ "$*" == "repolist --enabled" ]] || return 1
    printf '%s\n' \
      'repo id repo name' \
      'copr:copr.fedorainfracloud.org:avengemedia:danklinux direct' \
      'coprdep:copr.fedorainfracloud.org:avengemedia:danklinux dependency' \
      'coprdep:copr.fedorainfracloud.org:someone:else unrelated'
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
  }
  rpm() {
    [[ "$*" == "-E %fedora" ]] && printf '%s\n' "$MINIMUM_FEDORA_RELEASE"
  }

  run fedora_enable_sources "copr:avengemedia/danklinux"

  [ "$status" -eq 0 ]
  assert_contains "$output" "root:dnf copr enable -y avengemedia/danklinux"
  assert_contains "$output" "root:dnf config-manager setopt copr:copr.fedorainfracloud.org:avengemedia:danklinux.excludepkgs=ghostty,ghostty-shell-integration,ghostty-nautilus"
  assert_contains "$output" "root:dnf config-manager setopt coprdep:copr.fedorainfracloud.org:avengemedia:danklinux.excludepkgs=ghostty,ghostty-shell-integration,ghostty-nautilus"
  refute_contains "$output" "someone:else.excludepkgs"
}

@test "DMS COPR enables without extra repository options" {
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

  run fedora_enable_sources "copr:avengemedia/dms"

  [ "$status" -eq 0 ]
  assert_contains "$output" "root:dnf copr enable -y avengemedia/dms"
  refute_contains "$output" "excludepkgs"
}
