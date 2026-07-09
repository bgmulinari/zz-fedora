#!/usr/bin/env bash
set -Eeuo pipefail

module_60_dotfiles() {
  [[ "$SKIP_DOTFILES" -eq 1 ]] && return 0
  log_progress "Applying managed dotfiles"
  stow_apply_plan
}
