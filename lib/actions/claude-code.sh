#!/usr/bin/env bash
set -Eeuo pipefail

# Claude Code CLI custom action.

install_claude_code() {
  local claude_bin="$TARGET_HOME/.local/bin/claude"
  [[ -x "$claude_bin" ]] && return 0
  log_progress "Installing Claude Code"
  local install_script
  install_script="$(mktemp "$CACHE_DIR/claude-install.XXXXXX")"
  if ! run_cmd curl -fsSL https://claude.ai/install.sh -o "$install_script"; then
    rm -f "$install_script"
    return 1
  fi
  run_cmd chmod 0755 "$install_script"
  run_cmd_as_user "$TARGET_USER" bash "$install_script"
  rm -f "$install_script"
}

verify_claude_code() {
  [[ -x "$TARGET_HOME/.local/bin/claude" ]]
}

register_action "claude-code" install_claude_code verify_claude_code
