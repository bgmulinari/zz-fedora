#!/usr/bin/env bash
set -Eeuo pipefail

install_from_plan_file() {
  local backend="$1"
  local plan_file="$2"
  local mode="${3:-required}"
  [[ -f "$plan_file" ]] || return 0
  mapfile -t packages < <(read_plan_file "$plan_file")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  printf '%s packages: %s\n' "$backend" "${#packages[@]}"
  if package_install_idempotent "$backend" "${packages[@]}"; then
    return 0
  fi

  [[ "$mode" == "optional" ]] || return 1

  log_warn "Optional $backend package transaction failed; retrying packages individually."
  local package_name
  for package_name in "${packages[@]}"; do
    if package_install_idempotent "$backend" "$package_name"; then
      continue
    fi
    log_warn "Optional $backend package failed and will be skipped for now: $package_name"
  done
  return 0
}

install_base_packages_for_backend() {
  local backend="$1"
  local base_var="BASE_BUNDLE_IDS_${DISTRO}"
  declare -p "$base_var" >/dev/null 2>&1 || return 0
  local -n base_bundle_ids_ref="$base_var"
  local base_plan
  base_plan="$(mktemp "$CACHE_DIR/base-${backend}.XXXXXX")"

  local bundle_id
  local -a bundle_items=()
  for bundle_id in "${base_bundle_ids_ref[@]:-}"; do
    load_bundle_descriptor "$DISTRO" "$bundle_id" || die "Unknown base bundle: $bundle_id"
    [[ "$BUNDLE_INSTALLER" == "$backend" ]] || continue
    mapfile -t bundle_items < <(manifest_entries "$ROOT_DIR/$BUNDLE_ITEMS_FILE")
    append_plan_entries "$base_plan" "${bundle_items[@]:-}"
  done

  install_from_plan_file "$backend" "$base_plan"
  rm -f "$base_plan"
}

module_30_packages() {
  install_base_packages_for_backend dnf
  install_base_packages_for_backend pacman
  install_base_packages_for_backend aur
  install_base_packages_for_backend flatpak

  install_from_plan_file dnf "$PLAN_DIR/packages/dnf.pkgs" optional
  install_from_plan_file pacman "$PLAN_DIR/packages/pacman.pkgs" optional
  install_from_plan_file aur "$PLAN_DIR/packages/aur.pkgs" optional
  install_from_plan_file flatpak "$PLAN_DIR/flatpak/apps.flatpaks" optional
}
