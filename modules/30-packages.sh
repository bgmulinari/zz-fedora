#!/usr/bin/env bash
set -Eeuo pipefail

install_from_plan_file() {
  local backend="$1"
  local plan_file="$2"
  local mode="${3:-required}"
  local label="${4:-packages}"
  [[ -f "$plan_file" ]] || return 0
  mapfile -t packages < <(read_plan_file "$plan_file")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  printf '%s %s: %s\n' "$backend" "$label" "${#packages[@]}"
  if package_install_idempotent "$backend" "${packages[@]}"; then
    return 0
  fi

  if [[ "$mode" != "optional" ]]; then
    log_error "Required $backend $label transaction failed. Check the package manager output above."
    return 1
  fi

  log_warn "Optional $backend package transaction failed; retrying packages individually."
  local package_name
  local failed=0
  for package_name in "${packages[@]}"; do
    if package_install_idempotent "$backend" "$package_name"; then
      continue
    fi
    log_warn "Optional $backend package failed and will be skipped for now: $package_name"
    failed=1
  done
  return "$failed"
}

build_base_package_plan_for_backend() {
  local backend="$1"
  local base_plan="$2"
  local filter="${3:-all}"
  local base_var="BASE_BUNDLE_IDS_${DISTRO}"
  declare -p "$base_var" >/dev/null 2>&1 || return 0
  local -n base_bundle_ids_ref="$base_var"

  local bundle_id
  local -a bundle_items=()
  for bundle_id in "${base_bundle_ids_ref[@]:-}"; do
    case "$filter" in
      all)
        ;;
      early)
        is_early_base_bundle "$bundle_id" || continue
        ;;
      remaining)
        is_early_base_bundle "$bundle_id" && continue
        ;;
      *)
        die "Unsupported base bundle filter: $filter"
        ;;
    esac
    load_bundle_descriptor "$DISTRO" "$bundle_id" || die "Unknown base bundle: $bundle_id"
    [[ "$BUNDLE_INSTALLER" == "$backend" ]] || continue
    mapfile -t bundle_items < <(manifest_entries "$ROOT_DIR/$BUNDLE_ITEMS_FILE")
    append_plan_entries "$base_plan" "${bundle_items[@]:-}"
  done
}

is_early_base_bundle() {
  case "$1" in
    base-bootstrap|base-login-manager|base-system-services) return 0 ;;
    *) return 1 ;;
  esac
}

install_base_packages_for_backend() {
  local backend="$1"
  local base_plan="$2"
  install_from_plan_file "$backend" "$base_plan" required "base packages"
}

install_optional_packages_for_backend() {
  local backend="$1"
  local plan_file="$2"
  local base_plan="$3"
  [[ -f "$plan_file" ]] || return 0

  local optional_plan package_name
  optional_plan="$(mktemp "$CACHE_DIR/optional-${backend}.XXXXXX")"
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    if [[ -f "$base_plan" ]] && grep -Fx "$package_name" "$base_plan" >/dev/null 2>&1; then
      continue
    fi
    append_plan_entries "$optional_plan" "$package_name"
  done < <(read_plan_file "$plan_file")

  install_from_plan_file "$backend" "$optional_plan" optional "optional packages"
  rm -f "$optional_plan"
}

base_plan_has_package() {
  local package_name="$1"
  shift
  local plan_file
  for plan_file in "$@"; do
    [[ -f "$plan_file" ]] || continue
    if grep -Fx "$package_name" "$plan_file" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

configure_base_shell() {
  base_plan_has_package "zsh" "$@" || return 0

  local shell_path="/bin/zsh"
  local oh_my_zsh_dir="$TARGET_HOME/.oh-my-zsh"
  local custom_plugins_dir="$oh_my_zsh_dir/custom/plugins"
  local zshrc_path="$TARGET_HOME/.zshrc"

  if [[ "$DRY_RUN" -eq 0 ]] && ! command -v zsh >/dev/null 2>&1; then
    log_warn "zsh was planned but not found after base package install; retrying direct install."
    package_install_idempotent dnf zsh
    command -v zsh >/dev/null 2>&1 || die "zsh is part of the base install but could not be installed. Check package manager output above."
  fi

  if [[ ! -d "$oh_my_zsh_dir" ]]; then
    run_cmd_as_user "$TARGET_USER" bash -lc 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$custom_plugins_dir"
  run_cmd_as_user "$TARGET_USER" mkdir -p "$TARGET_HOME/.zsh" "$TARGET_HOME/.zshrc.d"

  if [[ ! -d "$custom_plugins_dir/zsh-autosuggestions" ]]; then
    run_cmd_as_user "$TARGET_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "$custom_plugins_dir/zsh-autosuggestions"
  fi

  if [[ ! -d "$custom_plugins_dir/zsh-syntax-highlighting" ]]; then
    run_cmd_as_user "$TARGET_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting "$custom_plugins_dir/zsh-syntax-highlighting"
  fi

  if ! grep -qxF "$shell_path" /etc/shells 2>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'DRY-RUN: append %s to /etc/shells\n' "$shell_path"
    else
      run_cmd_as_root sh -c 'printf "%s\n" "$1" >> /etc/shells' sh "$shell_path"
    fi
  fi

  if [[ -f "$zshrc_path" && ! -L "$zshrc_path" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'DRY-RUN: rm -f %s\n' "$zshrc_path"
    else
      run_cmd_as_user "$TARGET_USER" rm -f "$zshrc_path"
    fi
  fi

  local current_shell=""
  current_shell="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7 || true)"
  if [[ -z "$current_shell" ]]; then
    die "Could not resolve current login shell for target user '$TARGET_USER'."
  fi
  if [[ "$current_shell" != "$shell_path" ]]; then
    run_cmd_as_root chsh -s "$shell_path" "$TARGET_USER"
  fi
}

configure_login_manager() {
  base_plan_has_package "sddm" "$@" || return 0

  run_cmd_as_root systemctl daemon-reload || return 1
  if ! distro_service_exists sddm; then
    log_warn "sddm.service was not detected after base package installation; retrying direct SDDM package install."
    package_install_idempotent "$(native_backend_for_distro "$DISTRO")" sddm || return 1
    run_cmd_as_root systemctl daemon-reload || return 1
  fi
  if ! distro_service_exists sddm; then
    die "SDDM is part of the base install, but sddm.service is still not available after a direct install retry. Check the package manager output above."
  fi

  run_cmd_as_root systemctl set-default graphical.target || return 1
  run_cmd_as_root systemctl enable --force sddm.service || return 1
  printf 'SDDM is enabled. Reboot to start the graphical login.\n'
}

configure_niri_session() {
  base_plan_has_package "niri" "$@" || return 0

  local session_file="/usr/share/wayland-sessions/niri.desktop"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: verify niri command and %s\n' "$session_file"
    return 0
  fi

  if command -v niri >/dev/null 2>&1 && [[ -f "$session_file" ]]; then
    return 0
  fi

  log_warn "Niri or its Wayland session file was not detected after base package installation; retrying direct Niri package install."
  package_install_idempotent "$(native_backend_for_distro "$DISTRO")" niri || return 1

  command -v niri >/dev/null 2>&1 || die "Niri is part of the base install, but the niri command is still unavailable after a direct install retry. Check the package manager output above."
  [[ -f "$session_file" ]] || die "Niri is installed, but $session_file is missing, so SDDM will not show a Niri session."
}

configure_base_system_services() {
  local service_name
  while IFS= read -r service_name; do
    [[ -n "$service_name" ]] || continue
    if [[ "$DRY_RUN" -eq 1 ]]; then
      distro_enable_service_now "$service_name" || return 1
    else
      enable_required_system_service_now "$service_name" || return 1
    fi
  done < <(system_services_now_from_plan)
}

module_30_packages() {
  local dnf_early_base_plan flatpak_early_base_plan
  local dnf_base_plan flatpak_base_plan
  dnf_early_base_plan="$(mktemp "$CACHE_DIR/base-early-dnf.XXXXXX")"
  flatpak_early_base_plan="$(mktemp "$CACHE_DIR/base-early-flatpak.XXXXXX")"
  dnf_base_plan="$(mktemp "$CACHE_DIR/base-dnf.XXXXXX")"
  flatpak_base_plan="$(mktemp "$CACHE_DIR/base-flatpak.XXXXXX")"

  build_base_package_plan_for_backend dnf "$dnf_early_base_plan" early || return 1
  build_base_package_plan_for_backend flatpak "$flatpak_early_base_plan" early || return 1

  install_base_packages_for_backend dnf "$dnf_early_base_plan" || return 1
  install_base_packages_for_backend flatpak "$flatpak_early_base_plan" || return 1

  configure_login_manager "$dnf_early_base_plan" "$flatpak_early_base_plan" || return 1
  configure_base_system_services || return 1

  build_base_package_plan_for_backend dnf "$dnf_base_plan" remaining || return 1
  build_base_package_plan_for_backend flatpak "$flatpak_base_plan" remaining || return 1

  install_base_packages_for_backend dnf "$dnf_base_plan" || return 1
  install_base_packages_for_backend flatpak "$flatpak_base_plan" || return 1

  configure_niri_session "$dnf_base_plan" "$flatpak_base_plan" || return 1
  configure_base_shell "$dnf_base_plan" "$flatpak_base_plan" || return 1

  rm -f \
    "$dnf_early_base_plan" \
    "$flatpak_early_base_plan" \
    "$dnf_base_plan" \
    "$flatpak_base_plan"
}

module_32_optional_packages() {
  local dnf_base_plan flatpak_base_plan
  dnf_base_plan="$(mktemp "$CACHE_DIR/base-dnf.XXXXXX")"
  flatpak_base_plan="$(mktemp "$CACHE_DIR/base-flatpak.XXXXXX")"

  build_base_package_plan_for_backend dnf "$dnf_base_plan"
  build_base_package_plan_for_backend flatpak "$flatpak_base_plan"

  install_optional_packages_for_backend flatpak "$PLAN_DIR/flatpak/apps.flatpaks" "$flatpak_base_plan"
  install_optional_packages_for_backend dnf "$PLAN_DIR/packages/dnf.pkgs" "$dnf_base_plan"

  rm -f "$dnf_base_plan" "$flatpak_base_plan"
}
