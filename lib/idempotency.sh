#!/usr/bin/env bash
set -Eeuo pipefail

acquire_lock() {
  ensure_state_dirs
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_ACQUIRED=1
    printf '%s\n' "$$" >"$LOCK_DIR/pid"
    trap release_lock EXIT
    return 0
  fi
  die "Another zz-linux-setup process appears to be running. Remove $LOCK_DIR if that is stale."
}

release_lock() {
  if [[ "${LOCK_ACQUIRED:-0}" -eq 1 && -d "$LOCK_DIR" ]]; then
    rm -rf "$LOCK_DIR"
    LOCK_ACQUIRED=0
  fi
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

run_cmd_as_user() {
  local user="$1"
  shift
  if [[ "$user" == "$USER" && -z "${SUDO_USER:-}" ]]; then
    run_cmd "$@"
  else
    run_cmd sudo -u "$user" "$@"
  fi
}

backup_file_if_needed() {
  local destination="$1"
  [[ -e "$destination" || -L "$destination" ]] || return 0
  local backup_root="$STATE_DIR/backups/$(timestamp)"
  local backup_path="$backup_root${destination}"
  mkdir -p "$(dirname "$backup_path")"
  cp -a "$destination" "$backup_path"
  log_info "Backed up $destination to $backup_path"
}

file_install_if_changed() {
  local source_file="$1"
  local destination="$2"
  local mode="${3:-0644}"
  [[ -f "$source_file" ]] || die "Managed source file not found: $source_file"
  if [[ -f "$destination" ]] && cmp -s "$source_file" "$destination"; then
    log_info "Unchanged file: $destination"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install %s -> %s (mode %s)\n' "$source_file" "$destination" "$mode"
    return 0
  fi
  local temp_file
  mkdir -p "$(dirname "$destination")"
  temp_file="$(mktemp "$(dirname "$destination")/.zz-linux-setup.XXXXXX")"
  cp "$source_file" "$temp_file"
  chmod "$mode" "$temp_file"
  if [[ -e "$destination" || -L "$destination" ]]; then
    backup_file_if_needed "$destination"
  fi
  mv -f "$temp_file" "$destination"
}

file_template_if_changed() {
  local template_file="$1"
  local destination="$2"
  local mode="${3:-0644}"
  file_install_if_changed "$template_file" "$destination" "$mode"
}

service_enable_if_exists() {
  local service_name="$1"
  if distro_service_exists "$service_name"; then
    distro_enable_service "$service_name"
  else
    log_warn "Skipping missing service: $service_name"
  fi
}

systemctl_enable_now_if_exists() {
  local service_name="$1"
  if distro_service_exists "$service_name"; then
    distro_enable_service_now "$service_name"
  else
    log_warn "Skipping missing service: $service_name"
  fi
}

flatpak_remote_add_if_missing() {
  local name="$1"
  local url="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd flatpak remote-add --if-not-exists "$name" "$url"
    return 0
  fi
  if have_cmd flatpak && flatpak remotes --columns=name 2>/dev/null | grep -Fx "$name" >/dev/null 2>&1; then
    log_info "Flatpak remote already present: $name"
    return 0
  fi
  run_cmd flatpak remote-add --if-not-exists "$name" "$url"
}

flatpak_install_or_update() {
  local app_id="$1"
  local remote="${2:-flathub}"
  run_cmd flatpak install -y --or-update "$remote" "$app_id"
}

repo_enable_if_missing() {
  local repo_id="$1"
  shift
  if distro_repo_enabled "$repo_id"; then
    log_info "Source already enabled: $repo_id"
    return 0
  fi
  run_cmd "$@"
}

package_install_idempotent() {
  local backend="$1"
  shift
  local -a packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  case "$backend" in
    dnf) distro_install_dnf_packages "${packages[@]}" ;;
    pacman) distro_install_pacman_packages "${packages[@]}" ;;
    aur) distro_install_aur_packages "${packages[@]}" ;;
    flatpak) distro_install_flatpaks "${packages[@]}" ;;
    *) die "Unsupported package backend: $backend" ;;
  esac
}
