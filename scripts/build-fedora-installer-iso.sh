#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-fedora-installer-iso.sh --input ISO --output ISO

Embed this checkout and the zz-linux-setup Fedora Kickstart into a Fedora
installer ISO. The resulting ISO exposes the checkout at
/run/install/repo/zz-linux-setup and runs the normal installer online during
Anaconda %post.
EOF
}

err() {
  printf 'build-fedora-installer-iso: %s\n' "$*" >&2
}

input_iso=
output_iso=
skip_mkefiboot=0

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

for command in mkksiso rsync; do
  if ! command -v "$command" >/dev/null 2>&1; then
    err "missing required command: $command"
    exit 1
  fi
done

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ks_file="$repo_dir/iso/fedora/zz-fedora.ks"

if [[ ! -f "$ks_file" ]]; then
  err "missing Kickstart file: $ks_file"
  exit 1
fi

work_dir="$(mktemp -d)"
payload_dir="$work_dir/zz-linux-setup"
output_dir="$(dirname "$output_iso")"
output_base="$(basename "$output_iso")"
mkdir -p "$output_dir"
tmp_output="$(mktemp "$output_dir/.$output_base.tmp.XXXXXX")"
rm -f "$tmp_output"
trap 'rm -rf "$work_dir"; rm -f "$tmp_output"' EXIT

rsync -a --delete \
  --exclude='.cache/' \
  --exclude='downloads/' \
  --exclude='release/' \
  --exclude='test-artifacts/' \
  --exclude='livemedia.log' \
  --exclude='program.log' \
  --exclude='*.iso' \
  "$repo_dir/" "$payload_dir/"

mkksiso_args=(
  --add "$payload_dir"
  --ks "$ks_file"
)
if [[ "$skip_mkefiboot" -eq 1 ]]; then
  mkksiso_args+=(--skip-mkefiboot)
fi
mkksiso_args+=("$input_iso" "$tmp_output")

mkksiso "${mkksiso_args[@]}"

mv -f "$tmp_output" "$output_iso"
printf 'Created %s\n' "$output_iso"
