#!/usr/bin/env bash
set -Eeuo pipefail

module_20_plan() {
  generate_readiness_status
  tui_show_install_plan
  printf '\n'
  render_readiness_report
  if [[ "$COMMAND" == "wizard" && "$ASSUME_YES" -ne 1 ]]; then
    printf '\n'
    if ! tui_confirm "Proceed with this install plan?"; then
      printf 'Install cancelled.\n'
      exit 0
    fi
  fi
}
