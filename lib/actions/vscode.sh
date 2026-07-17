#!/usr/bin/env bash
set -Eeuo pipefail

# vscode-extension:<extension-id> custom actions.

vscode_extension_installed() {
  local extension="$1"
  local installed_extensions
  installed_extensions="$(run_cmd_as_user "$TARGET_USER" code --list-extensions 2>/dev/null)" || return 1
  grep -Fxi -- "$extension" <<<"$installed_extensions" >/dev/null 2>&1
}

install_vscode_extension() {
  local extension="$1"
  [[ -n "$extension" ]] || die "Visual Studio Code extension ID cannot be empty."

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Visual Studio Code extension for %s: %s\n' "$TARGET_USER" "$extension"
    return 0
  fi

  if vscode_extension_installed "$extension"; then
    log_info "Visual Studio Code extension is already installed: $extension"
    return 0
  fi

  log_progress "Installing Visual Studio Code extension: $extension"
  run_cmd_as_user "$TARGET_USER" code --install-extension "$extension"
}

register_action "vscode-extension" install_vscode_extension vscode_extension_installed
