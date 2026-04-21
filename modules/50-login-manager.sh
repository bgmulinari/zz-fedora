#!/usr/bin/env bash
set -Eeuo pipefail

module_50_login_manager() {
  [[ "$SKIP_LOGIN_MANAGER" -eq 1 ]] && return 0
  run_cmd sudo systemctl set-default graphical.target
  run_cmd sudo systemctl enable --force plasmalogin.service
  printf 'Plasma Login Manager is enabled. Reboot to start the graphical login.\n'
}
