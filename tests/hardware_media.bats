#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  PCI_DEVICES_ROOT="$TEST_ROOT/pci/devices"
  mkdir -p "$PCI_DEVICES_ROOT" "$TEST_ROOT/pci/drivers"
}

make_pci_device() {
  local address="$1"
  local class="$2"
  local vendor="$3"
  local device="$4"
  local driver="${5:-unbound}"
  local device_path="$PCI_DEVICES_ROOT/$address"

  mkdir -p "$device_path"
  printf '%s\n' "$class" >"$device_path/class"
  printf '%s\n' "$vendor" >"$device_path/vendor"
  printf '%s\n' "$device" >"$device_path/device"
  if [[ "$driver" != "unbound" ]]; then
    mkdir -p "$TEST_ROOT/pci/drivers/$driver"
    ln -s "$TEST_ROOT/pci/drivers/$driver" "$device_path/driver"
  fi
}

@test "hardware media targets classify display devices from sysfs" {
  make_pci_device 0000:00:01.0 0x030000 0x8086 0x7D55 i915
  make_pci_device 0000:00:02.0 0x030000 0x8086 0x0412 i915
  make_pci_device 0000:01:00.0 0x030000 0x1002 0x73bf amdgpu
  make_pci_device 0000:02:00.0 0x030200 0x10de 0x2684 nvidia
  make_pci_device 0000:03:00.0 0x030000 0x1002 0x744c vfio-pci
  make_pci_device 0000:04:00.0 0x030000 0x1af4 0x1050 virtio-pci
  make_pci_device 0000:05:00.0 0x040300 0x8086 0x51ca snd-hda-intel

  run media_hardware_acceleration_targets

  [ "$status" -eq 0 ]
  normalized_output="$(sed $'s/\t$//' <<<"$output")"
  assert_equal "$(cat <<'EOF'
intel	0000:00:01.0	0x8086	0x7d55	i915	intel-media-driver
intel	0000:00:02.0	0x8086	0x0412	i915	libva-intel-driver
amd	0000:01:00.0	0x1002	0x73bf	amdgpu
nvidia	0000:02:00.0	0x10de	0x2684	nvidia
vfio	0000:03:00.0	0x1002	0x744c	vfio-pci
unsupported	0000:04:00.0	0x1af4	0x1050	virtio-pci
EOF
)" "$normalized_output"
}

@test "Intel media lookup rejects valid but unmapped PCI device IDs" {
  run intel_media_driver_package_for_device 0xffff

  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "hardware media action installs AMD and Intel packages but skips NVIDIA" {
  make_pci_device 0000:00:02.0 0x030000 0x8086 0x7d55 i915
  make_pci_device 0000:00:02.1 0x038000 0x8086 0x7d55 i915
  make_pci_device 0000:00:03.0 0x030000 0x8086 0x0412 i915
  make_pci_device 0000:01:00.0 0x030000 0x1002 0x73bf amdgpu
  make_pci_device 0000:02:00.0 0x030200 0x10de 0x2684 nvidia
  command_log="$TEST_ROOT/hardware-media-commands.log"
  rpm() {
    [[ "$*" == "-q mesa-va-drivers.x86_64" ]]
  }
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
  }

  run install_fedora_media_hardware_acceleration

  [ "$status" -eq 0 ]
  assert_equal "$(cat <<'EOF'
dnf swap -y mesa-va-drivers.x86_64 mesa-va-drivers-freeworld.x86_64 --allowerasing
dnf install -y intel-media-driver
dnf install -y libva-intel-driver
EOF
)" "$(<"$command_log")"
  assert_contains "$output" "NVIDIA media-driver setup is intentionally out of scope"
}

@test "AMD media setup is idempotent when the freeworld driver is installed" {
  make_pci_device 0000:01:00.0 0x030000 0x1002 0x73bf amdgpu
  command_log="$TEST_ROOT/amd-media-idempotent-commands.log"
  : >"$command_log"
  rpm() {
    [[ "$*" == "-q mesa-va-drivers-freeworld.x86_64" ]]
  }
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
  }

  run install_fedora_media_hardware_acceleration

  [ "$status" -eq 0 ]
  [ ! -s "$command_log" ]
}

@test "AMD media setup swaps i686 only when its Fedora driver is installed" {
  make_pci_device 0000:01:00.0 0x030000 0x1002 0x73bf amdgpu
  command_log="$TEST_ROOT/amd-media-commands.log"
  rpm() {
    [[ "$*" == "-q mesa-va-drivers.x86_64" || "$*" == "-q mesa-va-drivers.i686" ]]
  }
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
  }

  run install_fedora_media_hardware_acceleration

  [ "$status" -eq 0 ]
  assert_equal "$(cat <<'EOF'
dnf swap -y mesa-va-drivers.x86_64 mesa-va-drivers-freeworld.x86_64 --allowerasing
dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686 --allowerasing
EOF
)" "$(<"$command_log")"
}

@test "AMD media setup propagates an i686 swap failure" {
  make_pci_device 0000:01:00.0 0x030000 0x1002 0x73bf amdgpu
  rpm() {
    [[ "$*" == "-q mesa-va-drivers.x86_64" || "$*" == "-q mesa-va-drivers.i686" ]]
  }
  run_cmd_as_root() {
    [[ "$*" != *"mesa-va-drivers.i686"* ]]
  }

  run install_fedora_media_hardware_acceleration

  [ "$status" -eq 1 ]
}

@test "unsupported, VFIO, NVIDIA, and unknown Intel devices are safe no-ops" {
  make_pci_device 0000:00:02.0 0x030000 0x8086 0xffff i915
  make_pci_device 0000:01:00.0 0x030000 0x10de 0x2684 nvidia
  make_pci_device 0000:02:00.0 0x030000 0x1002 0x744c vfio-pci
  make_pci_device 0000:03:00.0 0x030000 0x1af4 0x1050 virtio-pci
  run_cmd_as_root() {
    printf 'unexpected privileged command: %s\n' "$*" >&2
    return 1
  }

  run install_fedora_media_hardware_acceleration

  [ "$status" -eq 0 ]
  assert_contains "$output" "Unknown Intel display device"
  assert_contains "$output" "NVIDIA media-driver setup is intentionally out of scope"
  assert_contains "$output" "bound to vfio-pci"
  assert_contains "$output" "No managed media driver"
  refute_contains "$output" "unexpected privileged command"
}

@test "hardware media verification follows the detected package set" {
  make_pci_device 0000:00:02.0 0x030000 0x8086 0x7d55 i915
  make_pci_device 0000:01:00.0 0x030000 0x1002 0x73bf amdgpu
  rpm_log="$TEST_ROOT/hardware-media-rpm.log"
  rpm() {
    printf '%s\n' "$*" >>"$rpm_log"
  }

  run verify_fedora_media_hardware_acceleration

  [ "$status" -eq 0 ]
  assert_equal "$(cat <<'EOF'
-q intel-media-driver
-q mesa-va-drivers-freeworld.x86_64
EOF
)" "$(<"$rpm_log")"
}
