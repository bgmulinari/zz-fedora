#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
  DISTRO=fedora
  load_adapter
}

@test "required source failure aborts sources module before optional sources" {
  source_list="$TEST_ROOT/required-source-failure.list"
  printf 'required-source\noptional-source\n' >"$source_list"
  source_plan_files_for_distro() {
    printf '%s\n' "$source_list"
  }
  source_required_for_install() {
    [[ "$1" == "required-source" ]]
  }
  distro_enable_sources() {
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

@test "Flatpak install aborts when required remote bootstrap fails" {
  flatpak_remote_add_if_missing() {
    printf 'remote-bootstrap\n'
    return 1
  }
  flatpak_install_or_update() {
    printf 'install:%s\n' "$1"
  }

  run distro_install_flatpaks com.discordapp.Discord org.onlyoffice.desktopeditors

  [ "$status" -ne 0 ]
  assert_contains "$output" "remote-bootstrap"
  refute_contains "$output" "install:com.discordapp.Discord"
  refute_contains "$output" "install:org.onlyoffice.desktopeditors"
}

@test "Flatpak app install uses system installation, not user remote" {
  run_cmd_as_user() {
    printf 'user:%s:%s\n' "$1" "${*:2}"
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
  }
  TARGET_USER="test-user"
  DRY_RUN=1

  run flatpak_install_or_update com.spotify.Client flathub

  [ "$status" -eq 0 ]
  assert_contains "$output" "root:flatpak install -y --or-update flathub com.spotify.Client"
  refute_contains "$output" "user:test-user:flatpak --user install"
}

@test "Flathub setup removes Fedora remote and adds official system remote" {
  remote_fixed=0
  flatpak() {
    case "$1" in
      remotes)
        printf 'fedora\n'
        [[ "$remote_fixed" -eq 1 ]] && printf 'flathub\n'
        return 0
        ;;
      remote-ls)
        [[ "$remote_fixed" -eq 1 ]]
        ;;
      *)
        return 1
        ;;
    esac
  }
  run_cmd_as_user() {
    printf 'user:%s:%s\n' "$1" "${*:2}"
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
    if [[ "$*" == "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" ]]; then
      remote_fixed=1
    fi
  }
  TARGET_USER="test-user"
  DRY_RUN=0

  run flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  [ "$status" -eq 0 ]
  assert_contains "$output" "Removing Fedora Flatpak remote before configuring Flathub"
  assert_contains "$output" "root:flatpak remote-delete --force fedora"
  assert_contains "$output" "root:flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
  refute_contains "$output" "user:test-user:flatpak --user remote-add"
}

@test "unusable Flathub remote is repaired with GPG import and never no-gpg-verify" {
  remote_present=1
  remote_fixed=0
  mktemp() {
    printf '/tmp/flathub-test.gpg\n'
  }
  curl() {
    printf 'curl:%s\n' "$*" >&2
    [[ "$*" == "-fsSL https://flathub.org/repo/flathub.gpg -o /tmp/flathub-test.gpg" ]]
  }
  chmod() {
    printf 'chmod:%s\n' "$*" >&2
  }
  sleep() {
    :
  }
  flatpak() {
    case "$1" in
      remotes)
        [[ "$remote_present" -eq 1 ]] && printf 'flathub\n'
        ;;
      remote-ls)
        [[ "$remote_present" -eq 1 && "$remote_fixed" -eq 1 ]]
        ;;
      *)
        return 1
        ;;
    esac
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
    case "$*" in
      "flatpak remote-delete --force flathub")
        remote_present=0
        return 0
        ;;
      "flatpak remote-modify --gpg-verify --gpg-import=/tmp/flathub-test.gpg flathub")
        remote_fixed=1
        return 0
        ;;
    esac
    return 1
  }
  DRY_RUN=0

  run flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  [ "$status" -eq 0 ]
  assert_contains "$output" "Flatpak remote 'flathub' is present but unusable; importing the Flathub GPG key directly."
  assert_contains "$output" "curl:-fsSL https://flathub.org/repo/flathub.gpg -o /tmp/flathub-test.gpg"
  assert_contains "$output" "chmod:0644 /tmp/flathub-test.gpg"
  assert_contains "$output" "root:flatpak remote-modify --gpg-verify --gpg-import=/tmp/flathub-test.gpg flathub"
  refute_contains "$output" "--no-gpg-verify"
}

@test "Fedora vendor and RPM Fusion source setup imports keys before repo installs" {
  DISTRO=fedora
  DRY_RUN=0
  distro_repo_enabled() {
    return 1
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
  }
  rpm() {
    [[ "$*" == "-E %fedora" ]] && printf '44\n'
  }

  set +e
  output="$({
    distro_enable_sources vendor:google-chrome
    distro_enable_sources rpmfusion-free
    distro_enable_sources rpmfusion-nonfree
  } 2>&1)"
  status=$?
  set -e

  [ "$status" -eq 0 ]
  assert_contains "$output" "root:bash -c rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null"
  assert_contains "$output" "root:rpm --import https://download1.rpmfusion.org/free/fedora/RPM-GPG-KEY-rpmfusion-free-fedora-2020"
  assert_contains "$output" "root:dnf install -y --setopt=localpkg_gpgcheck=1 https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm"
  assert_contains "$output" "root:rpm --import https://download1.rpmfusion.org/nonfree/fedora/RPM-GPG-KEY-rpmfusion-nonfree-fedora-2020"
  assert_contains "$output" "root:dnf install -y --setopt=localpkg_gpgcheck=1 https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm"
}
