#!/usr/bin/env bash
set -Eeuo pipefail

PCI_DEVICES_ROOT="${ZZ_PCI_DEVICES_ROOT:-/sys/bus/pci/devices}"
INTEL_MEDIA_PCI_IDS_FILE="${ZZ_INTEL_MEDIA_PCI_IDS_FILE:-$ROOT_DIR/config/intel-media-pci-ids.conf}"

hardware_read_sysfs_value() {
  local path="$1"
  local value
  IFS= read -r value <"$path" || return 1
  printf '%s\n' "${value,,}"
}

hardware_display_pci_devices() {
  [[ -d "$PCI_DEVICES_ROOT" ]] || return 0

  local device_path class vendor device driver
  for device_path in "$PCI_DEVICES_ROOT"/*; do
    [[ -d "$device_path" && -r "$device_path/class" && -r "$device_path/vendor" && -r "$device_path/device" ]] || continue
    class="$(hardware_read_sysfs_value "$device_path/class")" || continue
    [[ "$class" == 0x03* ]] || continue

    vendor="$(hardware_read_sysfs_value "$device_path/vendor")" || continue
    device="$(hardware_read_sysfs_value "$device_path/device")" || continue
    driver="unbound"
    if [[ -L "$device_path/driver" ]]; then
      driver="$(basename "$(readlink -f "$device_path/driver")")"
    fi

    printf '%s\t%s\t%s\t%s\n' "$(basename "$device_path")" "$vendor" "$device" "$driver"
  done
}

intel_media_driver_package_for_device() {
  local device_id="${1,,}"
  device_id="${device_id#0x}"
  [[ "$device_id" =~ ^[0-9a-f]{4}$ && -r "$INTEL_MEDIA_PCI_IDS_FILE" ]] || return 1

  awk -v wanted="$device_id" '
    /^[[:space:]]*#/ || NF < 2 { next }
    {
      for (field = 2; field <= NF; field++) {
        if (tolower($field) == wanted) {
          print $1
          found = 1
          exit
        }
      }
    }
    END { exit found ? 0 : 1 }
  ' "$INTEL_MEDIA_PCI_IDS_FILE"
}

media_hardware_acceleration_targets() {
  local address vendor device driver package target
  while IFS=$'\t' read -r address vendor device driver; do
    [[ -n "$address" ]] || continue
    package=""
    if [[ "$driver" == "vfio-pci" ]]; then
      target="vfio"
    else
      case "$vendor" in
        0x1002)
          target="amd"
          ;;
        0x8086)
          package="$(intel_media_driver_package_for_device "$device" || true)"
          if [[ -n "$package" ]]; then
            target="intel"
          else
            target="intel-unknown"
          fi
          ;;
        0x10de)
          target="nvidia"
          ;;
        *)
          target="unsupported"
          ;;
      esac
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$target" "$address" "$vendor" "$device" "$driver" "$package"
  done < <(hardware_display_pci_devices)
}

install_fedora_amd_media_driver() {
  if rpm -q mesa-va-drivers-freeworld.x86_64 >/dev/null 2>&1; then
    :
  elif rpm -q mesa-va-drivers.x86_64 >/dev/null 2>&1; then
    run_cmd_as_root dnf swap -y mesa-va-drivers.x86_64 mesa-va-drivers-freeworld.x86_64 --allowerasing || return 1
  else
    run_cmd_as_root dnf install -y mesa-va-drivers-freeworld.x86_64 || return 1
  fi

  if rpm -q mesa-va-drivers-freeworld.i686 >/dev/null 2>&1; then
    :
  elif rpm -q mesa-va-drivers.i686 >/dev/null 2>&1; then
    run_cmd_as_root dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686 --allowerasing || return 1
  fi
}

install_fedora_media_hardware_acceleration() {
  local target address vendor device driver package
  local install_amd=0
  local -a intel_packages=()

  while IFS=$'\t' read -r target address vendor device driver package; do
    [[ -n "$target" ]] || continue
    case "$target" in
      amd)
        install_amd=1
        log_info "Detected AMD display device $address ($device, driver: $driver)."
        ;;
      intel)
        append_unique intel_packages "$package"
        log_info "Detected supported Intel display device $address ($device, driver: $driver): $package."
        ;;
      intel-unknown)
        log_warn "Unknown Intel display device $address ($device); skipping automatic media-driver selection."
        append_warning "Hardware media acceleration skipped for unknown Intel PCI device $device at $address."
        ;;
      nvidia)
        log_info "Detected NVIDIA display device $address ($device); NVIDIA media-driver setup is intentionally out of scope."
        ;;
      vfio)
        log_info "Skipping display device $address ($vendor:$device) because it is bound to vfio-pci."
        ;;
      unsupported)
        log_info "No managed media driver for display device $address ($vendor:$device, driver: $driver)."
        ;;
    esac
  done < <(media_hardware_acceleration_targets)

  if [[ "$install_amd" -eq 1 ]]; then
    log_progress "Installing AMD hardware media acceleration"
    install_fedora_amd_media_driver || return 1
  fi

  for package in "${intel_packages[@]:-}"; do
    [[ -n "$package" ]] || continue
    log_progress "Installing Intel hardware media acceleration package: $package"
    run_cmd_as_root dnf install -y "$package" || return 1
  done

  if [[ "$install_amd" -eq 0 && "${#intel_packages[@]}" -eq 0 ]]; then
    log_info "No supported AMD or Intel display device requires managed hardware media packages."
  fi
}

verify_fedora_media_hardware_acceleration() {
  local target _address _vendor _device _driver package
  local -a required_packages=()

  while IFS=$'\t' read -r target _address _vendor _device _driver package; do
    case "$target" in
      amd)
        append_unique required_packages mesa-va-drivers-freeworld.x86_64
        ;;
      intel)
        append_unique required_packages "$package"
        ;;
    esac
  done < <(media_hardware_acceleration_targets)

  for package in "${required_packages[@]:-}"; do
    [[ -n "$package" ]] || continue
    rpm -q "$package" >/dev/null 2>&1 || return 1
  done
}
