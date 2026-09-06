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
  # Enabling Terra must leave the repository's shipped package and metadata
  # signature verification untouched.
  [[ "$output" != *"repo_gpgcheck="* ]]
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

@test "COPR enablement is skipped when dnf lists the exact enabled repo id" {
  DRY_RUN=0
  dnf() {
    [[ "$*" == "repolist --enabled" ]] || return 1
    printf '%s\n' \
      'repo id repo name' \
      'copr:copr.fedorainfracloud.org:atim:starship Copr repo for starship owned by atim' \
      'fedora Fedora 44 - x86_64'
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
  }
  rpm() {
    [[ "$*" == "-E %fedora" ]] && printf '%s\n' "$MINIMUM_FEDORA_RELEASE"
  }

  run fedora_enable_sources "copr:atim/starship"

  [ "$status" -eq 0 ]
  refute_contains "$output" "dnf copr enable"
}

@test "COPR enablement runs when dnf lists no enabled repo for the project" {
  DRY_RUN=0
  dnf() {
    [[ "$*" == "repolist --enabled" ]] || return 1
    printf '%s\n' \
      'repo id repo name' \
      'fedora Fedora 44 - x86_64' \
      'updates Fedora 44 - x86_64 - Updates'
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
  }
  rpm() {
    [[ "$*" == "-E %fedora" ]] && printf '%s\n' "$MINIMUM_FEDORA_RELEASE"
  }

  run fedora_enable_sources "copr:atim/starship"

  [ "$status" -eq 0 ]
  assert_contains "$output" "root:dnf copr enable -y atim/starship"
}

@test "COPR repo id that only shares a prefix does not count as enabled" {
  dnf() {
    [[ "$*" == "repolist --enabled" ]] || return 1
    printf '%s\n' \
      'repo id repo name' \
      'copr:copr.fedorainfracloud.org:atim:starship-git Copr repo for starship-git owned by atim' \
      'coprdep:copr.fedorainfracloud.org:atim:starship dependency alias'
  }

  run fedora_repo_enabled "copr:atim/starship"

  [ "$status" -ne 0 ]
}

@test "dnf5 repolist header row never matches a COPR repo id" {
  dnf() {
    [[ "$*" == "repolist --enabled" ]] || return 1
    printf '%s\n' 'repo id repo name'
  }

  run fedora_repo_enabled "copr:atim/starship"

  [ "$status" -ne 0 ]
}
