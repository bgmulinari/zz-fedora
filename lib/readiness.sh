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
  for service_name in gdm.service lightdm.service ly.service; do
    if [[ "$DRY_RUN" -eq 0 ]] && systemctl is-enabled "$service_name" >/dev/null 2>&1; then
      readiness_record "display-manager" "$service_name" "enabled" "warn" "May conflict with SDDM"
    fi
  done
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
    "$user_config_home/environment.d/10-niri-gtk.conf" \
    "$user_config_home/noctalia/settings.json" \
    "$user_config_home/noctalia/plugins.json" \
    "$user_config_home/noctalia/user-templates.toml"; do
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

  status="$(readiness_status_for_command qs)"
  severity="info"
  [[ "$status" == "missing" ]] && severity="fatal"
  readiness_record "noctalia-v4" "command:qs" "$status" "$severity" "Expected package: noctalia-shell"
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

readiness_generate_key_commands() {
  local command_name status severity
  for command_name in ghostty xdg-terminal-exec nautilus satty brightnessctl ddcutil; do
    status="$(readiness_status_for_command "$command_name")"
    severity="info"
    [[ "$status" == "missing" ]] && severity="warn"
    readiness_record "command" "$command_name" "$status" "$severity" ""
  done
}

generate_readiness_status() {
  readiness_reset
  readiness_generate_packages
  readiness_generate_sources
  readiness_generate_services
  readiness_generate_display_manager_conflicts
  readiness_generate_desktop_files
  readiness_generate_target_home
  readiness_generate_config_conflicts
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
