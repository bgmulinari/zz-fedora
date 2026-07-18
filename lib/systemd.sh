#!/usr/bin/env bash
set -Eeuo pipefail

system_services_now_from_plan() {
  read_plan_file "$PLAN_DIR/services/system-enable-now.list"
}

system_services_from_plan() {
  read_plan_file "$PLAN_DIR/services/system-enable.list"
}

user_services_from_plan() {
  read_plan_file "$PLAN_DIR/services/user-enable.list"
}

enable_user_service() {
  local service_name="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "${ZZ_INSTALLER_DEFER_START_SERVICES:-0}" -eq 1 ]]; then
      printf 'DRY-RUN: systemctl --global enable %s\n' "$service_name"
    else
      printf 'DRY-RUN: systemctl --user enable --now %s\n' "$service_name"
    fi
    return 0
  fi

  if [[ "${ZZ_INSTALLER_DEFER_START_SERVICES:-0}" -eq 1 ]]; then
    run_cmd_as_root systemctl --global enable "$service_name"
    return $?
  fi

  if run_cmd_as_user "$TARGET_USER" systemctl --user enable --now "$service_name"; then
    return 0
  fi

  [[ "$EUID" -eq 0 ]] || return 1
  run_cmd_as_root systemctl --global enable "$service_name"
}

enable_user_services() {
  local service_name
  while IFS= read -r service_name; do
    [[ -n "$service_name" ]] || continue
    log_progress "Enabling user service: $service_name"
    enable_user_service "$service_name" || log_warn "Could not enable user service: $service_name"
  done < <(user_services_from_plan)
}

systemd_unit_file_exists() {
  local service_name="$1"
  local unit_name="${service_name%.service}.service"
  [[ "$DRY_RUN" -eq 1 ]] && return 0

  if systemctl list-unit-files "$unit_name" --no-legend --no-pager 2>/dev/null | awk -v unit="$unit_name" '$1 == unit { found = 1 } END { exit !found }'; then
    return 0
  fi

  local unit_path
  for unit_path in \
    "/etc/systemd/system/$unit_name" \
    "/run/systemd/system/$unit_name" \
    "/usr/local/lib/systemd/system/$unit_name" \
    "/usr/lib/systemd/system/$unit_name" \
    "/lib/systemd/system/$unit_name"; do
    [[ -e "$unit_path" || -L "$unit_path" ]] && return 0
  done

  return 1
}

known_display_manager_units() {
  printf '%s\n' \
    sddm.service \
    plasmalogin.service \
    gdm.service \
    gdm3.service \
    lightdm.service \
    ly.service \
    greetd.service \
    lxdm.service \
    slim.service \
    xdm.service \
    display-manager.service
}

systemd_unit_enabled() {
  local service_name="$1"
  local unit_name="${service_name%.service}.service"
  [[ "$DRY_RUN" -eq 1 ]] && return 1
  systemctl is-enabled "$unit_name" >/dev/null 2>&1
}

detect_enabled_display_manager() {
  [[ "$DRY_RUN" -eq 1 ]] && return 1

  local unit_name
  while IFS= read -r unit_name; do
    [[ -n "$unit_name" ]] || continue
    if systemd_unit_enabled "$unit_name"; then
      printf '%s\n' "$unit_name"
      return 0
    fi
  done < <(known_display_manager_units)

  return 1
}

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
