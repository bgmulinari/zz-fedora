#!/usr/bin/env bash
set -Eeuo pipefail

# First-run hook and marker handling. The post-actions step registers the
# autostart hook. Each session action records its own durable completion
# marker so a later failure retries only unfinished work; the aggregate marker
# removes the hook once every action has converged.

first_run_marker() {
  printf '%s\n' "$STATE_DIR/first-run.done"
}

first_run_action_state_dir() {
  printf '%s\n' "$STATE_DIR/first-run-actions"
}

first_run_action_marker() {
  local action_id="$1"
  [[ "$action_id" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] ||
    die "Invalid first-run action ID: $action_id"
  printf '%s/%s.done\n' "$(first_run_action_state_dir)" "$action_id"
}

first_run_action_completed() {
  local action_id="$1"
  local input_fingerprint="${2:-}"
  local marker
  marker="$(first_run_action_marker "$action_id")"
  [[ -f "$marker" ]] || return 1
  [[ -z "$input_fingerprint" ]] ||
    grep -Fxq "input_fingerprint=$input_fingerprint" "$marker"
}

mark_first_run_action_complete() {
  local action_id="$1"
  local input_fingerprint="${2:-}"
  local marker
  marker="$(first_run_action_marker "$action_id")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: mark first-run action complete: %s -> %s\n' "$action_id" "$marker"
    return 0
  fi
  mkdir -p "$(dirname "$marker")"
  {
    printf 'completed_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    [[ -z "$input_fingerprint" ]] || printf 'input_fingerprint=%s\n' "$input_fingerprint"
  } >"$marker"
}

run_first_run_action_once() {
  local action_id="$1"
  shift
  if first_run_action_completed "$action_id" && [[ "${ZZ_FIRST_RUN_FORCE:-0}" -ne 1 ]]; then
    log_info "First-run action already completed: $action_id"
    return 0
  fi
  # This helper is called from an OR-list so the module can continue with
  # independent actions after a failure. Bash consequently disables errexit
  # inside the action call; action entrypoints must return an explicit
  # aggregate status instead of relying on `set -e`.
  "$@" || return $?
  mark_first_run_action_complete "$action_id"
}

run_first_run_action_once_for_input() {
  local action_id="$1"
  local input_fingerprint="$2"
  shift 2
  if first_run_action_completed "$action_id" "$input_fingerprint" &&
    [[ "${ZZ_FIRST_RUN_FORCE:-0}" -ne 1 ]]; then
    log_info "First-run action already completed for current inputs: $action_id"
    return 0
  fi
  "$@" || return $?
  mark_first_run_action_complete "$action_id" "$input_fingerprint"
}

first_run_fingerprint() {
  sha256sum | awk '{ print $1 }'
}

first_run_files_fingerprint() {
  local file
  {
    for file in "$@"; do
      printf 'file=%s\n' "$file"
      if [[ -f "$file" ]]; then
        sha256sum "$file"
      else
        printf 'missing\n'
      fi
    done
  } | first_run_fingerprint
}

first_run_desktop_file() {
  printf '%s\n' "$TARGET_HOME/.config/autostart/zz-first-run.desktop"
}

register_first_run_hook() {
  local desktop_file launcher
  desktop_file="$(first_run_desktop_file)"
  launcher="$TARGET_HOME/.local/bin/zz"

  log_progress "Registering first-run hook"
  write_user_file 0644 "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=ZZ First Run
Exec=$launcher first-run --use-saved
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
}

remove_first_run_hook() {
  local desktop_file
  desktop_file="$(first_run_desktop_file)"
  [[ -e "$desktop_file" || -L "$desktop_file" ]] || return 0
  run_cmd_as_user "$TARGET_USER" rm -f "$desktop_file"
}
