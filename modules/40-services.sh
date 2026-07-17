#!/usr/bin/env bash
set -Eeuo pipefail

service_package() {
  local service_name="$1"
  case "$service_name" in
    NetworkManager) printf 'NetworkManager\n' ;;
    bluetooth) printf 'bluez\n' ;;
    chronyd) printf 'chrony\n' ;;
    firewalld) printf 'firewalld\n' ;;
    tuned-ppd) printf 'tuned-ppd\n' ;;
    cups) printf 'cups\n' ;;
    avahi-daemon) printf 'avahi\n' ;;
    *) return 1 ;;
  esac
}

ensure_required_system_service() {
  local service_name="$1"
  local package_name=""

  if ! fedora_service_exists "$service_name"; then
    package_name="$(service_package "$service_name" || true)"
    [[ -n "$package_name" ]] || die "Required system service is not available and no package retry is known: $service_name"

    log_warn "$service_name.service was not detected after base package installation; retrying $package_name install."
    package_install_idempotent "$(native_backend)" "$package_name"
    run_cmd_as_root systemctl daemon-reload
  fi

  if ! fedora_service_exists "$service_name"; then
    die "Required system service is still not available after package retry: $service_name"
  fi
}

enable_required_system_services_now() {
  local -a service_names=("$@")
  local service_name
  [[ "${#service_names[@]}" -gt 0 ]] || return 0

  for service_name in "${service_names[@]}"; do
    ensure_required_system_service "$service_name" || return 1
  done

  fedora_enable_services_now "${service_names[@]}"
}
