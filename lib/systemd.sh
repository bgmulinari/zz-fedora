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
