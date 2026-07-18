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
  local desktop_file launcher temp_file
  desktop_file="$(first_run_desktop_file)"
  launcher="$TARGET_HOME/.local/bin/zz"

  log_progress "Registering first-run hook"
  temp_file="$(mktemp "$CACHE_DIR/first-run-hook.XXXXXX")"
  cat >"$temp_file" <<EOF
[Desktop Entry]
Type=Application
Name=ZZ First Run
Exec=$launcher first-run
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  chmod 0644 "$temp_file"
  install_file_if_changed user "$temp_file" "$desktop_file"
  rm -f "$temp_file"
}

remove_first_run_hook() {
  local desktop_file
  desktop_file="$(first_run_desktop_file)"
  [[ -e "$desktop_file" || -L "$desktop_file" ]] || return 0
  run_cmd_as_user "$TARGET_USER" rm -f "$desktop_file"
}
