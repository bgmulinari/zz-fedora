#!/usr/bin/env bash
set -Eeuo pipefail

module_20_should_render_readiness_report() {
  [[ "$COMMAND" == "wizard" && "$ASSUME_YES" -ne 1 ]] && return 1
  return 0
}

module_20_plan() {
  log_progress "Generating readiness status"
  generate_readiness_status
  log_progress "Rendering install plan"
  tui_show_install_plan
  if module_20_should_render_readiness_report; then
    printf '\n'
    log_progress "Rendering readiness report"
    render_readiness_report
  fi
  if [[ "$COMMAND" == "wizard" && "$ASSUME_YES" -ne 1 ]]; then
    printf '\n'
    if ! tui_confirm "Proceed with this install plan?"; then
      printf 'Install cancelled.\n'
      exit 0
    fi
  fi
}
