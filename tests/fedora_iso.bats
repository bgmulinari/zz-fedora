#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
}

@test "Fedora ISO builder embeds Kickstart and checkout with mkksiso" {
  fake_bin="$TEST_ROOT/bin"
  mkdir -p "$fake_bin"

  cat >"$fake_bin/rsync" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >>"$ZZ_TEST_RSYNC_LOG"
dest=${@: -1}
mkdir -p "$dest"
printf 'payload\n' >"$dest/payload-marker"
SH
  chmod +x "$fake_bin/rsync"

  cat >"$fake_bin/mkksiso" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
ks=
add=
skip=0
args=()
while (($# > 0)); do
  case "$1" in
    --ks)
      ks=$2
      shift 2
      ;;
    --add)
      add=$2
      shift 2
      ;;
    --skip-mkefiboot)
      skip=1
      shift
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done
input=${args[0]:-}
output=${args[1]:-}
[[ -f "$ks" ]]
[[ -d "$add" ]]
{
  printf 'ks=%s\n' "$ks"
  printf 'add=%s\n' "$add"
  if [[ -f "$add/payload-marker" ]]; then
    printf 'payload_marker=yes\n'
  else
    printf 'payload_marker=no\n'
  fi
  printf 'input=%s\n' "$input"
  printf 'output=%s\n' "$output"
  printf 'skip=%s\n' "$skip"
} >"$ZZ_TEST_MKKSISO_LOG"
printf 'mock iso\n' >"$output"
SH
  chmod +x "$fake_bin/mkksiso"

  input_iso="$TEST_ROOT/Fedora-Everything-netinst.iso"
  output_iso="$TEST_ROOT/zz-linux-setup-fedora.iso"
  touch "$input_iso"
  export ZZ_TEST_RSYNC_LOG="$TEST_ROOT/rsync.log"
  export ZZ_TEST_MKKSISO_LOG="$TEST_ROOT/mkksiso.log"

  run env PATH="$fake_bin:$PATH" "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" \
    --input "$input_iso" \
    --output "$output_iso"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Created $output_iso"
  assert_file_contains "$output_iso" "mock iso"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "ks=$ROOT_DIR/iso/fedora/zz-fedora.ks"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "input=$input_iso"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "skip=0"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "payload_marker=yes"
  refute_file_contains "$ZZ_TEST_RSYNC_LOG" "--exclude=.git/"
  assert_file_contains "$ZZ_TEST_RSYNC_LOG" "--exclude=downloads/"
  assert_file_contains "$ZZ_TEST_RSYNC_LOG" "--exclude=release/"
  assert_file_contains "$ZZ_TEST_RSYNC_LOG" "--exclude=test-artifacts/"
  assert_file_contains "$ZZ_TEST_RSYNC_LOG" "--exclude=*.iso"
}

@test "Fedora ISO builder forwards development skip-mkefiboot flag" {
  fake_bin="$TEST_ROOT/skip-bin"
  mkdir -p "$fake_bin"

  cat >"$fake_bin/rsync" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
dest=${@: -1}
mkdir -p "$dest"
SH
  chmod +x "$fake_bin/rsync"

  cat >"$fake_bin/mkksiso" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >"$ZZ_TEST_MKKSISO_LOG"
output=${@: -1}
printf 'mock iso\n' >"$output"
SH
  chmod +x "$fake_bin/mkksiso"

  input_iso="$TEST_ROOT/Fedora-Everything-netinst.iso"
  output_iso="$TEST_ROOT/zz-linux-setup-fedora.iso"
  touch "$input_iso"
  export ZZ_TEST_MKKSISO_LOG="$TEST_ROOT/mkksiso-skip.log"

  run env PATH="$fake_bin:$PATH" "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" \
    --input "$input_iso" \
    --output "$output_iso" \
    --skip-mkefiboot

  [ "$status" -eq 0 ]
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "--skip-mkefiboot"
}

@test "Fedora Kickstart preserves Anaconda decisions and runs normal installer path" {
  ks="$ROOT_DIR/iso/fedora/zz-fedora.ks"

  assert_file_contains "$ks" "network --bootproto=dhcp --activate"
  assert_file_contains "$ks" "firstboot --disable"
  assert_file_contains "$ks" "url --metalink=\"https://mirrors.fedoraproject.org/metalink?repo=fedora-\$releasever&arch=\$basearch\""
  assert_file_contains "$ks" "cp -a /run/install/repo/zz-linux-setup /mnt/sysimage/opt/zz-linux-setup"
  assert_file_contains "$ks" "target_repo_dir=\"\$target_home/zz-linux-setup\""
  assert_file_contains "$ks" "\"\$target_home/.local/share\""
  assert_file_contains "$ks" "chown -R \"\$target_user:\$target_group\""
  assert_file_contains "$ks" "export STATE_DIR=\"\$target_home/.local/state/zz-linux-setup\""
  assert_file_contains "$ks" "export ZZ_INSTALLER_DEFER_START_SERVICES=1"
  assert_file_contains "$ks" "export ZZ_INSTALLER_POST_TIMEOUT_SECONDS="
  assert_file_contains "$ks" "export ZZ_COMMAND_TIMEOUT_SECONDS="
  assert_file_contains "$ks" "unset DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP DESKTOP_SESSION"
  assert_file_contains "$ks" "source /etc/locale.conf"
  assert_file_contains "$ks" "LC_ALL=\"\$LANG\""
  assert_file_contains "$ks" "export LANG LC_ALL"
  assert_file_contains "$ks" "Starting bootstrap for %s"
  assert_file_contains "$ks" "timeout --foreground --kill-after=60s \"\$ZZ_INSTALLER_POST_TIMEOUT_SECONDS\""
  assert_file_contains "$ks" "Bootstrap failed with exit code %s"
  assert_file_contains "$ks" "Bootstrap completed for %s"
  assert_file_contains "$ks" "./install.sh install --yes --distro fedora --desktop-app-profile full --no-tui --target-user \"\$target_user\""
  refute_file_contains "$ks" "clearpart"
  refute_file_contains "$ks" "autopart"
  refute_file_contains "$ks" "rootpw"
}

@test "Fedora VM installer test defaults to ISO boot path" {
  script="$ROOT_DIR/scripts/test-fedora-installer-vm.sh"

  assert_file_contains "$script" "--boot-mode iso|direct|uefi"
  assert_file_contains "$script" "--installer-ui graphical|text"
  assert_file_contains "$script" "boot_mode=iso"
  assert_file_contains "$script" "installer_ui=graphical"
  assert_file_contains "$script" "iso|direct|uefi)"
  assert_file_contains "$script" "graphical|text)"
  assert_file_contains "$script" "qemu_args+=(-boot d)"
  assert_file_contains "$script" "display_args=(-display \"vnc=\$vnc_display\")"
  assert_file_contains "$script" "--cmdline \"console=ttyS0,115200n8 inst.cmdline\""
  assert_file_contains "$script" "direct_append+=\" console=ttyS0,115200n8 inst.cmdline\""
  assert_file_contains "$script" "timeout --foreground --kill-after=60s \"\$ZZ_INSTALLER_POST_TIMEOUT_SECONDS\""
  assert_file_contains "$script" "Bootstrap failed with exit code %s"
}

@test "Fedora install readiness treats planned artifacts as planned during install" {
  source_core
  source_modules
  DISTRO=fedora
  load_adapter
  build_fedora_plan
  COMMAND=install
  DRY_RUN=0

  generate_readiness_status

  status_file="$(readiness_file)"
  assert_file_contains "$status_file" $'package:dnf\tniri\tplanned\tinfo'
  assert_file_contains "$status_file" $'niri\tcommand:niri\tplanned\tinfo'
  assert_file_contains "$status_file" $'noctalia-v5\tcommand:noctalia\tplanned\tinfo'
  assert_file_contains "$status_file" $'portal\tcommand:xdg-desktop-portal\tplanned\tinfo'
  refute_file_contains "$status_file" $'niri\tcommand:niri\tmissing\tfatal'
}

@test "Fedora installer mode enables services without starting them in chroot" {
  source_core
  source_modules
  DISTRO=fedora
  load_adapter
  DRY_RUN=0
  ZZ_INSTALLER_DEFER_START_SERVICES=1
  run_cmd_as_root() {
    printf '%s\n' "$*"
  }

  run distro_enable_service_now NetworkManager

  [ "$status" -eq 0 ]
  assert_contains "$output" "systemctl enable NetworkManager"
  refute_contains "$output" "--now"
}
