#!/usr/bin/env bash
set -Eeuo pipefail

module_05_bootstrap_tools() {
  log_progress "Installing native prerequisite packages"
  install_from_plan_file dnf "$PLAN_DIR/prereqs/dnf.pkgs" || return 1
  log_progress "Installing Flatpak prerequisite packages"
  install_from_plan_file flatpak "$PLAN_DIR/prereqs/flatpak.flatpaks" || return 1
}
