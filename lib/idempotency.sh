#!/usr/bin/env bash
set -Eeuo pipefail

acquire_lock() {
  ensure_state_dirs
  have_cmd flock || die "flock is required for installer locking"
  exec {LOCK_FD}>"$LOCK_FILE"
  if ! flock -n "$LOCK_FD"; then
    eval "exec ${LOCK_FD}>&-"
    LOCK_FD=""
    die "Another zz-fedora process is running (lock: $LOCK_FILE)."
  fi
  LOCK_ACQUIRED=1
  printf '%s\n' "$$" 1>&"$LOCK_FD"
  trap cleanup_on_exit EXIT
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
  state_owner_fixup_required || return 0

  local owner_group dir
  owner_group="$(state_owner_group)" || return 0
  for dir in "$STATE_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$LOG_DIR"; do
    [[ -d "$dir" && "$dir" == */zz-fedora ]] || continue
    chown -R "$STATE_OWNER_USER:$owner_group" "$dir" 2>/dev/null || true
  done
  if [[ -d "$LOG_DIR" && "$LOG_DIR" == "$ROOT_DIR/logs" ]]; then
    chown -R "$STATE_OWNER_USER:$owner_group" "$LOG_DIR" 2>/dev/null || true
  fi
}

release_lock() {
  [[ "${LOCK_ACQUIRED:-0}" -eq 1 ]] || return 0
  if [[ -n "${LOCK_FD:-}" ]]; then
    flock -u "$LOCK_FD" 2>/dev/null || true
    eval "exec ${LOCK_FD}>&-"
  fi
  LOCK_FD=""
  LOCK_ACQUIRED=0
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
  local command_timeout_seconds="${ZZ_COMMAND_TIMEOUT_SECONDS:-0}"
  if [[ "$command_timeout_seconds" =~ ^[0-9]+$ && "$command_timeout_seconds" -gt 0 ]]; then
    if have_cmd timeout; then
      local command_status
      set +e
      timeout --foreground --kill-after="${ZZ_COMMAND_TIMEOUT_KILL_AFTER:-30s}" "$command_timeout_seconds" "$@"
      command_status=$?
      set -e
      if [[ "$command_status" -eq 124 || "$command_status" -eq 137 ]]; then
        log_error "Command timed out after ${command_timeout_seconds}s: $LAST_COMMAND_CONTEXT"
      fi
      return "$command_status"
    fi
    log_warn "Command timeout requested but coreutils timeout is unavailable."
  fi
  "$@"
}

run_cmd_as_root() {
  if [[ "$EUID" -eq 0 ]]; then
    run_cmd "$@"
  else
    run_cmd sudo "$@"
  fi
}

run_cmd_as_user() {
  local user="$1"
  shift
  local current_user
  current_user="${USER:-}"
  [[ -n "$current_user" ]] || current_user="$(id -un)"
  if [[ "$user" == "$current_user" && -z "${SUDO_USER:-}" ]]; then
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
    local locale_lang="${LANG:-C.UTF-8}"
    local locale_all="${LC_ALL:-$locale_lang}"
    case "$locale_lang" in
      *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
      *) locale_lang=C.UTF-8 ;;
    esac
    case "$locale_all" in
      *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
      *) locale_all="$locale_lang" ;;
    esac
    user_env+=("LANG=$locale_lang" "LC_ALL=$locale_all")
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

# All pre-replace backups share one layout: the original absolute path
# mirrored under $STATE_DIR/backups/<timestamp>. timestamp() has second
# granularity, so when the same destination is backed up more than once in
# one second an incrementing suffix keeps every copy instead of letting the
# later backup overwrite the true original.
backup_target_path() {
  local destination="$1"
  local backup_path candidate suffix
  backup_path="$(printf '%s/backups/%s%s' "$STATE_DIR" "$(timestamp)" "$destination")"
  candidate="$backup_path"
  suffix=1
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$backup_path.$suffix"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

backup_file_if_needed() {
  local destination="$1"
  [[ -e "$destination" || -L "$destination" ]] || return 0
  local backup_path backup_dir
  backup_path="$(backup_target_path "$destination")"
  backup_dir="$(dirname "$backup_path")"
  # A failed backup must fail the running step immediately with the real
  # cause: step functions run with errexit suppressed, so a plain failure
  # status would be swallowed and the caller would replace $destination
  # without any backup.
  run_cmd mkdir -p "$backup_dir" ||
    die "Could not create backup directory $backup_dir before replacing $destination"
  run_cmd cp -a "$destination" "$backup_path" ||
    die "Could not back up $destination to $backup_path before replacing it"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  chown_state_path_to_owner "$backup_path"
  log_info "Backed up $destination to $backup_path"
}

backup_user_file_if_needed() {
  local destination="$1"
  [[ -e "$destination" || -L "$destination" ]] || return 0
  local backup_path backup_dir
  backup_path="$(backup_target_path "$destination")"
  backup_dir="$(dirname "$backup_path")"
  # A failed backup must fail the running step immediately with the real
  # cause: step functions run with errexit suppressed, so a plain failure
  # status would be swallowed and the caller would replace $destination
  # without any backup. In a continue-policy step the installer carries on
  # after the step is marked failed, so anything this step must guarantee
  # has to run before its first failable seed.
  run_cmd_as_user "$TARGET_USER" mkdir -p "$backup_dir" ||
    die "Could not create backup directory $backup_dir before replacing $destination"
  run_cmd_as_user "$TARGET_USER" cp -a "$destination" "$backup_path" ||
    die "Could not back up $destination to $backup_path before replacing it"
  [[ "$DRY_RUN" -eq 1 ]] || log_info "Backed up $destination to $backup_path"
}

# Single file-install primitive shared by root- and user-context callers:
# skip when unchanged, back up an existing destination, then install with
# the requested mode. Context selects the execution identity.
install_file_if_changed() {
  local context="$1"
  local source_file="$2"
  local destination="$3"
  local mode="${4:-0644}"
  [[ -f "$source_file" ]] || die "Managed source file not found: $source_file"
  if [[ -f "$destination" ]] && cmp -s "$source_file" "$destination"; then
    log_info "Unchanged file: $destination"
    return 0
  fi
  case "$context" in
    root)
      backup_file_if_needed "$destination"
      run_cmd_as_root install -D -m "$mode" "$source_file" "$destination"
      ;;
    user)
      backup_user_file_if_needed "$destination"
      run_cmd_as_user "$TARGET_USER" install -D -m "$mode" "$source_file" "$destination"
      ;;
    *)
      die "Unsupported install context: $context"
      ;;
  esac
}

# Write stdin to a root-owned destination: stage in CACHE_DIR, then install
# through install_file_if_changed so cmp/backup/dry-run behavior is shared.
write_root_file() {
  local mode="$1"
  local destination="$2"
  local temp_file
  temp_file="$(mktemp "$CACHE_DIR/root-file.XXXXXX")"
  cat >"$temp_file"
  chmod 0644 "$temp_file"
  if ! install_file_if_changed root "$temp_file" "$destination" "$mode"; then
    rm -f "$temp_file"
    return 1
  fi
  rm -f "$temp_file"
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

flatpak_remote_add_with_flathub_key() {
  local name="$1"
  local key_file
  [[ "$name" == "flathub" ]] || return 1
  log_warn "Official Flathub remote setup did not settle; importing the Flathub GPG key directly."
  key_file="$(download_flathub_gpg_key)" || return 1
  run_cmd_as_root flatpak remote-delete --force "$name" || true
  if run_cmd_as_root flatpak remote-add --gpg-import="$key_file" "$name" "https://dl.flathub.org/repo/" &&
    flatpak_remote_usable_with_wait "$name"; then
    rm -f "$key_file"
    return 0
  fi
  rm -f "$key_file"
  return 1
}

flatpak_remote_import_flathub_key() {
  local name="$1"
  local key_file
  [[ "$name" == "flathub" ]] || return 1
  log_warn "Flatpak remote '$name' is present but unusable; importing the Flathub GPG key directly."
  key_file="$(download_flathub_gpg_key)" || return 1
  if run_cmd_as_root flatpak remote-modify --gpg-verify --gpg-import="$key_file" "$name" &&
    flatpak_remote_usable_with_wait "$name"; then
    rm -f "$key_file"
    return 0
  fi
  rm -f "$key_file"
  flatpak_remote_add_with_flathub_key "$name"
}

flatpak_remote_add_with_retry() {
  local name="$1"
  local url="$2"
  local -a add_args=(remote-add --if-not-exists "$name" "$url")
  local max_attempts="${FLATPAK_REMOTE_RETRY_ATTEMPTS:-3}"
  local wait_seconds="${FLATPAK_REMOTE_RETRY_SECONDS:-2}"
  local attempt
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if run_cmd_as_root flatpak "${add_args[@]}"; then
      if flatpak_remote_usable_with_wait "$name"; then
        return 0
      fi
      log_warn "Flatpak remote '$name' was added but is not queryable yet."
    fi
    [[ "$attempt" -lt "$max_attempts" ]] || break
    log_warn "Flatpak remote add failed for '$name'; retrying."
    [[ "$wait_seconds" == "0" ]] || sleep "$wait_seconds"
  done
  if [[ "$name" == "flathub" ]] && flatpak_remote_add_with_flathub_key "$name"; then
    return 0
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
    if [[ "$name" == "flathub" ]] && flatpak_remote_import_flathub_key "$name"; then
      return 0
    fi
    log_warn "Flatpak remote '$name' is present but unusable; re-adding it."
    run_cmd_as_root flatpak remote-delete --force "$name"
  fi
  flatpak_remote_add_with_retry "$name" "$url"
}

flatpak_readd_remote_from_repo_file() {
  local name="$1"
  local _url="$2"
  [[ "$name" == "flathub" ]] || return 1
  log_warn "Flatpak install from '$name' failed GPG verification; importing the Flathub GPG key directly."
  flatpak_remote_import_flathub_key "$name"
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
        flatpak_readd_remote_from_repo_file "$remote" "https://dl.flathub.org/repo/flathub.flatpakrepo" || return 1
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

package_install_idempotent() {
  local backend="$1"
  shift
  local -a packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  case "$backend" in
    dnf) fedora_install_dnf_packages "${packages[@]}" ;;
    flatpak) fedora_install_flatpaks "${packages[@]}" ;;
    *) die "Unsupported package backend: $backend" ;;
  esac
}
