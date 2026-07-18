#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
}

@test "Fedora ISO builder embeds Kickstart, checkout, and Anaconda add-on with mkksiso" {
  setup_fake_bin

  write_fake_command rsync <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >>"$ZZ_TEST_RSYNC_LOG"
[[ " $* " == *" --files-from=- "* ]] && cat >/dev/null
src=${@: -2:1}
dest=${@: -1}
mkdir -p "$dest"
if [[ "$src" == */anaconda-addon/ ]]; then
  mkdir -p "$dest/org_zz_fedora"
  printf 'addon\n' >"$dest/org_zz_fedora/__init__.py"
  mkdir -p "$dest/org_zz_fedora/service"
  printf 'service\n' >"$dest/org_zz_fedora/service/installation.py"
elif [[ "$src" == */choices/ ]]; then
  printf 'firefox\tFirefox\t1\tbrowsers-firefox\tFedora official Firefox\n' >"$dest/browsers.conf"
else
  printf 'payload\n' >"$dest/payload-marker"
  printf '#!/usr/bin/env bash\n' >"$dest/install.sh"
  chmod +x "$dest/install.sh"
  mkdir -p "$dest/iso/lib"
  printf '#!/usr/bin/env bash\n' >"$dest/iso/lib/runtime-loader.sh"
  chmod +x "$dest/iso/lib/runtime-loader.sh"
fi
SH

  write_fake_command xorriso <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
dest=${@: -1}
mkdir -p "$(dirname "$dest")"
printf '0\n44\nx86_64\n' >"$dest"
SH

  write_fake_command mkksiso <<'SH'
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
  grep -Fx 'repo --name="updates"' "$ks" >/dev/null; then
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
addon_build_info_in_product=no
buildstamp_version_in_product=no
for add in "${adds[@]}"; do
  [[ -d "$add" ]]
  if [[ -f "$add/payload-marker" ]]; then
    payload_marker=yes
  fi
  if [[ -f "$add/product.img" ]]; then
    product_img=yes
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/addons/org_zz_fedora/__init__\.py$' >/dev/null; then
      addon_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/addons/org_zz_fedora/choices/browsers\.conf$' >/dev/null; then
      choices_in_product=yes
    fi
    product_conf="$(gzip -dc "$add/product.img" | cpio -i --to-stdout --quiet '*100-zz-fedora.conf' 2>/dev/null || true)"
    if grep -F 'SoftwareSelectionSpoke' <<<"$product_conf" >/dev/null; then
      config_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/addons/org_zz_fedora/service/installation\.py$' >/dev/null; then
      service_task_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/dbus/confs/org\.fedoraproject\.Anaconda\.Addons\.ZZFedora\.conf$' >/dev/null; then
      dbus_conf_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/dbus/services/org\.fedoraproject\.Anaconda\.Addons\.ZZFedora\.service$' >/dev/null; then
      dbus_service_in_product=yes
    fi
    addon_build_info="$(gzip -dc "$add/product.img" | cpio -i --to-stdout --quiet '*org_zz_fedora/build-info.conf' 2>/dev/null || true)"
    if grep -E '^git_revision=[0-9a-f]{40}$' <<<"$addon_build_info" >/dev/null; then
      addon_build_info_in_product=yes
    fi
    buildstamp="$(gzip -dc "$add/product.img" | cpio -i --to-stdout --quiet '*buildstamp' 2>/dev/null || true)"
    if grep -Fx 'Product=ZZ Fedora' <<<"$buildstamp" >/dev/null &&
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
  printf 'addon_build_info_in_product=%s\n' "$addon_build_info_in_product"
  printf 'buildstamp_version_in_product=%s\n' "$buildstamp_version_in_product"
  printf 'input=%s\n' "$input"
  printf 'output=%s\n' "$output"
  printf 'skip=%s\n' "$skip"
} >"$ZZ_TEST_MKKSISO_LOG"
printf 'mock iso\n' >"$output"
SH

  input_iso="$TEST_ROOT/Fedora-Everything-netinst.iso"
  output_iso="$TEST_ROOT/zz-fedora.iso"
  touch "$input_iso"
  input_sha256="$(sha256sum "$input_iso" | awk '{print $1}')"
  export ZZ_TEST_RSYNC_LOG="$TEST_ROOT/rsync.log"
  export ZZ_TEST_MKKSISO_LOG="$TEST_ROOT/mkksiso.log"

  run env PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" \
    --input "$input_iso" \
    --input-sha256 "$input_sha256" \
    --output "$output_iso"

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
    return "$status"
  fi
  assert_contains "$output" "Created $output_iso"
  assert_contains "$output" "Verified input SHA-256: $input_sha256"
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
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "addon_build_info_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "buildstamp_version_in_product=yes"
  assert_file_contains "$ZZ_TEST_RSYNC_LOG" "--from0"
  assert_file_contains "$ZZ_TEST_RSYNC_LOG" "--files-from=-"
}

@test "ISO runtime payload contains only tracked allowlisted files" {
  command -v git >/dev/null 2>&1 || skip "git is not installed"
  command -v rsync >/dev/null 2>&1 || skip "rsync is not installed"

  fixture="$TEST_ROOT/payload-repo"
  destination="$TEST_ROOT/payload"
  mkdir -p "$fixture/iso/lib" "$fixture/lib" "$fixture/tests" "$fixture/logs"
  printf '#!/usr/bin/env bash\n' >"$fixture/install.sh"
  chmod +x "$fixture/install.sh"
  printf 'install.sh\nlib\niso/payload-paths.conf\niso/lib/runtime-loader.sh\n' >"$fixture/iso/payload-paths.conf"
  printf '#!/usr/bin/env bash\n' >"$fixture/iso/lib/runtime-loader.sh"
  chmod +x "$fixture/iso/lib/runtime-loader.sh"
  printf 'runtime\n' >"$fixture/lib/runtime.sh"
  printf 'test\n' >"$fixture/tests/not-runtime.bats"
  printf 'secret\n' >"$fixture/.env"
  printf 'log\n' >"$fixture/logs/local.log"
  git -C "$fixture" init -q
  git -C "$fixture" add iso/payload-paths.conf iso/lib/runtime-loader.sh install.sh lib/runtime.sh tests/not-runtime.bats

  # shellcheck source=../iso/lib/build-common.sh
  source "$ROOT_DIR/iso/lib/build-common.sh"
  ISO_TOOL_NAME="payload-test"
  iso_stage_tracked_runtime_payload "$fixture" "$destination"

  [[ -x "$destination/install.sh" ]]
  [[ -f "$destination/iso/payload-paths.conf" ]]
  [[ -x "$destination/iso/lib/runtime-loader.sh" ]]
  [[ -f "$destination/lib/runtime.sh" ]]
  [[ ! -e "$destination/.git" ]]
  [[ ! -e "$destination/.env" ]]
  [[ ! -e "$destination/logs" ]]
  [[ ! -e "$destination/tests" ]]
  assert_file_contains "$destination/config/iso-payload.conf" "format=1"
}

@test "ISO payload manifest and Anaconda add-on agree on the runtime loader path" {
  runtime_py="$ROOT_DIR/iso/anaconda-addon/org_zz_fedora/runtime.py"
  manifest="$ROOT_DIR/iso/payload-paths.conf"

  [[ -x "$ROOT_DIR/iso/lib/runtime-loader.sh" ]]
  assert_file_contains "$runtime_py" "/run/install/repo/zz-fedora/iso/lib/runtime-loader.sh"
  assert_file_contains "$manifest" "iso/lib/runtime-loader.sh"
  assert_file_contains "$manifest" "iso/payload-paths.conf"
}

@test "ISO runtime refresh stages a remote runtime snapshot" {
  command -v curl >/dev/null 2>&1 || skip "curl is not installed"
  command -v cp >/dev/null 2>&1 || skip "cp is not installed"
  command -v tar >/dev/null 2>&1 || skip "tar is not installed"

  archive_root="$TEST_ROOT/snapshot-deadbee"
  archive="$TEST_ROOT/snapshot.tar.gz"
  destination="$TEST_ROOT/runtime"
  mkdir -p "$archive_root/choices" "$archive_root/extra-runtime" "$archive_root/iso" "$archive_root/lib" "$archive_root/tests"
  printf '#!/usr/bin/env bash\n' >"$archive_root/install.sh"
  chmod +x "$archive_root/install.sh"
  printf 'firefox\tFirefox\t1\tbrowsers-firefox\tFirefox\n' >"$archive_root/choices/browsers.conf"
  printf 'manifest-driven\n' >"$archive_root/extra-runtime/marker"
  printf 'latest runtime\n' >"$archive_root/lib/latest.sh"
  printf 'not runtime\n' >"$archive_root/tests/not-runtime.bats"
  printf 'install.sh\nchoices\nlib\nextra-runtime\niso/payload-paths.conf\n' >"$archive_root/iso/payload-paths.conf"
  tar -czf "$archive" -C "$TEST_ROOT" "$(basename "$archive_root")"

  run env \
    ZZ_ISO_RUNTIME_ARCHIVE_URL="file://$archive" \
    ZZ_ISO_RUNTIME_REF=main \
    ZZ_ISO_RUNTIME_DIR="$destination" \
    "$ROOT_DIR/iso/lib/runtime-loader.sh"

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  [[ -x "$destination/install.sh" ]]
  [[ -f "$destination/iso/payload-paths.conf" ]]
  [[ -f "$destination/extra-runtime/marker" ]]
  [[ -f "$destination/lib/latest.sh" ]]
  [[ ! -e "$destination/tests" ]]
  assert_file_contains "$destination/config/iso-payload.conf" "git_revision=deadbee"
  assert_file_contains "$destination/config/iso-payload.conf" "remote_ref=main"
}

@test "ISO runtime refresh repairs the clock after TLS validation failure" {
  command -v cp >/dev/null 2>&1 || skip "cp is not installed"
  command -v tar >/dev/null 2>&1 || skip "tar is not installed"

  setup_fake_bin
  archive_root="$TEST_ROOT/snapshot-c0ffee0"
  archive="$TEST_ROOT/clock-snapshot.tar.gz"
  destination="$TEST_ROOT/clock-runtime"
  paths_file="$TEST_ROOT/clock-runtime-paths.conf"
  mkdir -p "$archive_root/choices"
  printf '#!/usr/bin/env bash\n' >"$archive_root/install.sh"
  chmod +x "$archive_root/install.sh"
  printf 'firefox\tFirefox\t1\tbrowsers-firefox\tFirefox\n' >"$archive_root/choices/browsers.conf"
  printf 'install.sh\nchoices\n' >"$paths_file"
  tar -czf "$archive" -C "$TEST_ROOT" "$(basename "$archive_root")"

  write_fake_command curl <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
count=0
[[ ! -f "$ZZ_TEST_CURL_COUNT" ]] || count="$(<"$ZZ_TEST_CURL_COUNT")"
count=$((count + 1))
printf '%s\n' "$count" >"$ZZ_TEST_CURL_COUNT"
if [[ "$count" -eq 1 ]]; then
  exit 60
fi
output=
while (($# > 0)); do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done
cp "$ZZ_TEST_ARCHIVE" "$output"
SH

  write_fake_command chronyd <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >"$ZZ_TEST_CHRONYD_LOG"
SH

  write_fake_command chronyc <<'SH'
#!/usr/bin/env bash
exit 1
SH

  run env \
    PATH="$FAKE_BIN:$PATH" \
    ZZ_ISO_RUNTIME_ARCHIVE_URL=https://example.invalid/runtime.tar.gz \
    ZZ_ISO_RUNTIME_PATHS_FILE="$paths_file" \
    ZZ_ISO_RUNTIME_DIR="$destination" \
    ZZ_TEST_ARCHIVE="$archive" \
    ZZ_TEST_CHRONYD_LOG="$TEST_ROOT/chronyd.log" \
    ZZ_TEST_CURL_COUNT="$TEST_ROOT/curl-count" \
    "$ROOT_DIR/iso/lib/runtime-loader.sh"

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_file_contains "$TEST_ROOT/curl-count" "2"
  assert_file_contains "$TEST_ROOT/chronyd.log" "-q -t 30"
  [[ -x "$destination/install.sh" ]]
}

@test "Fedora ISO builder forwards development skip-mkefiboot flag" {
  setup_fake_bin

  write_fake_command rsync <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
staging_payload=0
if [[ " $* " == *" --files-from=- "* ]]; then
  staging_payload=1
  cat >/dev/null
fi
src=${@: -2:1}
dest=${@: -1}
mkdir -p "$dest"
if [[ "$staging_payload" -eq 1 ]]; then
  printf '#!/usr/bin/env bash\n' >"$dest/install.sh"
  chmod +x "$dest/install.sh"
  mkdir -p "$dest/iso/lib"
  printf '#!/usr/bin/env bash\n' >"$dest/iso/lib/runtime-loader.sh"
  chmod +x "$dest/iso/lib/runtime-loader.sh"
fi
SH

  write_fake_command xorriso <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
dest=${@: -1}
mkdir -p "$(dirname "$dest")"
printf '0\n44\nx86_64\n' >"$dest"
SH

  write_fake_command mkksiso <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >"$ZZ_TEST_MKKSISO_LOG"
output=${@: -1}
printf 'mock iso\n' >"$output"
SH

  input_iso="$TEST_ROOT/Fedora-Everything-netinst.iso"
  output_iso="$TEST_ROOT/zz-fedora.iso"
  touch "$input_iso"
  export ZZ_TEST_MKKSISO_LOG="$TEST_ROOT/mkksiso-skip.log"

  run env PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" \
    --input "$input_iso" \
    --output "$output_iso" \
    --skip-mkefiboot

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "--skip-mkefiboot"
}

@test "Fedora Kickstart preserves Anaconda decisions and delegates setup to add-on service" {
  ks="$ROOT_DIR/iso/zz-fedora.ks"
  package_lines="$(sed -n '/^%packages$/,/^%end$/p' "$ks")"

  assert_file_contains "$ks" "network --bootproto=dhcp --activate"
  assert_file_contains "$ks" "firstboot --disable"
  assert_file_contains "$ks" "url --metalink=\"https://mirrors.fedoraproject.org/metalink?repo=fedora-@FEDORA_RELEASE@&arch=@FEDORA_ARCH@\""
  assert_file_contains "$ks" 'repo --name="updates"'
  assert_file_contains "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "iso_extract_fedora_metadata"
  assert_file_contains "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "iso_render_release_template"
  assert_file_contains "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "addon_data_dir="
  assert_file_contains "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "usr/share/anaconda/dbus/confs"
  assert_file_contains "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "org.fedoraproject.Anaconda.Addons.ZZFedora.service"
  assert_contains "$package_lines" "dnf5-plugins"
  refute_contains "$package_lines" "bats"
  refute_contains "$package_lines" "dnf-plugins-core"
  refute_contains "$package_lines" "rsync"
  refute_file_contains "$ks" "%post"
  refute_file_contains "$ks" "zz-fedora-kickstart.log"
  refute_file_contains "$ks" "./install.sh install"
  refute_file_contains "$ks" "clearpart"
  refute_file_contains "$ks" "autopart"
  refute_file_contains "$ks" "rootpw"
}

@test "Anaconda product-image data lives in tracked files rendered by the build scripts" {
  data_dir="$ROOT_DIR/iso/anaconda-addon-data"
  build_script="$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh"
  vm_script="$ROOT_DIR/iso/scripts/test-fedora-installer-vm.sh"

  assert_file_contains "$data_dir/conf.d/100-zz-fedora.conf" "hidden_spokes ="
  assert_file_contains "$data_dir/conf.d/100-zz-fedora.conf" "SoftwareSelectionSpoke"
  assert_file_contains "$data_dir/buildstamp.in" "Product=ZZ Fedora"
  assert_file_contains "$data_dir/buildstamp.in" "Version=@FEDORA_RELEASE@"
  for script in "$build_script" "$vm_script"; do
    assert_file_contains "$script" 'conf.d/100-zz-fedora.conf'
    assert_file_contains "$script" 'buildstamp.in'
    assert_file_contains "$script" 'iso_write_checkout_stamp'
  done
}

@test "Fedora VM installer test defaults to ISO boot path" {
  script="$ROOT_DIR/iso/scripts/test-fedora-installer-vm.sh"

  assert_file_contains "$script" "--boot-mode iso|direct|uefi"
  assert_file_contains "$script" "--installer-ui graphical|text"
  assert_file_contains "$script" "--graphics vnc|none|egl-headless"
  assert_file_contains "$script" "--desktop-app-profile full|minimal"
  assert_file_contains "$script" "boot_mode=iso"
  assert_file_contains "$script" "installer_ui=graphical"
  assert_file_contains "$script" "graphics_mode=vnc"
  assert_file_contains "$script" "desktop_app_profile=full"
  assert_file_contains "$script" "iso|direct|uefi)"
  assert_file_contains "$script" "graphical|text)"
  assert_file_contains "$script" "vnc|none|egl-headless)"
  assert_file_contains "$script" "qemu_args+=(-boot d)"
  assert_file_contains "$script" "display_args=(-display \"vnc=\$vnc_display\")"
  assert_file_contains "$script" "display_args=(-display egl-headless,gl=on -vga none -device virtio-vga-gl)"
  assert_file_contains "$script" "iso_extract_fedora_metadata \"\$input_iso\""
  assert_file_contains "$script" 'work_dir="$(cd "$work_dir" && pwd)"'
  assert_file_contains "$script" "ZZ Fedora (9/9): Completed Doctor"
  assert_file_contains "$script" "ZZ Fedora complete"
  assert_file_contains "$script" "repo=fedora-%s&arch=%s"
  assert_file_contains "$script" "--cmdline \"console=ttyS0,115200n8 inst.cmdline\""
  assert_file_contains "$script" "direct_append+=\" console=ttyS0,115200n8 inst.cmdline\""
  assert_file_contains "$script" 'desktop_app_profile=$desktop_app_profile'
  assert_file_contains "$script" 'etc/zz-fedora/desktop-app-profile'
  assert_file_contains "$script" "Desktop app profile: %s"
  assert_file_contains "$script" "%pre --interpreter=/usr/bin/bash"
  assert_file_contains "$script" "addon_data_dir="
  assert_file_contains "$script" "usr/share/anaconda/dbus/services"
  assert_file_contains "$script" "conf.d/100-zz-fedora.conf"
  assert_file_contains "$script" "buildstamp.in"
  assert_file_contains "$script" "iso_write_checkout_stamp"
  assert_file_contains "$script" "--add \"\$images_dir\""
  refute_file_contains "$script" "Bootstrap failed with exit code %s"
  refute_file_contains "$script" "cp -a /run/install/repo/zz-fedora /mnt/sysimage/opt/zz-fedora"
}

@test "Fedora VM installer rejects unsupported desktop app profiles" {
  script="$ROOT_DIR/iso/scripts/test-fedora-installer-vm.sh"

  run "$script" --desktop-app-profile unsupported

  [ "$status" -ne 0 ]
  assert_contains "$output" "unsupported desktop app profile: unsupported"
}

@test "Fedora install readiness treats planned artifacts as planned during install" {
  source_core
  source_modules
  build_test_plan
  COMMAND=install
  DRY_RUN=0

  generate_readiness_status

  status_file="$(readiness_file)"
  assert_file_contains "$status_file" $'package:dnf\tniri\tplanned\tinfo'
  assert_file_contains "$status_file" $'niri\tcommand:niri\tplanned\tinfo'
  assert_file_contains "$status_file" $'noctalia\tcommand:noctalia\tplanned\tinfo'
  assert_file_contains "$status_file" $'portal\tcommand:xdg-desktop-portal\tplanned\tinfo'
  refute_file_contains "$status_file" $'niri\tcommand:niri\tmissing\tfatal'
}

@test "Fedora installer mode enables services without starting them in chroot" {
  source_core
  source_modules
  DRY_RUN=0
  ZZ_INSTALLER_DEFER_START_SERVICES=1
  run_cmd_as_root() {
    printf '%s\n' "$*"
  }

  run fedora_enable_services_now NetworkManager

  [ "$status" -eq 0 ]
  assert_contains "$output" "systemctl enable NetworkManager"
  refute_contains "$output" "--now"
}
