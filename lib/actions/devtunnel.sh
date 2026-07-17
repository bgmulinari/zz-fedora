#!/usr/bin/env bash
set -Eeuo pipefail

# Microsoft devtunnel CLI custom action.

install_devtunnel() {
  local devtunnel_bin="$TARGET_HOME/.local/bin/devtunnel"
  [[ -x "$devtunnel_bin" ]] && return 0
  log_progress "Installing Microsoft devtunnel CLI"
  local downloaded_bin
  downloaded_bin="$(mktemp "$CACHE_DIR/devtunnel.XXXXXX")"
  run_cmd_as_user "$TARGET_USER" mkdir -p "$TARGET_HOME/.local/bin"
  if ! run_cmd curl -fsSL https://aka.ms/TunnelsCliDownload/linux-x64 -o "$downloaded_bin"; then
    rm -f "$downloaded_bin"
    return 1
  fi
  run_cmd chmod 0644 "$downloaded_bin"
  run_cmd_as_user "$TARGET_USER" install -m 0755 "$downloaded_bin" "$devtunnel_bin"
  rm -f "$downloaded_bin"
}

verify_devtunnel() {
  [[ -x "$TARGET_HOME/.local/bin/devtunnel" ]]
}

register_action "devtunnel" install_devtunnel verify_devtunnel
