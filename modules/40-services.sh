#!/usr/bin/env bash
set -Eeuo pipefail

service_package_for_distro() {
  local service_name="$1"
  case "$DISTRO:$service_name" in
    fedora:NetworkManager) printf 'NetworkManager\n' ;;
    fedora:bluetooth) printf 'bluez\n' ;;
    fedora:chronyd) printf 'chrony\n' ;;
    fedora:firewalld) printf 'firewalld\n' ;;
    fedora:power-profiles-daemon) printf 'power-profiles-daemon\n' ;;
    arch:NetworkManager) printf 'networkmanager\n' ;;
    arch:bluetooth) printf 'bluez\n' ;;
    arch:chronyd) printf 'chrony\n' ;;
    arch:firewalld) printf 'firewalld\n' ;;
    arch:power-profiles-daemon) printf 'power-profiles-daemon\n' ;;
    *) return 1 ;;
  esac
}

enable_required_system_service_now() {
  local service_name="$1"
  local package_name=""

  if ! distro_service_exists "$service_name"; then
    package_name="$(service_package_for_distro "$service_name" || true)"
    [[ -n "$package_name" ]] || die "Required system service is not available and no package retry is known: $service_name"

    log_warn "$service_name.service was not detected after base package installation; retrying $package_name install."
    package_install_idempotent "$(native_backend_for_distro "$DISTRO")" "$package_name"
    run_cmd_as_root systemctl daemon-reload
  fi

  if ! distro_service_exists "$service_name"; then
    die "Required system service is still not available after package retry: $service_name"
  fi

  distro_enable_service_now "$service_name"
}
