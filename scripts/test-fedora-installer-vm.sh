#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/test-fedora-installer-vm.sh --input ISO [--work-dir DIR] [--boot-mode direct|uefi]

Run an unattended QEMU install that exercises the Fedora ISO post-install path.
The generated test ISO uses the same embedded checkout and installer invocation
as iso/fedora/zz-fedora.ks, but adds VM-only storage, user, and shutdown
Kickstart commands. The default direct boot mode boots the generated ISO's
kernel and initrd directly while mounting the generated ISO as the install
source. Use --boot-mode uefi to boot through the generated ISO firmware path.
EOF
}

err() {
  printf 'test-fedora-installer-vm: %s\n' "$*" >&2
}

input_iso=
work_dir=
memory=4096
cpus=4
disk_size=64G
timeout_seconds=14400
boot_mode=direct

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
  direct|uefi)
    ;;
  *)
    err "unsupported boot mode: $boot_mode"
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

for command in mkksiso qemu-img qemu-system-x86_64 rsync timeout xorriso; do
  if ! command -v "$command" >/dev/null 2>&1; then
    err "missing required command: $command"
    exit 1
  fi
done

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "$work_dir" ]]; then
  work_dir="$repo_dir/test-artifacts/fedora-installer-vm"
fi

rm -rf "$work_dir"
mkdir -p "$work_dir"

ks_file="$work_dir/zz-fedora-vm.ks"
payload_dir="$work_dir/payload/zz-linux-setup"
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

cat >"$ks_file" <<'EOF'
# VM-only unattended test profile for zz-linux-setup.
text
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

url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch"
repo --name="updates" --metalink="https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch" --install

services --enabled=NetworkManager

%packages
@core
sudo
ca-certificates
curl
git
gum
bats
dnf-plugins-core
dnf5-plugins
rsync
%end

%post --nochroot --interpreter=/usr/bin/bash --erroronfail --log=/mnt/sysimage/root/zz-linux-setup-copy.log
set -Eeuo pipefail

install -d -m 0755 /mnt/sysimage/opt
rm -rf /mnt/sysimage/opt/zz-linux-setup
cp -a /run/install/repo/zz-linux-setup /mnt/sysimage/opt/zz-linux-setup
%end

%post --interpreter=/usr/bin/bash --erroronfail --log=/root/zz-linux-setup-kickstart.log
set -Eeuo pipefail

repo_dir=/opt/zz-linux-setup
target_user=$(
  awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ "^/home/" && $7 !~ /(nologin|false)$/ { print $1; exit }' /etc/passwd
)

if [[ -z "$target_user" ]]; then
  echo "No installer-created regular user was found. Create a regular user in Anaconda before starting installation." >&2
  exit 1
fi

target_home=$(getent passwd "$target_user" | cut -d: -f6)
target_group=$(id -gn "$target_user")
target_repo_dir="$target_home/zz-linux-setup"

install -d -m 0755 "$target_home"
rm -rf "$target_repo_dir"
cp -a "$repo_dir" "$target_repo_dir"
chown -R "$target_user:$target_group" "$target_repo_dir"

install -d -m 0755 \
  "$target_home/.local" \
  "$target_home/.local/state" \
  "$target_home/.local/share" \
  "$target_home/.cache" \
  "$target_home/.config"
chown -R "$target_user:$target_group" \
  "$target_home/.local" \
  "$target_home/.cache" \
  "$target_home/.config"

export STATE_DIR="$target_home/.local/state/zz-linux-setup"
export CACHE_DIR="$target_home/.cache/zz-linux-setup"
export CONFIG_DIR="$target_home/.config/zz-linux-setup"
export LOG_DIR="$STATE_DIR/logs"
export STATE_OWNER_USER="$target_user"
export TARGET_USER="$target_user"
export DESKTOP_APP_PROFILE=full
export ZZ_INSTALLER_DEFER_START_SERVICES=1
if [[ -r /etc/locale.conf ]]; then
  source /etc/locale.conf
fi
case "${LANG:-}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
  *) LANG=C.UTF-8 ;;
esac
case "${LC_ALL:-}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
  *) LC_ALL="$LANG" ;;
esac
export LANG LC_ALL

cd "$target_repo_dir"
./install.sh install --yes --distro fedora --desktop-app-profile full --no-tui --target-user "$target_user"

rm -rf "$repo_dir"
%end
EOF

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
  --cmdline "console=ttyS0,115200n8 inst.cmdline"
  --replace 'set default="1"' 'set default="0"'
  --replace 'set timeout=60' 'set timeout=1'
  --add "$payload_dir"
  --ks "$ks_file"
  "$input_iso"
  "$test_iso"
)
if [[ "$EUID" -eq 0 ]]; then
  mkksiso "${mkksiso_args[@]}"
else
  sudo -n mkksiso "${mkksiso_args[@]}"
  sudo -n chown "$USER:$(id -gn)" "$test_iso"
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
  -display none \
  -serial "file:$serial_log" \
  -no-reboot
)

if [[ "$boot_mode" == "uefi" ]]; then
  qemu_args+=(
    -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
    -drive "if=pflash,format=raw,file=$ovmf_vars"
    -boot d
  )
else
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
    -append "inst.stage2=hd:LABEL=$iso_label inst.ks=hd:LABEL=$iso_label:/zz-fedora-vm.ks console=ttyS0,115200n8 inst.cmdline"
  )
fi

timeout "$timeout_seconds" qemu-system-x86_64 "${qemu_args[@]}" >"$qemu_log" 2>&1
