#!/usr/bin/env bash
set -Eeuo pipefail

module_32_optional_packages() {
  local dnf_base_plan flatpak_base_plan
  dnf_base_plan="$(mktemp "$CACHE_DIR/base-dnf.XXXXXX")"
  flatpak_base_plan="$(mktemp "$CACHE_DIR/base-flatpak.XXXXXX")"

  log_progress "Building base package exclusion list"
  build_base_package_plan_for_backend dnf "$dnf_base_plan"
  build_base_package_plan_for_backend flatpak "$flatpak_base_plan"

  log_progress "Installing optional Flatpaks"
  defer_extra_data_flatpaks "$PLAN_DIR/flatpak/apps.flatpaks"
  install_optional_packages_for_backend flatpak "$PLAN_DIR/flatpak/apps.flatpaks" "$flatpak_base_plan" "$(flatpak_deferred_plan_file)"
  log_progress "Installing optional native packages"
  install_optional_packages_for_backend dnf "$PLAN_DIR/packages/dnf.pkgs" "$dnf_base_plan"

  rm -f "$dnf_base_plan" "$flatpak_base_plan"
}
