#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
}

@test "Fedora ISO builder embeds Kickstart, checkout, and Anaconda add-on with mkksiso" {
  fake_bin="$TEST_ROOT/bin"
  mkdir -p "$fake_bin"

  cat >"$fake_bin/rsync" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >>"$ZZ_TEST_RSYNC_LOG"
src=${@: -2:1}
dest=${@: -1}
mkdir -p "$dest"
if [[ "$src" == */anaconda-addon/ ]]; then
  mkdir -p "$dest/org_zz_linux_setup"
  printf 'addon\n' >"$dest/org_zz_linux_setup/__init__.py"
  mkdir -p "$dest/org_zz_linux_setup/service"
  printf 'service\n' >"$dest/org_zz_linux_setup/service/installation.py"
elif [[ "$src" == */choices/ ]]; then
  mkdir -p "$dest/fedora"
  printf 'firefox\tFirefox\t0\tbrowser-firefox\tFedora official Firefox\n' >"$dest/fedora/browsers.conf"
else
  printf 'payload\n' >"$dest/payload-marker"
fi
SH
  chmod +x "$fake_bin/rsync"

  cat >"$fake_bin/xorriso" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
dest=${@: -1}
mkdir -p "$(dirname "$dest")"
printf '0\n44\nx86_64\n' >"$dest"
SH
  chmod +x "$fake_bin/xorriso"

  cat >"$fake_bin/mkksiso" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
  ks=
  adds=()
  skip=0
  args=()
while (($# > 0)); do
  case "$1" in
    --ks)
      ks=$2
      shift 2
      ;;
    --add)
      adds+=("$2")
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
ks_has_release=no
if grep -F 'repo=fedora-44&arch=x86_64' "$ks" >/dev/null &&
  grep -F 'repo=updates-released-f44&arch=x86_64' "$ks" >/dev/null; then
  ks_has_release=yes
fi
payload_marker=no
product_img=no
addon_in_product=no
choices_in_product=no
config_in_product=no
service_task_in_product=no
dbus_conf_in_product=no
dbus_service_in_product=no
buildstamp_version_in_product=no
for add in "${adds[@]}"; do
  [[ -d "$add" ]]
  if [[ -f "$add/payload-marker" ]]; then
    payload_marker=yes
  fi
  if [[ -f "$add/product.img" ]]; then
    product_img=yes
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/addons/org_zz_linux_setup/__init__\.py$' >/dev/null; then
      addon_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/addons/org_zz_linux_setup/choices/fedora/browsers\.conf$' >/dev/null; then
      choices_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?etc/anaconda/conf\.d/100-zz-linux-setup\.conf$' >/dev/null; then
      config_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/addons/org_zz_linux_setup/service/installation\.py$' >/dev/null; then
      service_task_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/dbus/confs/org\.fedoraproject\.Anaconda\.Addons\.ZZLinuxSetup\.conf$' >/dev/null; then
      dbus_conf_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/dbus/services/org\.fedoraproject\.Anaconda\.Addons\.ZZLinuxSetup\.service$' >/dev/null; then
      dbus_service_in_product=yes
    fi
    buildstamp="$(gzip -dc "$add/product.img" | cpio -i --to-stdout --quiet '*buildstamp' 2>/dev/null || true)"
    if grep -Fx 'Product=ZZ Linux Setup' <<<"$buildstamp" >/dev/null &&
      grep -Fx 'Version=44' <<<"$buildstamp" >/dev/null; then
      buildstamp_version_in_product=yes
    fi
  fi
done
{
  printf 'ks=%s\n' "$ks"
  printf 'ks_has_release=%s\n' "$ks_has_release"
  printf 'add_count=%s\n' "${#adds[@]}"
  printf 'payload_marker=%s\n' "$payload_marker"
  printf 'product_img=%s\n' "$product_img"
  printf 'addon_in_product=%s\n' "$addon_in_product"
  printf 'choices_in_product=%s\n' "$choices_in_product"
  printf 'config_in_product=%s\n' "$config_in_product"
  printf 'service_task_in_product=%s\n' "$service_task_in_product"
  printf 'dbus_conf_in_product=%s\n' "$dbus_conf_in_product"
  printf 'dbus_service_in_product=%s\n' "$dbus_service_in_product"
  printf 'buildstamp_version_in_product=%s\n' "$buildstamp_version_in_product"
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
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "ks_has_release=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "add_count=2"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "input=$input_iso"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "skip=0"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "payload_marker=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "product_img=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "addon_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "choices_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "config_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "service_task_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "dbus_conf_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "dbus_service_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "buildstamp_version_in_product=yes"
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

  cat >"$fake_bin/xorriso" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
dest=${@: -1}
mkdir -p "$(dirname "$dest")"
printf '0\n44\nx86_64\n' >"$dest"
SH
  chmod +x "$fake_bin/xorriso"

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

@test "Fedora Kickstart preserves Anaconda decisions and delegates setup to add-on service" {
  ks="$ROOT_DIR/iso/fedora/zz-fedora.ks"

  assert_file_contains "$ks" "network --bootproto=dhcp --activate"
  assert_file_contains "$ks" "firstboot --disable"
  assert_file_contains "$ks" "url --metalink=\"https://mirrors.fedoraproject.org/metalink?repo=fedora-@FEDORA_RELEASE@&arch=@FEDORA_ARCH@\""
  assert_file_contains "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" "extract_fedora_iso_metadata"
  assert_file_contains "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" "render_kickstart_template"
  assert_file_contains "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" "addon_data_dir="
  assert_file_contains "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" "usr/share/anaconda/dbus/confs"
  assert_file_contains "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" "org.fedoraproject.Anaconda.Addons.ZZLinuxSetup.service"
  refute_file_contains "$ks" "%post"
  refute_file_contains "$ks" "zz-linux-setup-kickstart.log"
  refute_file_contains "$ks" "./install.sh install"
  refute_file_contains "$ks" "clearpart"
  refute_file_contains "$ks" "autopart"
  refute_file_contains "$ks" "rootpw"
}

@test "Fedora Anaconda add-on exposes always-enabled GUI and TUI selection spokes" {
  addon="$ROOT_DIR/iso/fedora/anaconda-addon/org_zz_linux_setup"

  assert_file_contains "$addon/constants.py" "ZZ_LINUX_SETUP_NAMESPACE"
  assert_file_contains "$addon/constants.py" '(*ADDONS_NAMESPACE, "ZZLinuxSetup")'
  assert_file_contains "$addon/constants.py" 'SELECTION_FILE = "/tmp/zz-linux-setup-install-selected"'
  assert_file_contains "$addon/constants.py" '"browsers"'
  assert_file_contains "$addon/service/__main__.py" "org_zz_linux_setup.service.zz_linux_setup"
  assert_file_contains "$addon/service/zz_linux_setup.py" "def install_with_tasks"
  assert_file_contains "$addon/service/zz_linux_setup.py" "ZZLinuxSetupInstallationTask"
  assert_file_contains "$addon/service/installation.py" "self.report_progress(message)"
  assert_file_contains "$addon/service/installation.py" "_report_process_line"
  assert_file_contains "$addon/service/installation.py" "DNF_TRANSACTION_RE"
  assert_file_contains "$addon/service/installation.py" "chroot"
  assert_file_contains "$addon/service/installation.py" "ZZ_INSTALL_PROGRESS_FILE"
  assert_file_contains "$addon/service/installation.py" "ZZ_INSTALLER_APPLY_RELEASE_UPDATES=1"
  assert_file_contains "$ROOT_DIR/iso/fedora/anaconda-addon-data/org.fedoraproject.Anaconda.Addons.ZZLinuxSetup.service" "start-module org_zz_linux_setup.service"
  assert_file_contains "$ROOT_DIR/iso/fedora/anaconda-addon-data/org.fedoraproject.Anaconda.Addons.ZZLinuxSetup.conf" "org.fedoraproject.Anaconda.Addons.ZZLinuxSetup"
  assert_file_contains "$addon/selection.py" "def read_categories"
  assert_file_contains "$addon/selection.py" "def default_selections"
  assert_file_contains "$addon/selection.py" "select.%s=%s"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.py" "class ZZLinuxSetupSpoke"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.py" "NormalSpoke"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.py" "from pyanaconda.ui.categories.software import SoftwareCategory"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.py" "category = SoftwareCategory"
  refute_file_contains "$addon/gui/spokes/zz_linux_setup.py" "ZZLinuxSetupCategory"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.py" "_build_category_rows"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.py" "_render_choices"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.py" "_update_preferred_browser_combo"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.py" "write_state(True"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.glade" "Optional categories"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.glade" "categoryListBox"
  assert_file_contains "$addon/gui/spokes/zz_linux_setup.glade" "choiceListBox"
  refute_file_contains "$addon/gui/spokes/zz_linux_setup.glade" "Install ZZ Linux Setup managed desktop"
  assert_file_contains "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" "org_zz_linux_setup/choices"
  assert_file_contains "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" "hidden_spokes ="
  assert_file_contains "$ROOT_DIR/scripts/build-fedora-installer-iso.sh" "SoftwareSelectionSpoke"
  assert_file_contains "$addon/tui/spokes/zz_linux_setup.py" "NormalTUISpoke"
  assert_file_contains "$addon/tui/spokes/zz_linux_setup.py" "from pyanaconda.ui.categories.software import SoftwareCategory"
  assert_file_contains "$addon/tui/spokes/zz_linux_setup.py" "category = SoftwareCategory"
  refute_file_contains "$addon/tui/spokes/zz_linux_setup.py" "ZZLinuxSetupCategory"
  assert_file_contains "$addon/tui/spokes/zz_linux_setup.py" "CheckboxWidget"
  assert_file_contains "$addon/tui/spokes/zz_linux_setup.py" "_toggle_choice"
  assert_file_contains "$addon/tui/spokes/zz_linux_setup.py" "write_state(True"
  refute_file_contains "$addon/tui/spokes/zz_linux_setup.py" "_toggle_selection"
}

@test "Fedora VM installer test defaults to ISO boot path" {
  script="$ROOT_DIR/scripts/test-fedora-installer-vm.sh"

  assert_file_contains "$script" "--boot-mode iso|direct|uefi"
  assert_file_contains "$script" "--installer-ui graphical|text"
  assert_file_contains "$script" "--graphics vnc|none|egl-headless"
  assert_file_contains "$script" "boot_mode=iso"
  assert_file_contains "$script" "installer_ui=graphical"
  assert_file_contains "$script" "graphics_mode=vnc"
  assert_file_contains "$script" "iso|direct|uefi)"
  assert_file_contains "$script" "graphical|text)"
  assert_file_contains "$script" "vnc|none|egl-headless)"
  assert_file_contains "$script" "qemu_args+=(-boot d)"
  assert_file_contains "$script" "display_args=(-display \"vnc=\$vnc_display\")"
  assert_file_contains "$script" "display_args=(-display egl-headless,gl=on -vga none -device virtio-vga-gl)"
  assert_file_contains "$script" "extract_fedora_iso_metadata \"\$input_iso\""
  assert_file_contains "$script" "repo=fedora-%s&arch=%s"
  assert_file_contains "$script" "--cmdline \"console=ttyS0,115200n8 inst.cmdline\""
  assert_file_contains "$script" "direct_append+=\" console=ttyS0,115200n8 inst.cmdline\""
  assert_file_contains "$script" "printf 'selected=1\\n' >/tmp/zz-linux-setup-install-selected"
  assert_file_contains "$script" "addon_data_dir="
  assert_file_contains "$script" "usr/share/anaconda/dbus/services"
  assert_file_contains "$script" "SoftwareSelectionSpoke"
  assert_file_contains "$script" "--add \"\$images_dir\""
  refute_file_contains "$script" "Bootstrap failed with exit code %s"
  refute_file_contains "$script" "cp -a /run/install/repo/zz-linux-setup /mnt/sysimage/opt/zz-linux-setup"
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

@test "Fedora installer release update flag refreshes and upgrades Fedora repos" {
  source_core
  source_modules
  DISTRO=fedora
  load_adapter
  DRY_RUN=0
  ZZ_INSTALLER_APPLY_RELEASE_UPDATES=1
  COMMAND=install
  run_cmd_as_root() {
    printf '%s\n' "$*"
  }

  run module_05_bootstrap_tools

  [ "$status" -eq 0 ]
  assert_contains "$output" "dnf makecache --refresh"
  assert_contains "$output" "dnf upgrade -y --refresh"
}
