#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "optional package transaction retries individually and continues" {
  plan_file="$TEST_ROOT/optional.pkgs"
  printf 'bad-package\ngood-package\n' >"$plan_file"
  install_attempts=()
  package_install_idempotent() {
    local backend="$1"
    shift
    install_attempts+=("$backend:$*")
    [[ " $* " != *" bad-package "* ]]
  }

  install_from_plan_file dnf "$plan_file" optional

  assert_equal "dnf:bad-package good-package" "${install_attempts[0]}"
  assert_equal "dnf:bad-package" "${install_attempts[1]}"
  assert_equal "dnf:good-package" "${install_attempts[2]}"
}
@test "optional package verification rejects a provider for an architecture-qualified RPM" {
  plan_file="$TEST_ROOT/optional-exact.pkgs"
  install_log="$TEST_ROOT/optional-exact-installs.log"
  rpm_log="$TEST_ROOT/optional-exact-rpm.log"
  printf 'claude-desktop-unofficial.x86_64\n' >"$plan_file"
  VERIFY_INSTALLS=1
  DRY_RUN=0
  package_install_idempotent() {
    printf '%s:%s\n' "$1" "$2" >>"$install_log"
  }
  rpm() {
    printf '%s\n' "$*" >>"$rpm_log"
    if [[ "$*" == "-q --whatprovides claude-desktop-unofficial.x86_64" ]]; then
      return 0
    fi
    return 1
  }

  run install_from_plan_file dnf "$plan_file" optional

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$install_log")" -eq 2 ]
  assert_contains "$output" "Optional packages missing after install: claude-desktop-unofficial.x86_64"
  assert_contains "$output" "Optional dnf package failed and will be skipped for now: claude-desktop-unofficial.x86_64"
  refute_contains "$(<"$rpm_log")" "--whatprovides"
}
@test "required package transaction aborts without optional retry loop" {
  plan_file="$TEST_ROOT/required.pkgs"
  printf 'bad-package\ngood-package\n' >"$plan_file"
  package_install_idempotent() {
    local backend="$1"
    shift
    printf 'install:%s:%s\n' "$backend" "$*"
    return 1
  }

  run install_from_plan_file dnf "$plan_file" required

  [ "$status" -ne 0 ]
  assert_contains "$output" "install:dnf:bad-package good-package"
  [ "$(grep -Fc 'install:dnf:' <<<"$output")" -eq 1 ]
}
@test "required install verification reports missing native packages" {
  plan_file="$TEST_ROOT/verify-native.pkgs"
  printf 'missing-native-package\n' >"$plan_file"
  VERIFY_INSTALLS=1
  DRY_RUN=0
  fedora_package_installed() {
    return 1
  }

  run verify_plan_entries dnf "$plan_file" "base packages" required

  [ "$status" -ne 0 ]
  assert_contains "$output" "Required base packages missing after install: missing-native-package"
}
@test "Fedora package verification accepts installed providers" {
  setup_fake_bin
  write_fake_command rpm <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-q" && "$2" == "nodejs" ]]; then
  exit 1
fi
if [[ "$1" == "-q" && "$2" == "--whatprovides" && "$3" == "nodejs" ]]; then
  printf 'nodejs22-22.22.2-3.fc99.x86_64\n'
  exit 0
fi
exit 1
EOF
  PATH="$FAKE_BIN:$PATH"

  run fedora_package_installed nodejs

  [ "$status" -eq 0 ]
}
@test "run_cmd_as_user preserves UTF-8 locale variables" {
  TARGET_USER="locale-user"
  TARGET_HOME="$TEST_ROOT/locale-home"
  mkdir -p "$TARGET_HOME"
  export LANG=C.UTF-8
  export LC_ALL=C

  id() {
    if [[ "${1:-}" == "-u" && "${2:-}" == "locale-user" ]]; then
      printf '1234\n'
      return 0
    fi
    command id "$@"
  }
  getent() {
    if [[ "${1:-}" == "passwd" && "${2:-}" == "locale-user" ]]; then
      printf 'locale-user:x:1234:1234::%s:/bin/bash\n' "$TARGET_HOME"
      return 0
    fi
    command getent "$@"
  }
  run_cmd() {
    printf '%s\n' "$*"
  }

  run run_cmd_as_user locale-user true

  [ "$status" -eq 0 ]
  assert_contains "$output" "LANG=C.UTF-8"
  assert_contains "$output" "LC_ALL=C.UTF-8"
}
@test "run_cmd honors opt-in command timeout" {
  DRY_RUN=0
  ZZ_COMMAND_TIMEOUT_SECONDS=7
  ZZ_COMMAND_TIMEOUT_KILL_AFTER=2s
  timeout() {
    printf 'timeout called:'
    printf ' %s' "$@"
    printf '\n'
    return 124
  }

  run run_cmd slow command

  [ "$status" -eq 124 ]
  assert_contains "$output" "timeout called: --foreground --kill-after=2s 7 slow command"
  assert_contains "$output" "Command timed out after 7s: slow command"
}
