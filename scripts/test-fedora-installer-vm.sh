#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_TOOL_NAME="test-fedora-installer-vm"
# shellcheck source=lib/iso-common.sh
source "$repo_dir/scripts/lib/iso-common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/test-fedora-installer-vm.sh --input ISO [--input-sha256 HASH] [--work-dir DIR] [--boot-mode iso|direct|uefi] [--installer-ui graphical|text] [--graphics vnc|none|egl-headless] [--desktop-app-profile full|minimal]

Run an unattended QEMU install that exercises the Fedora ISO add-on task path.
The generated test ISO uses the same remote runtime refresh and installer
invocation as the production add-on task, but adds VM-only storage, user, and
shutdown Kickstart commands. The default iso boot mode boots through the
generated ISO bootloader. Use --boot-mode direct to boot the generated ISO's
kernel and initrd directly, or --boot-mode uefi to exercise the generated ISO
UEFI firmware path.
The default graphical installer UI uses a local QEMU VNC display; use
--installer-ui text for serial-console debugging.
Use --graphics egl-headless for a headless virtio GL device suitable for
post-install Niri/Wayland validation.
The desktop app profile defaults to full; use --desktop-app-profile minimal
to exercise the minimal Niri/Noctalia baseline.
EOF
}

err() {
  iso_err "$@"
}

input_iso=
input_sha256=
work_dir=
memory=4096
cpus=4
disk_size=64G
timeout_seconds=14400
boot_mode=iso
installer_ui=graphical
graphics_mode=vnc
desktop_app_profile=full
vnc_display=127.0.0.1:99
fedora_release=
fedora_arch=

while (($# > 0)); do
  case "$1" in
    --input)
      (($# >= 2)) || {
        err "--input requires a value."
        exit 1
      }
      input_iso=$2
      shift 2
      ;;
    --input=*)
      input_iso=${1#*=}
      shift
      ;;
    --work-dir)
      (($# >= 2)) || {
        err "--work-dir requires a value."
        exit 1
      }
      work_dir=$2
      shift 2
      ;;
    --input-sha256)
      (($# >= 2)) || {
        err "--input-sha256 requires a value."
        exit 1
      }
      input_sha256=$2
      shift 2
      ;;
    --input-sha256=*)
      input_sha256=${1#*=}
      shift
      ;;
    --work-dir=*)
      work_dir=${1#*=}
      shift
      ;;
    --memory)
      (($# >= 2)) || {
        err "--memory requires a value."
        exit 1
      }
      memory=$2
      shift 2
      ;;
    --cpus)
      (($# >= 2)) || {
        err "--cpus requires a value."
        exit 1
      }
      cpus=$2
      shift 2
      ;;
    --timeout)
      (($# >= 2)) || {
        err "--timeout requires a value."
        exit 1
      }
      timeout_seconds=$2
      shift 2
      ;;
    --boot-mode)
      (($# >= 2)) || {
        err "--boot-mode requires a value."
        exit 1
      }
      boot_mode=$2
      shift 2
      ;;
    --boot-mode=*)
      boot_mode=${1#*=}
      shift
      ;;
    --installer-ui)
      (($# >= 2)) || {
        err "--installer-ui requires a value."
        exit 1
      }
      installer_ui=$2
      shift 2
      ;;
    --installer-ui=*)
      installer_ui=${1#*=}
      shift
      ;;
    --graphics)
      (($# >= 2)) || {
        err "--graphics requires a value."
        exit 1
      }
      graphics_mode=$2
      shift 2
      ;;
    --graphics=*)
      graphics_mode=${1#*=}
      shift
      ;;
    --desktop-app-profile)
      (($# >= 2)) || {
        err "--desktop-app-profile requires a value."
        exit 1
      }
      desktop_app_profile=$2
      shift 2
      ;;
    --desktop-app-profile=*)
      desktop_app_profile=${1#*=}
      shift
      ;;
    --vnc-display)
      (($# >= 2)) || {
        err "--vnc-display requires a value."
        exit 1
      }
      vnc_display=$2
      shift 2
      ;;
    --vnc-display=*)
      vnc_display=${1#*=}
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

case "$boot_mode" in
  iso|direct|uefi)
    ;;
  *)
    err "unsupported boot mode: $boot_mode"
    exit 1
    ;;
esac

case "$installer_ui" in
  graphical|text)
    ;;
  *)
    err "unsupported installer UI: $installer_ui"
    exit 1
    ;;
esac

case "$graphics_mode" in
  vnc|none|egl-headless)
    ;;
  *)
    err "unsupported graphics mode: $graphics_mode"
    exit 1
    ;;
esac

case "$desktop_app_profile" in
  full|minimal)
    ;;
  *)
    err "unsupported desktop app profile: $desktop_app_profile"
    exit 1
    ;;
esac

if [[ -z "$input_iso" ]]; then
  usage >&2
  exit 1
fi

if [[ ! -f "$input_iso" ]]; then
  err "input ISO not found: $input_iso"
  exit 1
fi

if [[ -n "$input_sha256" ]]; then
  iso_verify_sha256 "$input_iso" "$input_sha256"
fi

for command in cpio gzip mkksiso qemu-img qemu-system-x86_64 rsync timeout xorriso; do
  if ! command -v "$command" >/dev/null 2>&1; then
    err "missing required command: $command"
    exit 1
  fi
done

iso_extract_fedora_metadata "$input_iso"
iso_validate_supported_platform "$fedora_release" "$fedora_arch"
addon_dir="$repo_dir/iso/anaconda-addon"
addon_data_dir="$repo_dir/iso/anaconda-addon-data"
if [[ ! -d "$addon_dir/org_zz_fedora" ]]; then
  err "missing Anaconda add-on payload: $addon_dir/org_zz_fedora"
  exit 1
fi
if [[ ! -d "$addon_data_dir" ]]; then
  err "missing Anaconda add-on data: $addon_data_dir"
  exit 1
fi
if [[ -z "$work_dir" ]]; then
  work_dir="$repo_dir/test-artifacts/fedora-installer-vm"
fi

rm -rf "$work_dir"
mkdir -p "$work_dir"
work_dir="$(cd "$work_dir" && pwd)"

ks_file="$work_dir/zz-fedora-vm.ks"
payload_dir="$work_dir/payload/zz-fedora"
product_root="$work_dir/product"
images_dir="$work_dir/images"
product_img="$images_dir/product.img"
test_iso="$work_dir/zz-fedora-vm.iso"
disk_image="$work_dir/fedora-vm.qcow2"
serial_log="$work_dir/serial.log"
qemu_log="$work_dir/qemu.log"
ovmf_code=/usr/share/edk2/ovmf/OVMF_CODE.fd
ovmf_vars_template=/usr/share/edk2/ovmf/OVMF_VARS.fd
ovmf_vars="$work_dir/OVMF_VARS.fd"
kernel_image="$work_dir/vmlinuz"
initrd_image="$work_dir/initrd.img"

mkdir -p "$(dirname "$payload_dir")"

if [[ "$boot_mode" == "uefi" && (! -f "$ovmf_code" || ! -f "$ovmf_vars_template") ]]; then
  err "OVMF firmware not found. Install edk2-ovmf."
  exit 1
fi

{
  printf '# VM-only unattended test profile for zz-fedora.\n'
  printf '%s\n' "$installer_ui"
  cat <<'EOF'
eula --agreed
keyboard --xlayouts='us'
lang en_US.UTF-8
timezone Etc/UTC --utc
rootpw --plaintext fedora
user --name=zztest --password=fedora --plaintext --groups=wheel

network --bootproto=dhcp --activate --hostname=zz-fedora-iso-test

firstboot --disable
selinux --enforcing
shutdown

ignoredisk --only-use=vda
zerombr
clearpart --all --initlabel --drives=vda
autopart --type=lvm
bootloader --location=mbr --append="console=ttyS0,115200n8"

EOF
  printf 'url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-%s&arch=%s"\n' "$fedora_release" "$fedora_arch"
  printf 'repo --name="updates"\n'
  cat <<EOF

services --enabled=NetworkManager

%packages
@core
sudo
ca-certificates
curl
dnf5-plugins
%end

%pre --interpreter=/usr/bin/bash
set -Eeuo pipefail
install -d -m 0700 /run/zz-fedora
printf 'selected=1\ndesktop_app_profile=$desktop_app_profile\n' >/run/zz-fedora/install-selected
chmod 0600 /run/zz-fedora/install-selected
%end
EOF
} >"$ks_file"

iso_stage_tracked_runtime_payload "$repo_dir" "$payload_dir"

mkdir -p \
  "$product_root/etc/anaconda/conf.d" \
  "$product_root/etc/zz-fedora" \
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
printf '%s\n' "$desktop_app_profile" >"$product_root/etc/zz-fedora/desktop-app-profile"
cat >"$product_root/etc/anaconda/conf.d/100-zz-fedora.conf" <<'EOF'
[User Interface]
hidden_spokes =
    SoftwareSelectionSpoke
EOF
cat >"$product_root/.buildstamp" <<EOF
[Main]
Product=ZZ Fedora
Version=$fedora_release
BugURL=https://github.com/bgmulinari/zz-fedora
IsFinal=True

[Compose]
Lorax=zz-fedora
EOF
(
  cd "$product_root"
  find . -print | sort | cpio --quiet -c -o | gzip -9c >"$product_img"
)

mkksiso_args=(
  --replace 'set default="1"' 'set default="0"'
  --replace 'set timeout=60' 'set timeout=1'
  --add "$payload_dir"
  --add "$images_dir"
  --ks "$ks_file"
  "$input_iso"
  "$test_iso"
)
if [[ "$installer_ui" == "text" ]]; then
  mkksiso_args=(
    --cmdline "console=ttyS0,115200n8 inst.cmdline"
    "${mkksiso_args[@]}"
  )
fi
if [[ "$EUID" -eq 0 ]]; then
  mkksiso "${mkksiso_args[@]}"
else
  sudo -n mkksiso "${mkksiso_args[@]}"
  sudo -n chown "$(id -un):$(id -gn)" "$test_iso"
fi
qemu-img create -f qcow2 "$disk_image" "$disk_size" >/dev/null
if [[ "$boot_mode" == "uefi" ]]; then
  cp "$ovmf_vars_template" "$ovmf_vars"
fi

printf 'Work dir: %s\n' "$work_dir"
printf 'Test ISO: %s\n' "$test_iso"
printf 'Disk image: %s\n' "$disk_image"
printf 'Serial log: %s\n' "$serial_log"
printf 'QEMU log: %s\n' "$qemu_log"
printf 'Boot mode: %s\n' "$boot_mode"
printf 'Installer UI: %s\n' "$installer_ui"
printf 'Graphics: %s\n' "$graphics_mode"
printf 'Desktop app profile: %s\n' "$desktop_app_profile"
if [[ "$graphics_mode" == "vnc" ]]; then
  printf 'VNC display: %s\n' "$vnc_display"
fi

display_args=()
case "$graphics_mode" in
  vnc)
    display_args=(-display "vnc=$vnc_display")
    ;;
  none)
    display_args=(-display none)
    ;;
  egl-headless)
    display_args=(-display egl-headless,gl=on -vga none -device virtio-vga-gl)
    ;;
esac

qemu_args=(
  -enable-kvm
  -m "$memory" \
  -smp "$cpus" \
  -cpu host \
  -name zz-fedora-installer-vm \
  -drive "file=$disk_image,format=qcow2,if=virtio" \
  -cdrom "$test_iso" \
  -netdev user,id=n0 \
  -device virtio-net-pci,netdev=n0 \
  "${display_args[@]}" \
  -serial "file:$serial_log" \
  -no-reboot
)

if [[ "$boot_mode" == "uefi" ]]; then
  qemu_args+=(
    -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
    -drive "if=pflash,format=raw,file=$ovmf_vars"
    -boot d
  )
elif [[ "$boot_mode" == "direct" ]]; then
  xorriso -osirrox on \
    -indev "$test_iso" \
    -extract /images/pxeboot/vmlinuz "$kernel_image" \
    -extract /images/pxeboot/initrd.img "$initrd_image" \
    >/dev/null
  iso_label="$(
    xorriso -indev "$test_iso" -pvd_info 2>/dev/null |
      awk -F: '$1 ~ /Volume Id/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }'
  )"
  [[ -n "$iso_label" ]] || {
    err "could not determine generated ISO label"
    exit 1
  }
  qemu_args+=(
    -kernel "$kernel_image"
    -initrd "$initrd_image"
  )
  direct_append="inst.stage2=hd:LABEL=$iso_label inst.ks=hd:LABEL=$iso_label:/zz-fedora-vm.ks"
  if [[ "$installer_ui" == "text" ]]; then
    direct_append+=" console=ttyS0,115200n8 inst.cmdline"
  fi
  qemu_args+=(-append "$direct_append")
else
  qemu_args+=(-boot d)
fi

timeout "$timeout_seconds" qemu-system-x86_64 "${qemu_args[@]}" >"$qemu_log" 2>&1

if [[ "$installer_ui" == "text" ]]; then
  if ! grep -aFq 'ZZ Fedora (9/9): Completed Doctor' "$serial_log"; then
    err "headless install exited without the Doctor completion marker; inspect $serial_log"
    exit 1
  fi
  if ! grep -aFq 'ZZ Fedora complete' "$serial_log"; then
    err "headless install exited without the final completion marker; inspect $serial_log"
    exit 1
  fi
  printf 'Verified headless install completion markers in %s\n' "$serial_log"
fi
