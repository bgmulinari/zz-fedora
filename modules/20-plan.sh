#!/usr/bin/env bash
set -Eeuo pipefail

module_20_plan() {
  tui_show_install_plan
  if [[ "$COMMAND" == "wizard" && "$ASSUME_YES" -ne 1 ]]; then
    if ! tui_confirm "Proceed with this install plan?"; then
      printf 'Install cancelled.\n'
      exit 0
    fi
  fi
}
