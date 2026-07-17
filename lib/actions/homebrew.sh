#!/usr/bin/env bash
set -Eeuo pipefail

# Homebrew bootstrap and brew:<package> custom actions.

BREW_PREFIX="/home/linuxbrew/.linuxbrew"
HOMEBREW_INSTALL_COMMIT="c7952e40b7957268f61643152f4db725379b292e"
HOMEBREW_INSTALL_SHA256="99287f194a8b3c9e6b0203a11a5fa54518be57209343e6bb954dec4635796d9d"

install_homebrew_if_needed() {
  if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Homebrew -> %s\n' "$BREW_PREFIX"
    return 0
  fi

  log_progress "Installing Homebrew"
  run_cmd_as_root mkdir -p "$BREW_PREFIX"
  run_cmd_as_root chown -R "$TARGET_USER:$TARGET_USER" /home/linuxbrew
  local install_script install_script_q
  install_script="$(mktemp "$CACHE_DIR/homebrew-install.XXXXXX")"
  if ! run_cmd curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/$HOMEBREW_INSTALL_COMMIT/install.sh" -o "$install_script" \
    || ! printf '%s  %s\n' "$HOMEBREW_INSTALL_SHA256" "$install_script" | sha256sum -c -; then
    rm -f "$install_script"
    return 1
  fi
  run_cmd chmod 0755 "$install_script"
  printf -v install_script_q '%q' "$install_script"
  run_user_login_shell "NONINTERACTIVE=1 /bin/bash $install_script_q"
  rm -f "$install_script"
}

install_brew_package() {
  local package="$1"
  log_progress "Installing Homebrew package: $package"
  install_homebrew_if_needed
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: brew install %s\n' "$package"
    return 0
  fi
  run_user_login_shell "brew list '$package' >/dev/null 2>&1 || brew install '$package'"
  run_user_login_shell "if brew list openssl@3 >/dev/null 2>&1 || brew list openssl >/dev/null 2>&1; then brew postinstall ca-certificates; fi"
}

verify_brew_package() {
  local package="$1" package_q
  printf -v package_q '%q' "$package"
  [[ -x "$BREW_PREFIX/bin/brew" ]] \
    && run_user_login_shell "brew list $package_q >/dev/null 2>&1"
}

register_action "brew" install_brew_package verify_brew_package
