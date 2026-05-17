#!/usr/bin/env bash
set -Eeuo pipefail

acquire_lock() {
  ensure_state_dirs
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_ACQUIRED=1
    printf '%s\n' "$$" >"$LOCK_DIR/pid"
    trap cleanup_on_exit EXIT
    return 0
  fi
  die "Another zz-linux-setup process appears to be running. Remove $LOCK_DIR if that is stale."
}

cleanup_on_exit() {
  if declare -F tui_progress_end >/dev/null 2>&1; then
    tui_progress_end || true
  fi
  stop_sudo_keepalive
  restore_state_ownership
  release_lock
}

restore_state_ownership() {
  [[ "$EUID" -eq 0 ]] || return 0
  [[ -n "${STATE_OWNER_USER:-}" && "$STATE_OWNER_USER" != "root" ]] || return 0
  id "$STATE_OWNER_USER" >/dev/null 2>&1 || return 0

  local owner_group dir
  owner_group="$(id -gn "$STATE_OWNER_USER" 2>/dev/null)" || return 0
  for dir in "$STATE_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$LOG_DIR"; do
    [[ -d "$dir" && "$dir" == */zz-linux-setup ]] || continue
    chown -R "$STATE_OWNER_USER:$owner_group" "$dir" 2>/dev/null || true
  done
  if [[ -d "$LOG_DIR" && "$LOG_DIR" == "$ROOT_DIR/logs" ]]; then
    chown -R "$STATE_OWNER_USER:$owner_group" "$LOG_DIR" 2>/dev/null || true
  fi
}

release_lock() {
  if [[ "${LOCK_ACQUIRED:-0}" -eq 1 && -d "$LOCK_DIR" ]]; then
    rm -rf "$LOCK_DIR"
    LOCK_ACQUIRED=0
  fi
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    LAST_COMMAND_CONTEXT="$(redacted_shell_quote "$@")"
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  LAST_COMMAND_CONTEXT="$(redacted_shell_quote "$@")"
  if [[ "${COMMAND_PREVIEW:-0}" -eq 1 ]]; then
    printf 'Command: %s\n' "$LAST_COMMAND_CONTEXT" >&2
    if [[ "${ASSUME_YES:-0}" -ne 1 ]]; then
      if declare -F tui_confirm >/dev/null 2>&1; then
        tui_confirm "Run this command?" || die "Command preview aborted before: $LAST_COMMAND_CONTEXT"
      elif is_tty; then
        local reply=""
        read -r -p "Run this command? [y/N] " reply
        [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || die "Command preview aborted before: $LAST_COMMAND_CONTEXT"
      else
        die "Command preview requires a TTY unless --yes is used."
      fi
    fi
  fi
  log_command "$@"
  "$@"
}

run_cmd_as_root() {
  if [[ "$EUID" -eq 0 ]]; then
    run_cmd "$@"
  else
    run_cmd sudo "$@"
  fi
}

run_cmd_as_clean_root() {
  local -a clean_env=(
    env -i
    "HOME=/root"
    "PATH=/usr/sbin:/usr/bin:/sbin:/bin"
  )
  if [[ "$EUID" -eq 0 ]]; then
    run_cmd "${clean_env[@]}" "$@"
  else
    run_cmd sudo "${clean_env[@]}" "$@"
  fi
}

run_cmd_as_user() {
  local user="$1"
  shift
  if [[ "$user" == "$USER" && -z "${SUDO_USER:-}" ]]; then
    run_cmd "$@"
  else
    local uid user_home runtime_dir dbus_bus
    uid="$(id -u "$user")"
    user_home="$(resolve_target_home "$user" || true)"
    [[ -n "$user_home" ]] || user_home="$TARGET_HOME"
    runtime_dir="/run/user/$uid"
    if [[ -n "${XDG_RUNTIME_DIR:-}" && "$XDG_RUNTIME_DIR" == "$runtime_dir" ]]; then
      runtime_dir="$XDG_RUNTIME_DIR"
    fi
    dbus_bus="unix:path=$runtime_dir/bus"

    local -a user_env=(
      "HOME=$user_home"
      "USER=$user"
      "LOGNAME=$user"
      "XDG_RUNTIME_DIR=$runtime_dir"
    )
    if [[ "${DBUS_SESSION_BUS_ADDRESS:-}" == "$dbus_bus" ]]; then
      user_env+=("DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS")
    elif [[ -S "$runtime_dir/bus" ]]; then
      user_env+=("DBUS_SESSION_BUS_ADDRESS=$dbus_bus")
    fi
    [[ -n "${DISPLAY:-}" ]] && user_env+=("DISPLAY=$DISPLAY")
    [[ -n "${WAYLAND_DISPLAY:-}" ]] && user_env+=("WAYLAND_DISPLAY=$WAYLAND_DISPLAY")
    [[ -n "${XAUTHORITY:-}" ]] && user_env+=("XAUTHORITY=$XAUTHORITY")
    [[ -n "${XDG_CURRENT_DESKTOP:-}" ]] && user_env+=("XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP")
    [[ -n "${DESKTOP_SESSION:-}" ]] && user_env+=("DESKTOP_SESSION=$DESKTOP_SESSION")

    run_cmd sudo -u "$user" env "${user_env[@]}" "$@"
  fi
}

start_sudo_keepalive() {
  [[ "$EUID" -eq 0 ]] && return 0
  have_cmd sudo || return 0
  sudo -v
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill -0 "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1; then
    return 0
  fi
  (
    while true; do
      sleep 50
      sudo -n true >/dev/null 2>&1 || exit 0
    done
  ) &
  SUDO_KEEPALIVE_PID="$!"
}

stop_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill -0 "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
  fi
  SUDO_KEEPALIVE_PID=""
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

flatpak_remote_usable() {
  local name="$1"
  have_cmd flatpak || return 1
  flatpak_remote_present "$name" || return 1
  flatpak remote-ls "$name" >/dev/null 2>&1
}

flatpak_remote_present() {
  local name="$1"
  have_cmd flatpak || return 1
  flatpak remotes --columns=name 2>/dev/null | grep -Fx "$name" >/dev/null 2>&1
}

flatpak_remote_usable_with_wait() {
  flatpak_remote_usable_with_wait_attempts "$1" 5
}

flatpak_remote_usable_with_wait_attempts() {
  local name="$1"
  local max_attempts="$2"
  local wait_seconds="${FLATPAK_REMOTE_WAIT_SECONDS:-1}"
  local attempt
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if flatpak_remote_usable "$name"; then
      return 0
    fi
    [[ "$wait_seconds" == "0" ]] || sleep "$wait_seconds"
  done
  return 1
}

flatpak_remote_usable_after_gpg_import() {
  local name="$1"
  flatpak_remote_usable_with_wait_attempts "$name" 5
}

download_flathub_gpg_key() {
  local key_file
  key_file="$(mktemp)"
  if ! curl -fsSL "https://flathub.org/repo/flathub.gpg" -o "$key_file"; then
    rm -f "$key_file"
    return 1
  fi
  chmod 0644 "$key_file"
  printf '%s\n' "$key_file"
}

flatpak_remote_add_with_gpg_key() {
  local key_file="$1"
  local name="$2"
  local url="$3"
  if run_cmd_as_root flatpak remote-add --gpg-import="$key_file" "$name" "$url"; then
    flatpak_remote_usable_after_gpg_import "$name" && return 0
  fi
  log_warn "Direct Flathub GPG import failed in the current environment; retrying with a clean root environment."
  if run_cmd_as_clean_root flatpak remote-add --gpg-import="$key_file" "$name" "$url"; then
    flatpak_remote_usable_after_gpg_import "$name" && return 0
  fi
  if [[ "$name" == "flathub" ]]; then
    log_warn "Verified Flathub setup is unavailable in this environment; adding Flathub without GPG verification."
    run_cmd_as_root flatpak remote-delete --force "$name" || true
    run_cmd_as_root flatpak remote-add --no-gpg-verify "$name" "$url" || return 1
    return 0
  fi
  flatpak_remote_usable_after_gpg_import "$name"
}

flatpak_remote_modify_with_gpg_key() {
  local key_file="$1"
  local name="$2"
  if run_cmd_as_root flatpak remote-modify --gpg-verify --gpg-import="$key_file" "$name"; then
    flatpak_remote_usable_with_wait "$name" && return 0
  fi
  log_warn "Direct Flathub GPG reimport failed in the current environment; retrying with a clean root environment."
  if run_cmd_as_clean_root flatpak remote-modify --gpg-verify --gpg-import="$key_file" "$name"; then
    flatpak_remote_usable_with_wait "$name" && return 0
  fi
  if [[ "$name" == "flathub" ]]; then
    log_warn "Verified Flathub reimport is unavailable in this environment; disabling Flathub GPG verification."
    run_cmd_as_root flatpak remote-modify --no-gpg-verify "$name"
    return $?
  fi
  return 1
}

flatpak_remote_add_with_retry() {
  local name="$1"
  local url="$2"
  local -a add_args=(remote-add --if-not-exists "$name" "$url")
  local attempt
  for attempt in 1 2 3; do
    if run_cmd_as_root flatpak "${add_args[@]}"; then
      return 0
    fi
    [[ "$attempt" -lt 3 ]] || break
    log_warn "Flatpak remote add failed for '$name'; retrying."
    [[ "${FLATPAK_REMOTE_RETRY_SECONDS:-2}" == "0" ]] || sleep "${FLATPAK_REMOTE_RETRY_SECONDS:-2}"
  done

  if [[ "$name" == "flathub" ]]; then
    local key_file
    log_warn "Verified Flathub remote setup failed; importing Flathub GPG key directly and retrying."
    key_file="$(download_flathub_gpg_key)" || return 1
    run_cmd_as_root flatpak remote-delete --force "$name" || true
    if flatpak_remote_add_with_gpg_key "$key_file" "$name" "https://dl.flathub.org/repo/"; then
      rm -f "$key_file"
      return 0
    fi
    rm -f "$key_file"
    return 1
  fi

  return 1
}

flatpak_remote_add_if_missing() {
  local name="$1"
  local url="$2"

  if [[ "$name" == "flathub" ]] && have_cmd flatpak; then
    if flatpak remotes --columns=name 2>/dev/null | grep -Fx fedora >/dev/null 2>&1; then
      log_info "Removing Fedora Flatpak remote before configuring Flathub"
      run_cmd_as_root flatpak remote-delete --force fedora || true
    fi
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd_as_root flatpak remote-add --if-not-exists "$name" "$url"
    return 0
  fi
  if flatpak_remote_present "$name"; then
    if flatpak_remote_usable "$name"; then
      log_info "Flatpak remote already present: $name"
      return 0
    fi
    if flatpak_remote_usable_with_wait "$name"; then
      log_info "Flatpak remote already present: $name"
      return 0
    fi
    if [[ "$name" == "flathub" ]]; then
      local key_file
      log_warn "Flatpak remote '$name' is present but not queryable; checking whether Flathub GPG verification settles."
      if flatpak_remote_usable_with_wait_attempts "$name" 5; then
        log_info "Flatpak remote already present: $name"
        return 0
      fi
      log_warn "Flatpak remote '$name' is present but not queryable; re-adding it with the Flathub GPG key."
      key_file="$(download_flathub_gpg_key)" || return 1
      run_cmd_as_root flatpak remote-delete --force "$name" || true
      if flatpak_remote_add_with_gpg_key "$key_file" "$name" "https://dl.flathub.org/repo/"; then
        rm -f "$key_file"
        return 0
      fi
      rm -f "$key_file"
      return 1
    fi
    log_warn "Flatpak remote '$name' is present but unusable; re-adding it."
    run_cmd_as_root flatpak remote-delete --force "$name"
  fi
  flatpak_remote_add_with_retry "$name" "$url" || flatpak_remote_usable_with_wait "$name" || {
    [[ "$name" == "flathub" ]] && flatpak_remote_present "$name"
  }
  flatpak_remote_usable_with_wait "$name" || {
    [[ "$name" == "flathub" ]] && flatpak_remote_present "$name"
  }
}

flatpak_reimport_remote_gpg_key() {
  local name="$1"
  local key_file
  [[ "$name" == "flathub" ]] || return 1
  log_warn "Flatpak install from '$name' failed GPG verification; importing Flathub GPG key directly and retrying."
  key_file="$(download_flathub_gpg_key)" || return 1
  if flatpak_remote_modify_with_gpg_key "$key_file" "$name"; then
    rm -f "$key_file"
    return 0
  fi
  log_warn "Flathub GPG key reimport failed; re-adding the remote with the Flathub GPG key."
  run_cmd_as_root flatpak remote-delete --force "$name" || true
  if flatpak_remote_add_with_gpg_key "$key_file" "$name" "https://dl.flathub.org/repo/"; then
    rm -f "$key_file"
    return 0
  fi
  rm -f "$key_file"
  return 1
}

flatpak_install_or_update() {
  local app_id="$1"
  local remote="${2:-flathub}"
  local detail_log=""
  if [[ "$DRY_RUN" -eq 0 && -n "${LOG_DIR:-}" ]]; then
    detail_log="$LOG_DIR/flatpak-${app_id//[^A-Za-z0-9_.-]/_}-$(timestamp).log"
    if ! run_cmd_as_root flatpak install -y --or-update "$remote" "$app_id" >"$detail_log" 2>&1; then
      if [[ "$remote" == "flathub" ]] && grep -F "GPG: Unable to complete signature verification" "$detail_log" >/dev/null 2>&1; then
        cat "$detail_log" >&2
        flatpak_reimport_remote_gpg_key "$remote" || return 1
        detail_log="$LOG_DIR/flatpak-${app_id//[^A-Za-z0-9_.-]/_}-retry-$(timestamp).log"
        if run_cmd_as_root flatpak install -y --or-update "$remote" "$app_id" >"$detail_log" 2>&1; then
          log_info "Flatpak install details for $app_id: $detail_log"
          return 0
        fi
      fi
      cat "$detail_log" >&2
      return 1
    fi
    log_info "Flatpak install details for $app_id: $detail_log"
    return 0
  fi
  run_cmd_as_root flatpak install -y --or-update "$remote" "$app_id"
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
    flatpak) distro_install_flatpaks "${packages[@]}" ;;
    *) die "Unsupported package backend: $backend" ;;
  esac
}
