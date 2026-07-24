#!/usr/bin/env bash
set -Eeuo pipefail

module_60_user_config() {
  log_progress "Applying managed configuration"
  apply_managed_config_plan
}
