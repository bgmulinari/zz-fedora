#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  FAKE_BIN="$TEST_ROOT/fake-bin"
  COMMAND_LOG="$TEST_ROOT/update-commands.log"
  mkdir -p "$FAKE_BIN"
}

make_fake_command() {
  local name="$1"
  local exit_code="${2:-0}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '\''%s %%s\\n'\'' "$*" >>%q\n' "$name" "$COMMAND_LOG"
    printf 'exit %s\n' "$exit_code"
  } >"$FAKE_BIN/$name"
  chmod +x "$FAKE_BIN/$name"
}

make_fake_sudo_passthrough() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '\''sudo %%s\\n'\'' "$*" >>%q\n' "$COMMAND_LOG"
    printf 'if [[ "${1:-}" == "-v" ]]; then exit 0; fi\n'
    printf 'if [[ "${1:-}" == "-n" ]]; then shift; fi\n'
    printf 'if [[ "${1:-}" == "env" ]]; then shift; exec env "$@"; fi\n'
    printf 'exec "$@"\n'
  } >"$FAKE_BIN/sudo"
  chmod +x "$FAKE_BIN/sudo"
}

@test "zz update exposes target help" {
  run bash "$ROOT_DIR/bin/zz" update --help

  [ "$status" -eq 0 ]
  assert_contains "$output" "zz update <target>"
  assert_contains "$output" "dotnet-tools"
  assert_contains "$output" "--dry-run"
  refute_contains "$output" "--reboot"
}

@test "zz update all dry-run plans supported updater commands" {
  local command_name
  for command_name in dnf flatpak brew npm dotnet claude; do
    make_fake_command "$command_name"
  done
  local dotnet_dir="$TEST_ROOT/dotnet"
  mkdir -p "$dotnet_dir"
  touch "$dotnet_dir/dotnet"
  chmod +x "$dotnet_dir/dotnet"

  run env PATH="$FAKE_BIN:$PATH" DOTNET_INSTALL_DIR="$dotnet_dir" \
    bash "$ROOT_DIR/bin/zz" update all --dry-run

  [ "$status" -eq 0 ]
  assert_contains "$output" "==> DNF"
  assert_contains "$output" "DRY-RUN: sudo $FAKE_BIN/dnf upgrade -y --refresh --offline"
  assert_contains "$output" "DRY-RUN: sudo $FAKE_BIN/flatpak update -y"
  assert_contains "$output" "DRY-RUN: $FAKE_BIN/brew update"
  assert_contains "$output" "DRY-RUN: sudo $FAKE_BIN/npm update -g"
  assert_contains "$output" "DRY-RUN: install active .NET SDK channels"
  assert_contains "$output" "DRY-RUN: update installed .NET global tools"
  assert_contains "$output" "DRY-RUN: $FAKE_BIN/claude update"
  assert_contains "$output" "==> Cleanup"
  assert_contains "$output" "Update complete."
  assert_contains "$output" "- dnf:"
  assert_contains "$output" "- flatpak:"
  [[ ! -e "$COMMAND_LOG" ]]
}

@test "zz update direct target executes only that updater" {
  make_fake_command flatpak
  make_fake_command npm
  make_fake_sudo_passthrough

  run env PATH="$FAKE_BIN:$PATH" ZZ_UPDATE_ROOT_CONTEXT=1 bash "$ROOT_DIR/bin/zz" update flatpak

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "sudo -n $FAKE_BIN/flatpak update -y"
  refute_file_contains "$COMMAND_LOG" "npm update"
}

@test "zz update all aggregates target failures and keeps going" {
  make_fake_command dnf
  make_fake_command dnf5
  make_fake_command brew
  make_fake_command npm
  make_fake_command claude
  make_fake_sudo_passthrough

  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '\''flatpak %%s\\n'\'' "$*" >>%q\n' "$COMMAND_LOG"
    printf 'printf '\'' 1. [✗] com.discordapp.Discord stable u flathub 109 MB / 223 MB\\n'\''\n'
    printf 'exit 23\n'
  } >"$FAKE_BIN/flatpak"
  chmod +x "$FAKE_BIN/flatpak"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '\''dotnet %%s\\n'\'' "$*" >>%q\n' "$COMMAND_LOG"
    printf 'if [[ "$1 $2 $3" == "tool list -g" ]]; then\n'
    printf '  printf '\''Package Id      Version      Commands\\n'\''\n'
    printf '  printf '\''-------------------------------------\\n'\''\n'
    printf '  printf '\''csharp-ls       1.0.0        csharp-ls\\n'\''\n'
    printf 'fi\n'
  } >"$FAKE_BIN/dotnet"
  chmod +x "$FAKE_BIN/dotnet"

  run env PATH="$FAKE_BIN:$PATH" DOTNET_INSTALL_DIR="$TEST_ROOT/missing-dotnet" ZZ_UPDATE_ROOT_CONTEXT=1 \
    bash "$ROOT_DIR/bin/zz" update all --no-cleanup

  [ "$status" -ne 0 ]
  assert_contains "$output" "Update complete."
  assert_contains "$output" "- dnf:"
  assert_contains "$output" "offline transaction prepared; will be applied on the next boot"
  assert_contains "$output" "- flatpak:"
  assert_contains "$output" "1 update failed (com.discordapp.Discord)"
  assert_contains "$output" "[failed]"
  assert_contains "$output" "DNF offline upgrade will be applied when you next reboot normally."
  assert_file_contains "$COMMAND_LOG" "sudo -n $FAKE_BIN/flatpak update -y"
  assert_file_contains "$COMMAND_LOG" "sudo -n env DNF_SYSTEM_UPGRADE_NO_REBOOT=1 dnf5 -y offline reboot"
  assert_file_contains "$COMMAND_LOG" "brew update"
  assert_file_contains "$COMMAND_LOG" "claude update"
}

@test "zz update dnf schedules offline upgrade for next normal reboot" {
  make_fake_command dnf
  make_fake_command dnf5
  make_fake_sudo_passthrough

  run env PATH="$FAKE_BIN:$PATH" ZZ_UPDATE_ROOT_CONTEXT=1 bash "$ROOT_DIR/bin/zz" update dnf

  [ "$status" -eq 0 ]
  assert_contains "$output" "Update complete."
  assert_contains "$output" "offline transaction prepared; will be applied on the next boot"
  assert_contains "$output" "DNF offline upgrade will be applied when you next reboot normally."
  assert_file_contains "$COMMAND_LOG" "sudo -n $FAKE_BIN/dnf upgrade -y --refresh --offline"
  assert_file_contains "$COMMAND_LOG" "sudo -n env DNF_SYSTEM_UPGRADE_NO_REBOOT=1 dnf5 -y offline reboot"
  refute_file_contains "$COMMAND_LOG" "systemctl reboot"
}

@test "zz update validates sudo once and re-execs privileged targets as root" {
  make_fake_sudo_passthrough
  make_fake_command dnf
  make_fake_command dnf5

  run env PATH="$FAKE_BIN:$PATH" bash "$ROOT_DIR/bin/zz" update dnf --dry-run
  [ "$status" -eq 0 ]
  [[ ! -e "$COMMAND_LOG" ]] || refute_file_contains "$COMMAND_LOG" "sudo -v"

  : >"$COMMAND_LOG"
  run env PATH="$FAKE_BIN:$PATH" bash "$ROOT_DIR/bin/zz" update dnf

  [ "$status" -eq 0 ]
  assert_contains "$output" "Root privileges are required for zz update dnf"
  assert_file_contains "$COMMAND_LOG" "sudo -v"
  assert_file_contains "$COMMAND_LOG" "sudo env ZZ_UPDATE_RUN_USER="
  assert_file_contains "$COMMAND_LOG" "sudo -n $FAKE_BIN/dnf upgrade -y --refresh --offline"
}
