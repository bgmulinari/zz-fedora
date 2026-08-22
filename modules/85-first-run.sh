#!/usr/bin/env bash
set -Eeuo pipefail

# A theme artifact counts as generated only once it holds content that is
# not the static fallback seed: the Ghostty theme is pre-seeded with the
# same path DMS later overwrites, so bare existence proves nothing there.
dms_theme_artifact_generated() {
  local artifact="$1"
  local seed="$2"
  [[ -s "$artifact" ]] || return 1
  [[ -z "$seed" ]] && return 0
  ! cmp -s "$seed" "$artifact"
}

DMS_THEME_MAX_ATTEMPTS=3

# DMS regenerates every enabled matugen template when the shell starts or
# the theme changes; there is no explicit apply request. Wait for the shell
# socket to answer, then for the generated theme artifacts this install
# actually consumes, so first login completes with the terminal and Qt
# themes in place. The wait retries at the next login on timeout, but only
# a bounded number of times: a persistently absent artifact degrades to a
# warning instead of taxing every login, and the doctor checks surface it.
apply_dms_theme() {
  local attempt failed_attempts native_plan
  local -a artifacts=() artifact_seeds=()

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: await DMS shell readiness and generated theme artifacts\n'
    return 0
  fi

  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" dms || return 0

  failed_attempts="$(first_run_action_attempt_count dms-theme)"
  if [[ "$failed_attempts" -ge "$DMS_THEME_MAX_ATTEMPTS" ]]; then
    log_warn "DMS theme generation did not complete after $failed_attempts logins; continuing without waiting (run 'zz doctor' to investigate)"
    return 0
  fi

  log_progress "Waiting for the DMS shell"
  for ((attempt = 1; attempt <= 120; attempt++)); do
    run_cmd_as_user "$TARGET_USER" dms ipc call wallpaper get >/dev/null 2>&1 && break
    sleep 0.25
  done
  if [[ "$attempt" -gt 120 ]]; then
    log_warn "The DMS shell did not answer IPC; retrying at next login"
    first_run_record_action_attempt dms-theme
    return 1
  fi

  if plan_has_any_backend_entry "$native_plan" ghostty; then
    artifacts+=("$(dms_ghostty_theme_file)")
    artifact_seeds+=("$ROOT_DIR/templates/ghostty/dankcolors")
  fi
  if plan_has_any_backend_entry "$native_plan" qt6ct qt6ct-kde; then
    artifacts+=("$(dms_qt_color_scheme_file)")
    artifact_seeds+=("")
  fi
  if [[ "${#artifacts[@]}" -eq 0 ]]; then
    first_run_clear_action_attempts dms-theme
    return 0
  fi

  log_progress "Waiting for DMS theme generation"
  local index all_generated
  for ((attempt = 1; attempt <= 120; attempt++)); do
    all_generated=1
    for index in "${!artifacts[@]}"; do
      dms_theme_artifact_generated "${artifacts[$index]}" "${artifact_seeds[$index]}" || {
        all_generated=0
        break
      }
    done
    if [[ "$all_generated" -eq 1 ]]; then
      first_run_clear_action_attempts dms-theme
      return 0
    fi
    sleep 0.25
  done

  log_warn "DMS did not finish generating theme files; retrying at next login"
  first_run_record_action_attempt dms-theme
  return 1
}

# Populate this user's greeter cache slot (wallpaper snapshot, theme,
# avatar) once the shell state exists. The slot sync is sudo-free; the
# root-side cache and access grants were prepared by the dms-greeter
# action.
apply_dms_greeter_profile_sync() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: sync the DMS Greeter per-user profile slot\n'
    return 0
  fi

  if ! plan_file_has_entry "$(package_file_for_backend action)" "dms-greeter" ||
    dms_greeter_action_skipped || dms_greeter_user_sync_skipped; then
    return 0
  fi

  log_progress "Syncing the DMS Greeter user profile"
  if ! run_cmd_as_user "$TARGET_USER" dms-greeter sync --profile >/dev/null 2>&1; then
    log_warn "The DMS Greeter profile sync failed; retrying at next login"
    return 1
  fi
}

first_run_enable_session_services() {
  local failed=0
  run_cmd_as_user "$TARGET_USER" systemctl --user daemon-reload || failed=1
  enable_user_services strict || failed=1
  return "$failed"
}

first_run_update_user_directories() {
  run_cmd_as_user "$TARGET_USER" xdg-user-dirs-update || true
}

first_run_apply_desktop_interface() {
  local cursor_theme
  cursor_theme="$(desktop_cursor_theme_name)"

  if [[ "$(resolved_desktop_app_profile)" == "full" ]]; then
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark || true
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme" || true
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface cursor-size "$DESKTOP_CURSOR_THEME_SIZE" || true
  fi
}

first_run_session_services_fingerprint() {
  first_run_files_fingerprint \
    "$PLAN_DIR/services/user-enable.list" \
    "$PLAN_DIR/services/user-wants.tsv"
}

first_run_desktop_interface_fingerprint() {
  {
    printf 'desktop_app_profile=%s\n' "$(resolved_desktop_app_profile)"
    printf 'cursor_theme=%s\n' "$(desktop_cursor_theme_name)"
    printf 'cursor_size=%s\n' "$DESKTOP_CURSOR_THEME_SIZE"
  } | first_run_fingerprint
}

first_run_desktop_defaults_fingerprint() {
  {
    printf 'desktop_app_profile=%s\n' "$(resolved_desktop_app_profile)"
    printf 'preferred_browser=%s\n' "$PREFERRED_BROWSER"
    printf 'update_mode=%s\n' "$UPDATE_MODE"
    printf 'browser_choices\n'
    effective_choice_ids "browsers"
    first_run_files_fingerprint \
      "$ROOT_DIR/config/default-applications.tsv" \
      "$PLAN_DIR/bundles.list" \
      "$(package_file_for_backend "$(native_backend)")" \
      "$(package_file_for_backend flatpak)"
  } | first_run_fingerprint
}

mark_first_run_complete() {
  local marker
  marker="$(first_run_marker)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: mark first-run complete -> %s\n' "$marker"
    return 0
  fi
  mkdir -p "$(dirname "$marker")"
  printf 'completed_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >"$marker"
}

module_85_first_run() {
  local marker failed=0
  local session_services_fingerprint desktop_interface_fingerprint desktop_defaults_fingerprint
  marker="$(first_run_marker)"

  session_services_fingerprint="$(first_run_session_services_fingerprint)"
  desktop_interface_fingerprint="$(first_run_desktop_interface_fingerprint)"
  desktop_defaults_fingerprint="$(first_run_desktop_defaults_fingerprint)"
  if [[ -f "$marker" && "${ZZ_FIRST_RUN_FORCE:-0}" -ne 1 ]] &&
    first_run_action_completed session-services "$session_services_fingerprint" &&
    first_run_action_completed user-directories &&
    first_run_action_completed desktop-interface "$desktop_interface_fingerprint" &&
    first_run_action_completed desktop-defaults "$desktop_defaults_fingerprint" &&
    first_run_action_completed dms-theme &&
    first_run_action_completed dms-greeter-profile; then
    log_info "First-run tasks already completed: $marker"
    # A deferred Flatpak queue can appear after first-run already completed
    # (an install re-run in a sandbox-restricted environment re-registers
    # the hook); consume it and clear the hook instead of stranding both.
    install_deferred_flatpaks || return 1
    remove_first_run_hook
    return 0
  fi

  # These actions are independent checkpoints. A failure keeps the aggregate
  # first-run hook active, but successful actions are never repeated merely
  # because another action (including deferred Flatpaks) still needs a retry.
  run_first_run_action_once_for_input \
    session-services "$session_services_fingerprint" first_run_enable_session_services || failed=1
  run_first_run_action_once user-directories first_run_update_user_directories || failed=1
  run_first_run_action_once_for_input \
    desktop-interface "$desktop_interface_fingerprint" first_run_apply_desktop_interface || failed=1
  run_first_run_action_once_for_input \
    desktop-defaults "$desktop_defaults_fingerprint" apply_desktop_defaults || failed=1
  run_first_run_action_once dms-theme apply_dms_theme || failed=1
  run_first_run_action_once dms-greeter-profile apply_dms_greeter_profile_sync || failed=1

  # The deferred list and its per-app removal are already the Flatpak action's
  # durable checkpoint, including support for a new queue after first-run.
  install_deferred_flatpaks || failed=1

  [[ "$failed" -eq 0 ]] || return 1
  mark_first_run_complete
  remove_first_run_hook
}
