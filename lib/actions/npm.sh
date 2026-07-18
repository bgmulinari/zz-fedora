#!/usr/bin/env bash
set -Eeuo pipefail

# npm-global:<package> custom actions.

install_npm_global_package() {
  local package="$1"
  log_progress "Installing npm global package: $package"
  run_cmd_as_root npm install -g "$package"
}

verify_npm_global_package() {
  local package="$1"
  npm list -g --depth=0 "$package" >/dev/null 2>&1
}

register_action "npm-global" install_npm_global_package verify_npm_global_package
