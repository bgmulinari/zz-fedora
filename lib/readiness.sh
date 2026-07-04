#!/usr/bin/env bash
set -Eeuo pipefail

readiness_file() {
  printf '%s/readiness/status.tsv\n' "$PLAN_DIR"
}

readiness_reset() {
  mkdir -p "$PLAN_DIR/readiness"
  : >"$(readiness_file)"
}

readiness_record() {
  local area="$1"
  local item="$2"
  local status="$3"
  local severity="$4"
  local detail="${5:-}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$area" "$item" "$status" "$severity" "$detail" >>"$(readiness_file)"
}

readiness_status_for_file() {
  local file="$1"
  [[ -f "$file" ]] && printf 'present' || printf 'missing'
}

readiness_status_for_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 && printf 'present' || printf 'missing'
}

readiness_package_status() {
  local backend="$1"
  local package_name="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'planned'
    return 0
  fi
  case "$backend" in
    dnf)
      if declare -F distro_package_installed >/dev/null 2>&1 && distro_package_installed "$package_name"; then
        printf 'installed'
      else
        printf 'missing'
      fi
      ;;
    flatpak)
      if have_cmd flatpak && flatpak info "$package_name" >/dev/null 2>&1; then
        printf 'installed'
      else
        printf 'missing'
      fi
      ;;
    *)
      printf 'planned'
      ;;
  esac
}

readiness_source_status() {
  local source_id="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'planned'
    return 0
  fi
  if declare -F distro_repo_enabled >/dev/null 2>&1 && distro_repo_enabled "$source_id"; then
    printf 'enabled'
  else
    printf 'missing'
  fi
}

readiness_service_status() {
  local service_name="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'planned'
    return 0
  fi
  if systemctl is-enabled "$service_name" >/dev/null 2>&1; then
    if systemctl is-active "$service_name" >/dev/null 2>&1; then
      printf 'enabled-active'
    else
      printf 'enabled-inactive'
    fi
  else
    printf 'missing'
  fi
}

readiness_generate_packages() {
  local backend plan_file package_name status severity
  for backend in dnf flatpak; do
    plan_file="$(package_file_for_backend "$backend")"
    [[ -f "$plan_file" ]] || continue
    while IFS= read -r package_name; do
      [[ -n "$package_name" ]] || continue
      status="$(readiness_package_status "$backend" "$package_name")"
      severity="info"
      [[ "$status" == "missing" ]] && severity="warn"
      readiness_record "package:$backend" "$package_name" "$status" "$severity" ""
    done < <(read_plan_file "$plan_file")
  done
}

readiness_generate_sources() {
  local source_file source_id status severity
  for source_file in "$PLAN_DIR"/sources/*.list; do
    [[ -f "$source_file" ]] || continue
    while IFS= read -r source_id; do
      [[ -n "$source_id" ]] || continue
      status="$(readiness_source_status "$source_id")"
      severity="info"
      load_source_descriptor "$DISTRO" "$source_id" || true
      if [[ "${SOURCE_REQUIRED:-0}" -eq 1 && "$status" == "missing" ]]; then
        severity="fatal"
      elif [[ "$status" == "missing" ]]; then
        severity="warn"
      fi
      readiness_record "source" "$source_id" "$status" "$severity" "${SOURCE_LABEL:-}"
    done < <(read_plan_file "$source_file")
  done
}

readiness_generate_services() {
  local service_file service_name status severity
  for service_file in "$PLAN_DIR"/services/*.list; do
    [[ -f "$service_file" ]] || continue
    while IFS= read -r service_name; do
      [[ -n "$service_name" ]] || continue
      status="$(readiness_service_status "$service_name")"
      severity="info"
      [[ "$status" == "missing" ]] && severity="fatal"
      readiness_record "service" "$service_name" "$status" "$severity" ""
    done < <(read_plan_file "$service_file")
  done
}

readiness_generate_display_manager_conflicts() {
  local service_name
  while IFS= read -r service_name; do
    [[ -n "$service_name" && "$service_name" != "display-manager.service" ]] || continue
    if [[ "$DRY_RUN" -eq 0 ]] && systemctl is-enabled "$service_name" >/dev/null 2>&1; then
      readiness_record "display-manager" "$service_name" "enabled" "warn" "Noctalia Greeter fallback will be skipped"
    fi
  done < <(known_display_manager_units)
}

readiness_generate_package_manager_locks() {
  local lock_path found=0
  for lock_path in \
    /var/lib/dnf/rpmdb_lock.pid \
    /var/cache/dnf/metadata_lock.pid \
    /var/lib/rpm/.rpm.lock; do
    if [[ -e "$lock_path" ]]; then
      readiness_record "package-manager" "$lock_path" "locked" "warn" "Another package transaction may be active"
      found=1
    fi
  done
  [[ "$found" -eq 1 ]] || readiness_record "package-manager" "locks" "clear" "info" ""
}

readiness_generate_disk_space() {
  local path available_mb severity
  path="$TARGET_HOME"
  [[ -d "$path" ]] || path="$STATE_DIR"
  available_mb="$(df -Pm "$path" 2>/dev/null | awk 'NR==2 {print $4+0}')"
  if [[ -z "$available_mb" || "$available_mb" -eq 0 ]]; then
    readiness_record "disk" "$path" "unknown" "warn" "Could not determine available space"
    return 0
  fi
  severity="info"
  [[ "$available_mb" -lt 10240 ]] && severity="warn"
  readiness_record "disk" "$path" "${available_mb}MB-free" "$severity" "Recommended: 10240MB+"
}

readiness_generate_network() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    readiness_record "network" "internet" "not-checked" "info" "Run install for live network validation"
    return 0
  fi
  if getent hosts fedoraproject.org >/dev/null 2>&1; then
    readiness_record "network" "fedoraproject.org" "reachable" "info" ""
  else
    readiness_record "network" "fedoraproject.org" "unreachable" "warn" "DNS or internet access may be unavailable"
  fi
}

readiness_generate_session_state() {
  local current_desktop="${XDG_CURRENT_DESKTOP:-unknown}"
  local desktop_session="${DESKTOP_SESSION:-unknown}"
  local severity="info"
  local status="detected"
  if [[ "$current_desktop" == *GNOME* || "$desktop_session" == *gnome* ]]; then
    severity="warn"
    status="gnome-session"
  fi
  readiness_record "session" "current-desktop" "$status" "$severity" "XDG_CURRENT_DESKTOP=$current_desktop DESKTOP_SESSION=$desktop_session"
}

readiness_generate_secure_boot() {
  if ! have_cmd mokutil; then
    readiness_record "secure-boot" "mokutil" "missing" "info" "Secure Boot state not checked"
    return 0
  fi
  local state
  state="$(mokutil --sb-state 2>/dev/null || true)"
  if grep -qi 'enabled' <<<"$state"; then
    readiness_record "secure-boot" "state" "enabled" "warn" "Unsigned kernel modules or drivers may need manual enrollment"
  elif grep -qi 'disabled' <<<"$state"; then
    readiness_record "secure-boot" "state" "disabled" "info" ""
  else
    readiness_record "secure-boot" "state" "unknown" "info" "$state"
  fi
}

readiness_generate_portals() {
  local command_name status severity
  for command_name in xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-gnome; do
    status="$(readiness_status_for_command "$command_name")"
    severity="info"
    [[ "$status" == "missing" ]] && severity="warn"
    readiness_record "portal" "command:$command_name" "$status" "$severity" ""
  done
  if [[ "$DRY_RUN" -eq 0 ]] && systemctl --user is-active xdg-desktop-portal.service >/dev/null 2>&1; then
    readiness_record "portal" "xdg-desktop-portal.service" "active" "info" ""
  elif [[ "$DRY_RUN" -eq 0 ]]; then
    readiness_record "portal" "xdg-desktop-portal.service" "inactive" "warn" ""
  else
    readiness_record "portal" "xdg-desktop-portal.service" "planned" "info" ""
  fi
}

readiness_generate_desktop_files() {
  local user_config_home="$TARGET_HOME/.config"
  local niri_config_home="$user_config_home/niri"
  local item status severity

  for item in \
    "$user_config_home/niri/config.kdl" \
    "$niri_config_home/cfg/autostart.kdl" \
    "$niri_config_home/cfg/keybinds.kdl" \
    "$niri_config_home/cfg/misc.kdl" \
    "$user_config_home/xdg-desktop-portal/niri-portals.conf" \
    "$user_config_home/environment.d/10-niri-gtk.conf"; do
    status="$(readiness_status_for_file "$item")"
    severity="info"
    [[ "$status" == "missing" ]] && severity="warn"
    readiness_record "file" "$item" "$status" "$severity" ""
  done

  status="$(readiness_status_for_command niri)"
  severity="info"
  [[ "$status" == "missing" ]] && severity="fatal"
  readiness_record "niri" "command:niri" "$status" "$severity" ""
  status="$(readiness_status_for_file /usr/share/wayland-sessions/niri.desktop)"
  severity="info"
  [[ "$status" == "missing" ]] && severity="fatal"
  readiness_record "niri" "/usr/share/wayland-sessions/niri.desktop" "$status" "$severity" ""

  status="$(readiness_status_for_command noctalia)"
  severity="info"
  [[ "$status" == "missing" ]] && severity="fatal"
  readiness_record "noctalia-v5" "command:noctalia" "$status" "$severity" "Expected package: noctalia-git"
}

readiness_generate_target_home() {
  local owner status severity
  if [[ -d "$TARGET_HOME" ]]; then
    owner="$(stat -c %U "$TARGET_HOME" 2>/dev/null || true)"
    if [[ "$owner" == "$TARGET_USER" ]]; then
      status="owned"
      severity="info"
    else
      status="owner-mismatch"
      severity="warn"
    fi
    readiness_record "target-home" "$TARGET_HOME" "$status" "$severity" "owner=${owner:-unknown}"
  else
    readiness_record "target-home" "$TARGET_HOME" "missing" "fatal" ""
  fi
}

readiness_generate_config_conflicts() {
  local conflict_file="$PLAN_DIR/files/config-conflicts.tsv"
  local path package action
  [[ -f "$conflict_file" ]] || return 0
  while IFS=$'\t' read -r path package action; do
    [[ -n "$path" ]] || continue
    readiness_record "config-conflict" "$path" "conflict" "warn" "$package:$action"
  done <"$conflict_file"
}

readiness_generate_managed_config_policy() {
  local policy_file="$PLAN_DIR/files/managed-config-policy.tsv"
  local path mode conflict owner description
  [[ -f "$policy_file" ]] || return 0
  while IFS=$'\t' read -r path mode conflict owner description; do
    [[ -n "$path" ]] || continue
    readiness_record "managed-config" "$path" "$mode" "info" "$owner:$conflict ${description:-}"
  done <"$policy_file"
}

readiness_plan_has_entry() {
  local plan_file="$1"
  local entry="$2"
  [[ -f "$plan_file" ]] || return 1
  grep -Fx "$entry" "$plan_file" >/dev/null 2>&1
}

readiness_generate_key_commands() {
  local native_plan package_name command_name status severity
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  while IFS=$'\t' read -r package_name command_name; do
    readiness_plan_has_entry "$native_plan" "$package_name" || continue
    status="$(readiness_status_for_command "$command_name")"
    severity="info"
    [[ "$status" == "missing" ]] && severity="warn"
    readiness_record "command" "$command_name" "$status" "$severity" ""
  done <<'EOF'
niri	niri
niri	niri-session
noctalia-git	noctalia
ghostty	ghostty
xdg-terminal-exec	xdg-terminal-exec
nautilus	nautilus
brightnessctl	brightnessctl
ddcutil	ddcutil
papers	papers
loupe	loupe
showtime	showtime
decibels	org.gnome.Decibels
pavucontrol	pavucontrol
system-config-printer	system-config-printer
simple-scan	simple-scan
EOF
}

generate_readiness_status() {
  readiness_reset
  readiness_generate_package_manager_locks
  readiness_generate_disk_space
  readiness_generate_network
  readiness_generate_session_state
  readiness_generate_secure_boot
  readiness_generate_packages
  readiness_generate_sources
  readiness_generate_services
  readiness_generate_display_manager_conflicts
  readiness_generate_portals
  readiness_generate_desktop_files
  readiness_generate_target_home
  readiness_generate_config_conflicts
  readiness_generate_managed_config_policy
  readiness_generate_key_commands
}

readiness_fatal_count() {
  local file
  file="$(readiness_file)"
  [[ -f "$file" ]] || {
    printf '0\n'
    return 0
  }
  awk -F'\t' '$4=="fatal"{count++} END{print count+0}' "$file"
}

render_readiness_report() {
  local file
  file="$(readiness_file)"
  [[ -f "$file" ]] || generate_readiness_status

  printf 'Readiness:\n'
  awk -F'\t' 'NF>=4 {
    detail = $5 == "" ? "" : " - " $5
    printf "  [%s] %s %s: %s%s\n", $4, $1, $2, $3, detail
  }' "$file"
  printf 'Fatal readiness issues: %s\n' "$(readiness_fatal_count)"
}
