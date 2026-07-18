#!/usr/bin/env bash
set -Eeuo pipefail

# First-run hook and marker handling. The post-actions step registers the
# autostart hook; the first-run session command removes it and writes the
# completion marker.

first_run_marker() {
  printf '%s\n' "$STATE_DIR/first-run.done"
}

first_run_desktop_file() {
  printf '%s\n' "$TARGET_HOME/.config/autostart/zz-first-run.desktop"
}

register_first_run_hook() {
  local desktop_file launcher
  desktop_file="$(first_run_desktop_file)"
  launcher="$TARGET_HOME/.local/bin/zz"

  log_progress "Registering first-run hook"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: register first-run hook -> %s\n' "$desktop_file"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$desktop_file")"
  run_cmd_as_user "$TARGET_USER" sh -c '
    desktop_file="$1"
    launcher="$2"
    cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=ZZ First Run
Exec=$launcher first-run
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  ' sh "$desktop_file" "$launcher"
}

remove_first_run_hook() {
  local desktop_file
  desktop_file="$(first_run_desktop_file)"
  [[ -e "$desktop_file" || -L "$desktop_file" ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: remove first-run hook %s\n' "$desktop_file"
    return 0
  fi
  run_cmd_as_user "$TARGET_USER" rm -f "$desktop_file"
}
