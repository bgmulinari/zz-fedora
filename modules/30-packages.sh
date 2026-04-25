#!/usr/bin/env bash
set -Eeuo pipefail

install_from_plan_file() {
  local backend="$1"
  local plan_file="$2"
  [[ -f "$plan_file" ]] || return 0
  mapfile -t packages < <(read_plan_file "$plan_file")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  printf '%s packages: %s\n' "$backend" "${#packages[@]}"
  package_install_idempotent "$backend" "${packages[@]}"
}

module_30_packages() {
  install_from_plan_file dnf "$PLAN_DIR/packages/dnf.pkgs"
  install_from_plan_file pacman "$PLAN_DIR/packages/pacman.pkgs"
  install_from_plan_file aur "$PLAN_DIR/packages/aur.pkgs"
  install_from_plan_file flatpak "$PLAN_DIR/flatpak/apps.flatpaks"
}
