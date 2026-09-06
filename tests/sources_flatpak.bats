#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "Flatpak install aborts when required remote bootstrap fails" {
  flatpak_remote_add_if_missing() {
    printf 'remote-bootstrap\n'
    return 1
  }
  flatpak_install_or_update() {
    printf 'install:%s\n' "$1"
  }

  run fedora_install_flatpaks com.discordapp.Discord org.onlyoffice.desktopeditors

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

@test "Flathub install retries once after importing the GPG key on signature failure" {
  install_attempts=0
  flatpak_remote_import_flathub_key() {
    printf 'import-key:%s\n' "$1"
  }
  # The install output is captured into the detail log, so record every
  # attempt in a side file instead of relying on stdout/stderr.
  local attempts_file="$TEST_ROOT/flatpak-attempts"
  run_cmd_as_root() {
    [[ "$*" == "flatpak install -y --or-update flathub com.spotify.Client" ]] || return 1
    install_attempts=$((install_attempts + 1))
    printf 'attempt:%s\n' "$install_attempts" >>"$attempts_file"
    if [[ "$install_attempts" -eq 1 ]]; then
      printf 'error: GPG: Unable to complete signature verification\n'
      return 1
    fi
    printf 'Installed com.spotify.Client\n'
  }
  DRY_RUN=0

  run flatpak_install_or_update com.spotify.Client flathub

  [ "$status" -eq 0 ]
  assert_contains "$output" "GPG: Unable to complete signature verification"
  assert_contains "$output" "Flatpak install from 'flathub' failed GPG verification; importing the Flathub GPG key directly."
  assert_contains "$output" "import-key:flathub"
  assert_contains "$output" "Flatpak install details for com.spotify.Client: $LOG_DIR/flatpak-com.spotify.Client-retry-"
  assert_equal $'attempt:1\nattempt:2' "$(cat "$attempts_file")"
}

@test "Flatpak GPG failure on a non-Flathub remote fails without a retry" {
  install_attempts=0
  flatpak_remote_import_flathub_key() {
    printf 'import-key:%s\n' "$1"
  }
  local attempts_file="$TEST_ROOT/flatpak-attempts"
  run_cmd_as_root() {
    install_attempts=$((install_attempts + 1))
    printf 'attempt:%s\n' "$install_attempts" >>"$attempts_file"
    printf 'error: GPG: Unable to complete signature verification\n'
    return 1
  }
  DRY_RUN=0

  run flatpak_install_or_update org.example.App custom-remote

  [ "$status" -ne 0 ]
  assert_contains "$output" "GPG: Unable to complete signature verification"
  refute_contains "$output" "import-key:"
  assert_equal "attempt:1" "$(cat "$attempts_file")"
}
