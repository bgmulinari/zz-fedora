#!/usr/bin/env bash
set -Eeuo pipefail

module_05_bootstrap_tools() {
  log_progress "Installing native prerequisite packages"
  install_from_plan_file dnf "$PLAN_DIR/prereqs/dnf.pkgs" || return 1
  log_progress "Installing Flatpak prerequisite packages"
  install_from_plan_file flatpak "$PLAN_DIR/prereqs/flatpak.flatpaks" || return 1
  if [[ "${ZZ_INSTALLER_APPLY_RELEASE_UPDATES:-0}" -eq 1 ]]; then
    if declare -F fedora_apply_release_updates >/dev/null 2>&1; then
      fedora_apply_release_updates || return 1
    else
      die "Release updates were requested, but Fedora update support is unavailable."
    fi
  fi
}
