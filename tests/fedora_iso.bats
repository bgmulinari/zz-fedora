#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  # shellcheck source=../config/defaults.sh
  source "$ROOT_DIR/config/defaults.sh"
  export ZZ_TEST_FEDORA_RELEASE="$((MINIMUM_FEDORA_RELEASE + 1))"
  export ZZ_TEST_BETA_RELEASE="$((ZZ_TEST_FEDORA_RELEASE + 1))"
}

make_fake_identity() {
  local uid="${1:-0}"
  write_fake_command id <<SH
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "\$#" -eq 1 && "\$1" == "-u" ]]; then
  printf '%s\n' "$uid"
else
  command -p id "\$@"
fi
SH
}

@test "Fedora ISO builder embeds Kickstart, checkout, and Anaconda add-on with mkksiso" {
  setup_fake_bin
  make_fake_identity

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
elif [[ "$src" == */catalog/ ]]; then
  mkdir -p "$dest/units/browsers"
  printf 'id = "browsers-firefox"\n' >"$dest/units/browsers/firefox.toml"
else
  printf 'payload\n' >"$dest/payload-marker"
  printf '#!/usr/bin/env bash\n' >"$dest/install.sh"
  chmod +x "$dest/install.sh"
  mkdir -p "$dest/iso/lib"
  printf '#!/usr/bin/env bash\n' >"$dest/iso/lib/runtime-loader.sh"
  chmod +x "$dest/iso/lib/runtime-loader.sh"
  mkdir -p "$dest/catalog/units" "$dest/lib"
  printf 'catalog tool\n' >"$dest/lib/catalog.py"
fi
SH

  write_fake_command xorriso <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
dest=${@: -1}
mkdir -p "$(dirname "$dest")"
printf '0\n%s\nx86_64\n' "$ZZ_TEST_FEDORA_RELEASE" >"$dest"
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
if grep -F "repo=fedora-$ZZ_TEST_FEDORA_RELEASE&arch=x86_64" "$ks" >/dev/null &&
  grep -Fx 'repo --name="updates"' "$ks" >/dev/null; then
  ks_has_release=yes
fi
payload_marker=no
product_img=no
addon_in_product=no
catalog_in_product=no
catalog_tool_in_product=no
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
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/addons/org_zz_fedora/catalog/units/browsers/firefox\.toml$' >/dev/null; then
      catalog_in_product=yes
    fi
    if gzip -dc "$add/product.img" | cpio -t 2>/dev/null | grep -E '^(\./)?usr/share/anaconda/addons/org_zz_fedora/lib/catalog\.py$' >/dev/null; then
      catalog_tool_in_product=yes
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
      grep -Fx "Version=$ZZ_TEST_FEDORA_RELEASE" <<<"$buildstamp" >/dev/null; then
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
  printf 'catalog_in_product=%s\n' "$catalog_in_product"
  printf 'catalog_tool_in_product=%s\n' "$catalog_tool_in_product"
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
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "catalog_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "catalog_tool_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "config_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "service_task_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "dbus_conf_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "dbus_service_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "addon_build_info_in_product=yes"
  assert_file_contains "$ZZ_TEST_MKKSISO_LOG" "buildstamp_version_in_product=yes"
  assert_file_contains "$ZZ_TEST_RSYNC_LOG" "--from0"
  assert_file_contains "$ZZ_TEST_RSYNC_LOG" "--files-from=-"
}

@test "Fedora ISO builder downloads and reuses its default input cache" {
  setup_fake_bin

  write_fake_command curl <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
destination=
while (($# > 0)); do
  case "$1" in
    --output)
      destination=$2
      shift 2
      ;;
    *)
      printf '%s\n' "$1" >>"$ZZ_TEST_CURL_LOG"
      shift
      ;;
  esac
done
[[ -n "$destination" ]]
mkdir -p "$(dirname "$destination")"
printf 'downloaded ISO\n' >"$destination"
SH

  input_url="https://download.fedoraproject.org/pub/fedora/linux/releases/$ZZ_TEST_FEDORA_RELEASE/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-$ZZ_TEST_FEDORA_RELEASE-1.7.iso"
  input_iso="$TEST_ROOT/release/input/Fedora-Everything-netinst-x86_64-$ZZ_TEST_FEDORA_RELEASE-1.7.iso"
  export ZZ_TEST_CURL_LOG="$TEST_ROOT/curl.log"

  run env PATH="$FAKE_BIN:$PATH" bash -c '
    source "$1"
    ISO_TOOL_NAME=default-input-test
    iso_download_cached_input "$2" "$3"
    iso_download_cached_input "$2" "$3"
  ' _ "$ROOT_DIR/iso/lib/build-common.sh" "$input_url" "$input_iso"

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "Downloading input ISO to $input_iso"
  assert_contains "$output" "Downloaded input ISO: $input_iso"
  assert_contains "$output" "Using cached input ISO: $input_iso"
  assert_file_contains "$input_iso" "downloaded ISO"
  [ ! -e "${input_iso}.part" ]
  [ "$(grep -Fxc -- "$input_url" "$ZZ_TEST_CURL_LOG")" -eq 1 ]

  run "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" --help
  [ "$status" -eq 0 ]
  assert_contains "$output" "[--input ISO] [--output ISO]"
  assert_contains "$output" "Publishable builds require root privileges"
  assert_contains "$output" "latest stable Fedora"
  assert_contains "$output" "downloaded to release/input"
  assert_contains "$output" "output filename is derived from the input ISO metadata"
  assert_file_contains "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" \
    'iso_prepare_default_input'
}

@test "Fedora ISO builder rejects empty option values" {
  local option
  for option in --input --output --input-sha256; do
    run "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "$option" ""
    [ "$status" -ne 0 ]
    assert_contains "$output" "$option requires a value."

    run "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "$option="
    [ "$status" -ne 0 ]
    assert_contains "$output" "$option requires a value."
  done
}

@test "Fedora ISO builder requires root before resolving or downloading its input" {
  setup_fake_bin
  make_fake_identity 1000

  write_fake_command curl <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
touch "$ZZ_TEST_CURL_CALLED"
SH

  export ZZ_TEST_CURL_CALLED="$TEST_ROOT/curl-called"
  run env PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh"

  [ "$status" -ne 0 ]
  assert_contains "$output" "root privileges are required; rerun this command with sudo, or pass --skip-mkefiboot for a development build."
  [ ! -e "$ZZ_TEST_CURL_CALLED" ]
}

@test "Fedora ISO builder exempts skip-mkefiboot development builds from the root requirement" {
  setup_fake_bin
  make_fake_identity 1000

  run env PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" \
    --skip-mkefiboot --input "$TEST_ROOT/missing.iso"

  [ "$status" -ne 0 ]
  assert_contains "$output" "input ISO not found: $TEST_ROOT/missing.iso"
}

@test "Fedora ISO builder derives its default output and verifies automatic input" {
  setup_fake_bin
  make_fake_identity

  fixture_repo="$TEST_ROOT/builder-repo"
  release_key_dir="$TEST_ROOT/fedora-release-keys"
  mkdir -p "$fixture_repo/iso/scripts" "$fixture_repo/iso/lib" "$fixture_repo/config" "$release_key_dir"
  cp "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "$fixture_repo/iso/scripts/"
  cp "$ROOT_DIR/iso/lib/build-common.sh" "$fixture_repo/iso/lib/"
  cp "$ROOT_DIR/config/defaults.sh" "$fixture_repo/config/"
  cp "$ROOT_DIR/iso/zz-fedora.ks" "$ROOT_DIR/iso/payload-paths.conf" "$fixture_repo/iso/"
  cp -a "$ROOT_DIR/iso/anaconda-addon" "$ROOT_DIR/iso/anaconda-addon-data" "$fixture_repo/iso/"
  cp -a "$ROOT_DIR/catalog" "$fixture_repo/"
  mkdir -p "$fixture_repo/lib"
  cp "$ROOT_DIR/lib/catalog.py" "$fixture_repo/lib/"
  cp "$ROOT_DIR/install.sh" "$fixture_repo/"
  git -C "$fixture_repo" init -q
  git -C "$fixture_repo" add .

  write_fake_command rsync <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
staging_payload=0
if [[ " $* " == *" --files-from=- "* ]]; then
  staging_payload=1
  cat >/dev/null
fi
destination=${@: -1}
mkdir -p "$destination"
if [[ "$staging_payload" -eq 1 ]]; then
  printf '#!/usr/bin/env bash\n' >"$destination/install.sh"
  chmod +x "$destination/install.sh"
  mkdir -p "$destination/iso/lib"
  printf '#!/usr/bin/env bash\n' >"$destination/iso/lib/runtime-loader.sh"
  chmod +x "$destination/iso/lib/runtime-loader.sh"
  mkdir -p "$destination/catalog/units" "$destination/lib"
  printf 'catalog tool\n' >"$destination/lib/catalog.py"
fi
SH

  write_fake_command curl <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
destination=
url=
while (($# > 0)); do
  case "$1" in
    --output)
      destination=$2
      shift 2
      ;;
    --retry)
      shift 2
      ;;
    --fail|--location)
      shift
      ;;
    *)
      url=$1
      shift
      ;;
  esac
done
[[ -n "$destination" && -n "$url" ]]
printf '%s\n' "$url" >>"$ZZ_TEST_CURL_LOG"
case "$url" in
  */releases.json)
    printf '[{"version":"%s","arch":"x86_64","link":"https://download.fedoraproject.org/pub/fedora/linux/releases/test/%s_Beta/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-%s-1.1.iso","variant":"Everything","subvariant":"Everything","sha256":"%064d","size":"1234567890"},{"version":"%s","arch":"x86_64","link":"https://download.fedoraproject.org/pub/fedora/linux/releases/%s/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-%s-1.7.iso","variant":"Everything","subvariant":"Everything","sha256":"%s","size":"1217329152"}]\n' \
      "$ZZ_TEST_BETA_RELEASE" \
      "$ZZ_TEST_BETA_RELEASE" \
      "$ZZ_TEST_BETA_RELEASE" \
      0 \
      "$ZZ_TEST_FEDORA_RELEASE" \
      "$ZZ_TEST_FEDORA_RELEASE" \
      "$ZZ_TEST_FEDORA_RELEASE" \
      "$ZZ_TEST_INPUT_SHA256" >"$destination"
    ;;
  *-CHECKSUM)
    printf 'signed checksum fixture\n' >"$destination"
    ;;
  */fedora.gpg)
    printf 'Fedora keyring fixture\n' >"$destination"
    ;;
  *.iso)
    printf 'mock Fedora input ISO\n' >"$destination"
    ;;
  *)
    exit 1
    ;;
esac
SH

  write_fake_command gpg <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'pub:-:4096:1:DBFCF71C6D9F90A6:0:0::-:::scESC::::::23::0:\n'
printf 'fpr:::::::::36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6:\n'
SH

  write_fake_command gpgv <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
verified_output=
checksum_file=
while (($# > 0)); do
  case "$1" in
    --keyring|--status-fd)
      shift 2
      ;;
    --output)
      verified_output=$2
      shift 2
      ;;
    *)
      checksum_file=$1
      shift
      ;;
  esac
done
[[ -n "$verified_output" && -n "$checksum_file" ]]
if ! grep -q 'signed checksum fixture' "$checksum_file"; then
  exit 2
fi
printf '[GNUPG:] VALIDSIG 36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6 2026-04-24 0 0 4 0 1 8 01 36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6\n' >&3
printf 'SHA256 (Fedora-Everything-netinst-x86_64-%s-1.7.iso) = %s\n' \
  "$ZZ_TEST_FEDORA_RELEASE" \
  "$ZZ_TEST_INPUT_SHA256" >"$verified_output"
printf 'verified\n' >>"$ZZ_TEST_GPGV_LOG"
SH

  write_fake_command xorriso <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
destination=${@: -1}
mkdir -p "$(dirname "$destination")"
printf '0\n%s\nx86_64\n' "$ZZ_TEST_FEDORA_RELEASE" >"$destination"
SH

  write_fake_command mkksiso <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
output=${@: -1}
printf 'mock ISO\n' >"$output"
SH

  input_url="https://download.fedoraproject.org/pub/fedora/linux/releases/$ZZ_TEST_FEDORA_RELEASE/Everything/x86_64/iso/Fedora-Everything-netinst-x86_64-$ZZ_TEST_FEDORA_RELEASE-1.7.iso"
  input_iso="$fixture_repo/release/input/Fedora-Everything-netinst-x86_64-$ZZ_TEST_FEDORA_RELEASE-1.7.iso"
  expected_output="$fixture_repo/release/zz-fedora-x86_64-$ZZ_TEST_FEDORA_RELEASE.iso"
  export ZZ_TEST_CURL_LOG="$TEST_ROOT/default-input-curl.log"
  export ZZ_TEST_GPGV_LOG="$TEST_ROOT/default-input-gpgv.log"
  export ZZ_FEDORA_RELEASE_KEY_DIR="$release_key_dir"
  export ZZ_TEST_INPUT_SHA256
  ZZ_TEST_INPUT_SHA256="$(printf 'mock Fedora input ISO\n' | sha256sum | awk '{print $1}')"
  printf 'Fedora release certificate fixture\n' >"$release_key_dir/RPM-GPG-KEY-fedora-$ZZ_TEST_FEDORA_RELEASE-primary"

  run env PATH="$FAKE_BIN:$PATH" "$fixture_repo/iso/scripts/build-fedora-installer-iso.sh"

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "Resolved latest Fedora Everything release: $ZZ_TEST_FEDORA_RELEASE x86_64"
  assert_contains "$output" "Created $expected_output"
  assert_contains "$output" "Verified Fedora checksum signature: 36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6"
  assert_contains "$output" "Verified input SHA-256: $ZZ_TEST_INPUT_SHA256"
  assert_file_contains "$input_iso" "mock Fedora input ISO"
  assert_file_contains "$expected_output" "mock ISO"

  run env PATH="$FAKE_BIN:$PATH" "$fixture_repo/iso/scripts/build-fedora-installer-iso.sh"
  [ "$status" -eq 0 ]
  assert_contains "$output" "Using cached input ISO: $input_iso"
  [ "$(grep -Fxc -- "$input_url" "$ZZ_TEST_CURL_LOG")" -eq 1 ]
  [ "$(grep -Fxc -- "verified" "$ZZ_TEST_GPGV_LOG")" -eq 2 ]

  printf 'corrupt cached ISO\n' >"$input_iso"
  run env PATH="$FAKE_BIN:$PATH" "$fixture_repo/iso/scripts/build-fedora-installer-iso.sh"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "cached input ISO failed verification; downloading a replacement"
  assert_contains "$output" "Downloading input ISO to $input_iso"
  assert_file_contains "$input_iso" "mock Fedora input ISO"
  [ "$(grep -Fxc -- "$input_url" "$ZZ_TEST_CURL_LOG")" -eq 2 ]
  [ "$(grep -Fxc -- "verified" "$ZZ_TEST_GPGV_LOG")" -eq 3 ]

  checksum_url="${input_url%/*}/Fedora-Everything-$ZZ_TEST_FEDORA_RELEASE-1.7-x86_64-CHECKSUM"
  checksum_file="$fixture_repo/release/input/Fedora-Everything-$ZZ_TEST_FEDORA_RELEASE-1.7-x86_64-CHECKSUM"
  [ "$(grep -Fxc -- "$checksum_url" "$ZZ_TEST_CURL_LOG")" -eq 1 ]
  printf 'tampered checksum\n' >"$checksum_file"
  run env PATH="$FAKE_BIN:$PATH" "$fixture_repo/iso/scripts/build-fedora-installer-iso.sh"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "cached Fedora checksum failed verification; downloading a replacement"
  assert_file_contains "$checksum_file" "signed checksum fixture"
  [ "$(grep -Fxc -- "$checksum_url" "$ZZ_TEST_CURL_LOG")" -eq 2 ]
  [ "$(grep -Fxc -- "verified" "$ZZ_TEST_GPGV_LOG")" -eq 4 ]
}

@test "Fedora ISO platform validation uses the repository minimum release" {
  source "$ROOT_DIR/iso/lib/build-common.sh"
  ISO_TOOL_NAME=platform-test
  previous_release="$((MINIMUM_FEDORA_RELEASE - 1))"
  next_release="$((MINIMUM_FEDORA_RELEASE + 1))"

  run iso_validate_supported_platform "$previous_release" x86_64 "$MINIMUM_FEDORA_RELEASE"
  [ "$status" -ne 0 ]
  assert_contains "$output" "minimum: $MINIMUM_FEDORA_RELEASE"

  run iso_validate_supported_platform "$MINIMUM_FEDORA_RELEASE" x86_64 "$MINIMUM_FEDORA_RELEASE"
  [ "$status" -eq 0 ]

  run iso_validate_supported_platform "$next_release" x86_64 "$MINIMUM_FEDORA_RELEASE"
  [ "$status" -eq 0 ]

  run iso_validate_supported_platform "$next_release" x86_64 ""
  [ "$status" -ne 0 ]
  assert_contains "$output" "invalid MINIMUM_FEDORA_RELEASE configuration"
  refute_contains "$output" "input ISO"
}

@test "Fedora ISO builder rejects a checksum signed by an unexpected key" {
  setup_fake_bin

  write_fake_command gpgv <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
verified_output=
while (($# > 0)); do
  case "$1" in
    --keyring|--status-fd)
      shift 2
      ;;
    --output)
      verified_output=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '[GNUPG:] VALIDSIG 0000000000000000000000000000000000000000 2026-04-24 0 0 4 0 1 8 01 0000000000000000000000000000000000000000\n' >&3
printf 'SHA256 (input.iso) = %064d\n' 0 >"$verified_output"
SH

  checksum_file="$TEST_ROOT/Fedora-Everything-CHECKSUM"
  keyring_file="$TEST_ROOT/fedora.gpg"
  touch "$checksum_file" "$keyring_file"
  run env PATH="$FAKE_BIN:$PATH" bash -c '
    source "$1"
    ISO_TOOL_NAME=checksum-test
    iso_verified_sha256_from_checksum \
      "$2" "$3" 36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6 input.iso
  ' _ "$ROOT_DIR/iso/lib/build-common.sh" "$checksum_file" "$keyring_file"

  [ "$status" -ne 0 ]
  assert_contains "$output" "checksum signature is not from expected Fedora signer"
}

@test "Fedora ISO checksum verification accepts a signature from a subkey of the expected key" {
  setup_fake_bin

  write_fake_command gpgv <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
verified_output=
while (($# > 0)); do
  case "$1" in
    --keyring|--status-fd)
      shift 2
      ;;
    --output)
      verified_output=$2
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "$verified_output" ]]
printf '[GNUPG:] VALIDSIG 1111111111111111111111111111111111111111 2026-04-24 0 0 4 0 1 8 01 36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6\n' >&3
printf 'SHA256 (input.iso) = %064d\n' 0 >"$verified_output"
SH

  checksum_file="$TEST_ROOT/Fedora-Everything-CHECKSUM"
  keyring_file="$TEST_ROOT/fedora.gpg"
  touch "$checksum_file" "$keyring_file"
  run env PATH="$FAKE_BIN:$PATH" bash -c '
    source "$1"
    ISO_TOOL_NAME=checksum-test
    iso_verified_sha256_from_checksum \
      "$2" "$3" 36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6 input.iso
  ' _ "$ROOT_DIR/iso/lib/build-common.sh" "$checksum_file" "$keyring_file"

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "$(printf '%064d' 0)"
}

@test "Fedora ISO certificate fingerprint requires exactly one primary key" {
  setup_fake_bin

  certificate="$TEST_ROOT/release-certificate"
  touch "$certificate"

  write_fake_command gpg <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'pub:-:4096:1:DBFCF71C6D9F90A6:0:0::-:::scESC::::::23::0:\n'
printf 'fpr:::::::::36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6:\n'
printf 'sub:-:4096:1:AAAAAAAAAAAAAAAA:0:0:::::s::::::23:\n'
printf 'fpr:::::::::4444444444444444444444444444444444444444:\n'
SH

  run env PATH="$FAKE_BIN:$PATH" bash -c '
    source "$1"
    ISO_TOOL_NAME=certificate-test
    iso_certificate_fingerprint "$2"
  ' _ "$ROOT_DIR/iso/lib/build-common.sh" "$certificate"

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6"
  refute_contains "$output" "4444444444444444444444444444444444444444"

  write_fake_command gpg <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'pub:-:4096:1:DBFCF71C6D9F90A6:0:0::-:::scESC::::::23::0:\n'
printf 'fpr:::::::::36F612DCF27F7D1A48A835E4DBFCF71C6D9F90A6:\n'
printf 'pub:-:4096:1:BBBBBBBBBBBBBBBB:0:0::-:::scESC::::::23::0:\n'
printf 'fpr:::::::::5555555555555555555555555555555555555555:\n'
SH

  run env PATH="$FAKE_BIN:$PATH" bash -c '
    source "$1"
    ISO_TOOL_NAME=certificate-test
    iso_certificate_fingerprint "$2"
  ' _ "$ROOT_DIR/iso/lib/build-common.sh" "$certificate"

  [ "$status" -ne 0 ]
  assert_contains "$output" "contains more than one key"
}

@test "Fedora ISO builder checks local build inputs before downloading" {
  setup_fake_bin
  make_fake_identity

  fixture_repo="$TEST_ROOT/precondition-repo"
  mkdir -p "$fixture_repo/iso/scripts" "$fixture_repo/iso/lib" "$fixture_repo/config"
  cp "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "$fixture_repo/iso/scripts/"
  cp "$ROOT_DIR/iso/lib/build-common.sh" "$fixture_repo/iso/lib/"
  cp "$ROOT_DIR/config/defaults.sh" "$fixture_repo/config/"

  write_fake_command curl <<'SH'
#!/usr/bin/env bash
touch "$ZZ_TEST_CURL_CALLED"
exit 1
SH
  local command_name
  for command_name in cpio gzip mkksiso rsync xorriso gpg gpgv jq sha256sum; do
    write_fake_command "$command_name" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  done

  export ZZ_TEST_CURL_CALLED="$TEST_ROOT/curl-called"
  run env PATH="$FAKE_BIN:$PATH" "$fixture_repo/iso/scripts/build-fedora-installer-iso.sh"

  [ "$status" -ne 0 ]
  assert_contains "$output" "missing Kickstart file"
  [ ! -e "$ZZ_TEST_CURL_CALLED" ]
}

@test "Fedora ISO input download does not publish a failed partial file" {
  setup_fake_bin

  write_fake_command curl <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
while (($# > 0)); do
  if [[ "$1" == "--output" ]]; then
    printf 'partial ISO\n' >"$2"
    exit 22
  fi
  shift
done
exit 22
SH

  input_iso="$TEST_ROOT/release/input/Fedora-Everything-netinst-x86_64-$ZZ_TEST_FEDORA_RELEASE-1.7.iso"
  run env PATH="$FAKE_BIN:$PATH" bash -c '
    source "$1"
    ISO_TOOL_NAME=default-input-test
    iso_download_cached_input https://example.invalid/input.iso "$2"
  ' _ "$ROOT_DIR/iso/lib/build-common.sh" "$input_iso"

  [ "$status" -eq 22 ]
  assert_contains "$output" "failed to download input ISO"
  [ ! -e "$input_iso" ]
  [ ! -e "${input_iso}.part" ]
}

@test "ISO runtime payload contains only tracked allowlisted files" {
  command -v git >/dev/null 2>&1 || skip "git is not installed"
  command -v rsync >/dev/null 2>&1 || skip "rsync is not installed"

  fixture="$TEST_ROOT/payload-repo"
  destination="$TEST_ROOT/payload"
  mkdir -p "$fixture/iso/lib" "$fixture/lib" "$fixture/catalog/units/browsers" "$fixture/tests" "$fixture/logs"
  printf '#!/usr/bin/env bash\n' >"$fixture/install.sh"
  chmod +x "$fixture/install.sh"
  printf 'install.sh\ncatalog\nlib\niso/payload-paths.conf\niso/lib/runtime-loader.sh\n' >"$fixture/iso/payload-paths.conf"
  printf '#!/usr/bin/env bash\n' >"$fixture/iso/lib/runtime-loader.sh"
  chmod +x "$fixture/iso/lib/runtime-loader.sh"
  printf 'runtime\n' >"$fixture/lib/runtime.sh"
  printf 'catalog tool\n' >"$fixture/lib/catalog.py"
  printf 'id = "browsers-firefox"\n' >"$fixture/catalog/units/browsers/firefox.toml"
  printf 'test\n' >"$fixture/tests/not-runtime.bats"
  printf 'secret\n' >"$fixture/.env"
  printf 'log\n' >"$fixture/logs/local.log"
  git -C "$fixture" init -q
  git -C "$fixture" add iso/payload-paths.conf iso/lib/runtime-loader.sh install.sh lib/runtime.sh lib/catalog.py catalog/units/browsers/firefox.toml tests/not-runtime.bats

  # shellcheck source=../iso/lib/build-common.sh
  source "$ROOT_DIR/iso/lib/build-common.sh"
  ISO_TOOL_NAME="payload-test"
  iso_stage_tracked_runtime_payload "$fixture" "$destination"

  [[ -x "$destination/install.sh" ]]
  [[ -f "$destination/iso/payload-paths.conf" ]]
  [[ -x "$destination/iso/lib/runtime-loader.sh" ]]
  [[ -f "$destination/lib/runtime.sh" ]]
  [[ -f "$destination/lib/catalog.py" ]]
  [[ -f "$destination/catalog/units/browsers/firefox.toml" ]]
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
  assert_file_contains "$manifest" "catalog"
  assert_file_contains "$manifest" "lib"
}

@test "ISO runtime refresh stages a remote runtime snapshot" {
  command -v curl >/dev/null 2>&1 || skip "curl is not installed"
  command -v cp >/dev/null 2>&1 || skip "cp is not installed"
  command -v tar >/dev/null 2>&1 || skip "tar is not installed"

  archive_root="$TEST_ROOT/snapshot-deadbee"
  archive="$TEST_ROOT/snapshot.tar.gz"
  destination="$TEST_ROOT/runtime"
  mkdir -p "$archive_root/catalog/units/browsers" "$archive_root/extra-runtime" "$archive_root/iso" "$archive_root/lib" "$archive_root/tests"
  printf '#!/usr/bin/env bash\n' >"$archive_root/install.sh"
  chmod +x "$archive_root/install.sh"
  printf 'id = "browsers-firefox"\n' >"$archive_root/catalog/units/browsers/firefox.toml"
  printf 'catalog tool\n' >"$archive_root/lib/catalog.py"
  printf 'manifest-driven\n' >"$archive_root/extra-runtime/marker"
  printf 'latest runtime\n' >"$archive_root/lib/latest.sh"
  printf 'not runtime\n' >"$archive_root/tests/not-runtime.bats"
  printf 'install.sh\ncatalog\nlib\nextra-runtime\niso/payload-paths.conf\n' >"$archive_root/iso/payload-paths.conf"
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
  [[ -f "$destination/lib/catalog.py" ]]
  [[ -f "$destination/catalog/units/browsers/firefox.toml" ]]
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
  mkdir -p "$archive_root/catalog/units/browsers" "$archive_root/lib"
  printf '#!/usr/bin/env bash\n' >"$archive_root/install.sh"
  chmod +x "$archive_root/install.sh"
  printf 'id = "browsers-firefox"\n' >"$archive_root/catalog/units/browsers/firefox.toml"
  printf 'catalog tool\n' >"$archive_root/lib/catalog.py"
  printf 'install.sh\ncatalog\nlib\n' >"$paths_file"
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
  mkdir -p "$dest/catalog/units" "$dest/lib"
  printf 'catalog tool\n' >"$dest/lib/catalog.py"
fi
SH

  write_fake_command xorriso <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
dest=${@: -1}
mkdir -p "$(dirname "$dest")"
printf '0\n%s\nx86_64\n' "$ZZ_TEST_FEDORA_RELEASE" >"$dest"
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
  assert_contains "$package_lines" "git"
  assert_contains "$package_lines" "dnf5-plugins"
  assert_contains "$package_lines" "python3"
  assert_contains "$package_lines" "plymouth-system-theme"
  assert_file_contains "$ROOT_DIR/catalog/units/base/boot-splash.toml" "plymouth-system-theme"
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
