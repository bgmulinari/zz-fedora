#!/usr/bin/env bash
set -Eeuo pipefail

# npm-global:<package> custom actions. Global packages belong to the target
# user under ~/.local, the prefix the managed /etc/npmrc gives every npm run,
# so a plain `npm install -g` and the packages' own self-updaters work without
# root. The prefix is passed explicitly because these actions run before the
# User Configuration step installs /etc/npmrc.

npm_global_prefix() {
  printf '%s/.local\n' "$TARGET_HOME"
}

# Print the installed global package names, one per line, scoped packages as
# @scope/name. Reads the prefix directly instead of running `npm ls -g`, which
# costs a Node startup and writes npm's log files.
npm_global_packages() {
  local modules_dir entry
  modules_dir="$(npm_global_prefix)/lib/node_modules"
  [[ -d "$modules_dir" ]] || return 0
  for entry in "$modules_dir"/*/package.json "$modules_dir"/@*/*/package.json; do
    [[ -f "$entry" ]] || continue
    entry="${entry%/package.json}"
    printf '%s\n' "${entry#"$modules_dir"/}"
  done
}

install_npm_global_package() {
  local package="$1"
  log_progress "Installing npm global package: $package"
  run_cmd_as_user "$TARGET_USER" npm install -g --prefix "$(npm_global_prefix)" "$package"
}

verify_npm_global_package() {
  local package="$1"
  [[ -f "$(npm_global_prefix)/lib/node_modules/$package/package.json" ]]
}

remove_npm_global_package() {
  local package="$1"
  log_progress "Removing npm global package: $package"
  run_cmd_as_user "$TARGET_USER" npm uninstall -g --prefix "$(npm_global_prefix)" "$package"
}

register_action "npm-global" install_npm_global_package verify_npm_global_package
