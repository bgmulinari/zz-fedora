#!/usr/bin/env bash
set -Eeuo pipefail

module_50_login_manager() {
  [[ "$SKIP_LOGIN_MANAGER" -eq 1 ]] && return 0
  run_cmd sudo systemctl set-default graphical.target
  if distro_service_exists sddm; then
    run_cmd sudo systemctl enable --force sddm.service
    printf 'SDDM is enabled. Reboot to start the graphical login.\n'
  else
    die "SDDM service is not available after package installation. Check the package step above before rebooting."
  fi
}
