#!/usr/bin/env bash
set -Eeuo pipefail

module_05_bootstrap_tools() {
  install_from_plan_file dnf "$PLAN_DIR/prereqs/dnf.pkgs"
  install_from_plan_file pacman "$PLAN_DIR/prereqs/pacman.pkgs"
  install_from_plan_file aur "$PLAN_DIR/prereqs/aur.pkgs"
  install_from_plan_file flatpak "$PLAN_DIR/prereqs/flatpak.flatpaks"
}
