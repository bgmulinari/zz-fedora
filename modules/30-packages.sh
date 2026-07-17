#!/usr/bin/env bash
set -Eeuo pipefail

OH_MY_ZSH_REPOSITORY="https://github.com/ohmyzsh/ohmyzsh.git"
OH_MY_ZSH_COMMIT="d2379b2701df66a36b217a7707e77f8029a99814"
ZSH_AUTOSUGGESTIONS_REPOSITORY="https://github.com/zsh-users/zsh-autosuggestions.git"
ZSH_AUTOSUGGESTIONS_COMMIT="85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5"
ZSH_SYNTAX_HIGHLIGHTING_REPOSITORY="https://github.com/zsh-users/zsh-syntax-highlighting.git"
ZSH_SYNTAX_HIGHLIGHTING_COMMIT="1d85c692615a25fe2293bdd44b34c217d5d2bf04"

install_base_packages_for_backend() {
  local backend="$1"
  local base_plan="$2"
  log_progress "Preparing $backend base package transaction"
  install_from_plan_file "$backend" "$base_plan" required "base packages"
}

install_base_actions_from_plan() {
  local action_plan="$1"
  log_progress "Running required base actions"
  run_actions_from_plan_file "$action_plan" required "base actions"
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

  log_progress "Configuring the target user's shell"
  local shell_path="/bin/zsh"
  local oh_my_zsh_dir="$TARGET_HOME/.oh-my-zsh"
  local custom_plugins_dir="$oh_my_zsh_dir/custom/plugins"
  local zshrc_path="$TARGET_HOME/.zshrc"

  if [[ "$DRY_RUN" -eq 0 ]] && ! command -v zsh >/dev/null 2>&1; then
    log_warn "zsh was planned but not found after base package install; retrying direct install."
    package_install_idempotent dnf zsh
    command -v zsh >/dev/null 2>&1 || die "zsh is part of the base install but could not be installed. Check package manager output above."
  fi

  log_progress "Installing pinned Oh My Zsh for $TARGET_USER"
  install_pinned_git_checkout "Oh My Zsh" "$OH_MY_ZSH_REPOSITORY" "$OH_MY_ZSH_COMMIT" "$oh_my_zsh_dir"

  run_cmd_as_user "$TARGET_USER" mkdir -p "$custom_plugins_dir"
  run_cmd_as_user "$TARGET_USER" mkdir -p "$TARGET_HOME/.zsh" "$TARGET_HOME/.zshrc.d"

  log_progress "Installing pinned zsh autosuggestions"
  install_pinned_git_checkout "zsh-autosuggestions" "$ZSH_AUTOSUGGESTIONS_REPOSITORY" "$ZSH_AUTOSUGGESTIONS_COMMIT" "$custom_plugins_dir/zsh-autosuggestions"

  log_progress "Installing pinned zsh syntax highlighting"
  install_pinned_git_checkout "zsh-syntax-highlighting" "$ZSH_SYNTAX_HIGHLIGHTING_REPOSITORY" "$ZSH_SYNTAX_HIGHLIGHTING_COMMIT" "$custom_plugins_dir/zsh-syntax-highlighting"

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
    log_progress "Setting $TARGET_USER login shell to zsh"
    run_cmd_as_root chsh -s "$shell_path" "$TARGET_USER"
  fi
}

configure_niri_session() {
  base_plan_has_package "niri" "$@" || return 0

  log_progress "Verifying Niri session availability"
  local session_file="/usr/share/wayland-sessions/niri.desktop"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: verify niri command and %s\n' "$session_file"
    return 0
  fi

  if command -v niri >/dev/null 2>&1 && [[ -f "$session_file" ]]; then
    return 0
  fi

  log_warn "Niri or its Wayland session file was not detected after base package installation; retrying direct Niri package install."
  package_install_idempotent "$(native_backend)" niri || return 1

  command -v niri >/dev/null 2>&1 || die "Niri is part of the base install, but the niri command is still unavailable after a direct install retry. Check the package manager output above."
  [[ -f "$session_file" ]] || die "Niri is installed, but $session_file is missing, so the display manager will not show a Niri session."
}

configure_base_system_services() {
  local service_name
  local -a service_names=()
  while IFS= read -r service_name; do
    [[ -n "$service_name" ]] || continue
    log_progress "Enabling system service: $service_name"
    service_names+=("$service_name")
  done < <(system_services_now_from_plan)

  if [[ "$DRY_RUN" -eq 1 ]]; then
    fedora_enable_services_now "${service_names[@]}" || return 1
  else
    enable_required_system_services_now "${service_names[@]}" || return 1
  fi
}

module_30_packages() {
  local dnf_early_base_plan flatpak_early_base_plan
  local dnf_base_plan flatpak_base_plan action_base_plan
  dnf_early_base_plan="$(mktemp "$CACHE_DIR/base-early-dnf.XXXXXX")"
  flatpak_early_base_plan="$(mktemp "$CACHE_DIR/base-early-flatpak.XXXXXX")"
  dnf_base_plan="$(mktemp "$CACHE_DIR/base-dnf.XXXXXX")"
  flatpak_base_plan="$(mktemp "$CACHE_DIR/base-flatpak.XXXXXX")"
  action_base_plan="$(mktemp "$CACHE_DIR/base-actions.XXXXXX")"

  log_progress "Building early base package plan"
  build_base_package_plan_for_backend dnf "$dnf_early_base_plan" early || return 1
  build_base_package_plan_for_backend flatpak "$flatpak_early_base_plan" early || return 1

  log_progress "Installing early base packages"
  install_base_packages_for_backend dnf "$dnf_early_base_plan" || return 1
  install_base_packages_for_backend flatpak "$flatpak_early_base_plan" || return 1

  log_progress "Enabling base system services"
  configure_base_system_services || return 1

  log_progress "Building remaining base package plan"
  build_base_package_plan_for_backend dnf "$dnf_base_plan" remaining || return 1
  build_base_package_plan_for_backend flatpak "$flatpak_base_plan" remaining || return 1
  build_base_package_plan_for_backend action "$action_base_plan" remaining || return 1

  log_progress "Installing remaining base packages"
  install_base_packages_for_backend dnf "$dnf_base_plan" || return 1
  install_base_packages_for_backend flatpak "$flatpak_base_plan" || return 1

  log_progress "Configuring base desktop session"
  configure_niri_session "$dnf_base_plan" "$flatpak_base_plan" || return 1
  configure_base_shell "$dnf_base_plan" "$flatpak_base_plan" || return 1
  install_base_actions_from_plan "$action_base_plan" || return 1

  rm -f \
    "$dnf_early_base_plan" \
    "$flatpak_early_base_plan" \
    "$dnf_base_plan" \
    "$flatpak_base_plan" \
    "$action_base_plan"
}
