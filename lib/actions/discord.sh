#!/usr/bin/env bash
set -Eeuo pipefail

# Official Discord RPM custom action.

DISCORD_RPM_URL="https://discord.com/api/download?platform=linux&format=rpm"

discord_official_rpm_installed() {
  rpm -q discord >/dev/null 2>&1 && [[ -x /usr/bin/discord ]]
}

install_discord() {
  if discord_official_rpm_installed; then
    log_info "Discord RPM is already installed"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install official Discord RPM from %s\n' "$DISCORD_RPM_URL"
    return 0
  fi

  log_progress "Installing the official Discord RPM"
  local downloaded_rpm rpm_identity
  downloaded_rpm="$(mktemp --suffix=.rpm "$CACHE_DIR/discord.XXXXXX")"
  if ! run_cmd curl -fsSL "$DISCORD_RPM_URL" -o "$downloaded_rpm"; then
    rm -f "$downloaded_rpm"
    return 1
  fi

  rpm_identity="$(rpm -qp --qf $'%{NAME}\t%{ARCH}\n' "$downloaded_rpm" 2>/dev/null || true)"
  if [[ "$rpm_identity" != $'discord\tx86_64' ]]; then
    log_warn "Discord download did not contain the expected discord.x86_64 RPM."
    rm -f "$downloaded_rpm"
    return 1
  fi

  if ! run_cmd_as_root dnf install -y "$downloaded_rpm"; then
    rm -f "$downloaded_rpm"
    return 1
  fi
  rm -f "$downloaded_rpm"
}

register_action "discord" install_discord discord_official_rpm_installed
