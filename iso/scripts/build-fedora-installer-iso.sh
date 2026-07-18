#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISO_TOOL_NAME="build-fedora-installer-iso"
# shellcheck source=../lib/build-common.sh
source "$repo_dir/iso/lib/build-common.sh"

usage() {
  cat <<'EOF'
Usage: iso/scripts/build-fedora-installer-iso.sh --input ISO --output ISO [--input-sha256 HASH]

Embed this checkout and the zz-fedora Fedora Kickstart into a Fedora installer
ISO. The embedded checkout refreshes the remote runtime before Anaconda shows
its choices. An Anaconda add-on D-Bus task runs the normal installer from that
refreshed snapshot.
EOF
}

err() {
  iso_err "$@"
}

input_iso=
input_sha256=
output_iso=
skip_mkefiboot=0
fedora_release=
fedora_arch=

while (($# > 0)); do
  case "$1" in
    --input)
      if (($# < 2)); then
        err "--input requires a value."
        exit 1
      fi
      input_iso=$2
      shift 2
      ;;
    --input=*)
      input_iso=${1#*=}
      shift
      ;;
    --output)
      if (($# < 2)); then
        err "--output requires a value."
        exit 1
      fi
      output_iso=$2
      shift 2
      ;;
    --output=*)
      output_iso=${1#*=}
      shift
      ;;
    --input-sha256)
      if (($# < 2)); then
        err "--input-sha256 requires a value."
        exit 1
      fi
      input_sha256=$2
      shift 2
      ;;
    --input-sha256=*)
      input_sha256=${1#*=}
      shift
      ;;
    --skip-mkefiboot)
      skip_mkefiboot=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$input_iso" || -z "$output_iso" ]]; then
  usage >&2
  exit 1
fi

if [[ "$input_iso" == "$output_iso" ]]; then
  err "input and output ISO paths must differ."
  exit 1
fi

if [[ ! -f "$input_iso" ]]; then
  err "input ISO not found: $input_iso"
  exit 1
fi

if [[ -n "$input_sha256" ]]; then
  iso_verify_sha256 "$input_iso" "$input_sha256"
fi

for command in cpio gzip mkksiso rsync xorriso; do
  if ! command -v "$command" >/dev/null 2>&1; then
    err "missing required command: $command"
    exit 1
  fi
done

ks_file="$repo_dir/iso/zz-fedora.ks"
addon_dir="$repo_dir/iso/anaconda-addon"
addon_data_dir="$repo_dir/iso/anaconda-addon-data"

if [[ ! -f "$ks_file" ]]; then
  err "missing Kickstart file: $ks_file"
  exit 1
fi
if [[ ! -d "$addon_dir/org_zz_fedora" ]]; then
  err "missing Anaconda add-on payload: $addon_dir/org_zz_fedora"
  exit 1
fi
if [[ ! -d "$addon_data_dir" ]]; then
  err "missing Anaconda add-on data: $addon_data_dir"
  exit 1
fi

work_dir="$(mktemp -d)"
payload_dir="$work_dir/zz-fedora"
product_root="$work_dir/product"
images_dir="$work_dir/images"
product_img="$images_dir/product.img"
rendered_ks_file="$work_dir/zz-fedora.ks"
output_dir="$(dirname "$output_iso")"
output_base="$(basename "$output_iso")"
mkdir -p "$output_dir"
tmp_output="$(mktemp "$output_dir/.$output_base.tmp.XXXXXX")"
rm -f "$tmp_output"
trap 'rm -rf "$work_dir"; rm -f "$tmp_output"' EXIT

iso_extract_fedora_metadata "$input_iso"
iso_validate_supported_platform "$fedora_release" "$fedora_arch"
iso_stage_tracked_runtime_payload "$repo_dir" "$payload_dir"
iso_render_release_template "$ks_file" "$rendered_ks_file"

mkdir -p \
  "$product_root/etc/anaconda/conf.d" \
  "$product_root/usr/share/anaconda/dbus/confs" \
  "$product_root/usr/share/anaconda/dbus/services" \
  "$product_root/usr/share/anaconda/addons" \
  "$images_dir"
rsync -a --delete \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  "$addon_dir/" "$product_root/usr/share/anaconda/addons/"
rsync -a --delete "$repo_dir/choices/" "$product_root/usr/share/anaconda/addons/org_zz_fedora/choices/"
install -m 0644 \
  "$addon_data_dir/org.fedoraproject.Anaconda.Addons.ZZFedora.conf" \
  "$product_root/usr/share/anaconda/dbus/confs/"
install -m 0644 \
  "$addon_data_dir/org.fedoraproject.Anaconda.Addons.ZZFedora.service" \
  "$product_root/usr/share/anaconda/dbus/services/"
install -m 0644 \
  "$addon_data_dir/conf.d/100-zz-fedora.conf" \
  "$product_root/etc/anaconda/conf.d/"
iso_render_release_template \
  "$addon_data_dir/buildstamp.in" \
  "$product_root/.buildstamp"
iso_write_checkout_stamp "$repo_dir" \
  "$product_root/usr/share/anaconda/addons/org_zz_fedora/build-info.conf"
(
  cd "$product_root"
  find . -print | sort | cpio --quiet -c -o | gzip -9c >"$product_img"
)

mkksiso_args=(
  --add "$payload_dir"
  --add "$images_dir"
  --ks "$rendered_ks_file"
)
if [[ "$skip_mkefiboot" -eq 1 ]]; then
  mkksiso_args+=(--skip-mkefiboot)
fi
mkksiso_args+=("$input_iso" "$tmp_output")

mkksiso "${mkksiso_args[@]}"

mv -f "$tmp_output" "$output_iso"
printf 'Created %s\n' "$output_iso"
