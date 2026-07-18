#!/usr/bin/env bash
set -Eeuo pipefail

# Custom action registry and dispatch. Each lib/actions/*.sh file owns one
# action family (constants, installer, verifier) and describes its actions
# with register_action rows; this file only provides the registry, shared
# helpers, and the plan-file runner.

declare -Ag ACTION_INSTALL_FN=()
declare -Ag ACTION_VERIFY_FN=()

# register_action <id> <install_fn> [verify_fn]
# One row fully describes a custom action. Prefixed actions such as
# brew:<package> register under the bare prefix (brew) and their install and
# verify functions receive the suffix as their single argument. Actions
# without a verify function always pass verification.
register_action() {
  local action_id="$1" install_fn="$2" verify_fn="${3:-}"
  ACTION_INSTALL_FN["$action_id"]="$install_fn"
  if [[ -n "$verify_fn" ]]; then
    ACTION_VERIFY_FN["$action_id"]="$verify_fn"
  fi
}

action_plan_has() {
  local expected="$1"
  [[ -f "$PLAN_DIR/actions/actions.list" ]] || return 1
  grep -Fx "$expected" "$PLAN_DIR/actions/actions.list" >/dev/null 2>&1
}

run_user_login_shell() {
  local script="$1"
  local local_bin dotnet_root dotnet_tools brew_bin
  printf -v local_bin '%q' "$TARGET_HOME/.local/bin"
  printf -v dotnet_root '%q' "$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME"
  printf -v dotnet_tools '%q' "$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME/tools"
  printf -v brew_bin '%q' "$BREW_PREFIX/bin"
  run_cmd_as_user "$TARGET_USER" bash -lc "export PATH=$local_bin:$dotnet_root:$dotnet_tools:$brew_bin:\"\$PATH\"; $script"
}

# shellcheck source=./actions/homebrew.sh
source "$ROOT_DIR/lib/actions/homebrew.sh"
# shellcheck source=./actions/npm.sh
source "$ROOT_DIR/lib/actions/npm.sh"
# shellcheck source=./actions/vscode.sh
source "$ROOT_DIR/lib/actions/vscode.sh"
# shellcheck source=./actions/pywalfox.sh
source "$ROOT_DIR/lib/actions/pywalfox.sh"
# shellcheck source=./actions/claude-code.sh
source "$ROOT_DIR/lib/actions/claude-code.sh"
# shellcheck source=./actions/jetbrains.sh
source "$ROOT_DIR/lib/actions/jetbrains.sh"
# shellcheck source=./actions/devtunnel.sh
source "$ROOT_DIR/lib/actions/devtunnel.sh"
# shellcheck source=./actions/discord.sh
source "$ROOT_DIR/lib/actions/discord.sh"
# shellcheck source=./actions/docker.sh
source "$ROOT_DIR/lib/actions/docker.sh"
# shellcheck source=./actions/dotnet.sh
source "$ROOT_DIR/lib/actions/dotnet.sh"
# shellcheck source=./actions/fonts.sh
source "$ROOT_DIR/lib/actions/fonts.sh"
# shellcheck source=./actions/noctalia-greeter.sh
source "$ROOT_DIR/lib/actions/noctalia-greeter.sh"
# shellcheck source=./actions/media.sh
source "$ROOT_DIR/lib/actions/media.sh"

# split_action_id <action> stores the registry key in ACTION_DISPATCH_ID and
# the prefixed-action argument (empty for plain actions) in ACTION_DISPATCH_ARG.
split_action_id() {
  local action="$1"
  ACTION_DISPATCH_ID="$action"
  ACTION_DISPATCH_ARG=""
  if [[ "$action" == *:* ]]; then
    ACTION_DISPATCH_ID="${action%%:*}"
    ACTION_DISPATCH_ARG="${action#*:}"
  fi
}

# action_registered <action> succeeds when the action id (or the bare prefix
# for prefixed actions such as brew:<package>) has a registered installer.
action_registered() {
  split_action_id "$1"
  [[ -n "${ACTION_INSTALL_FN[$ACTION_DISPATCH_ID]:-}" ]]
}

# validate_action_manifest <manifest_file> fails fast when a .actions manifest
# references an action id that no lib/actions/*.sh file registered.
validate_action_manifest() {
  local manifest_file="$1"
  local action
  while IFS= read -r action; do
    [[ -n "$action" ]] || continue
    action_registered "$action" || die "Unknown custom action '$action' in $manifest_file: no register_action row declares it (see lib/actions/*.sh)"
  done < <(manifest_entries "$manifest_file")
}

run_custom_action() {
  local action="$1" install_fn
  split_action_id "$action"
  install_fn="${ACTION_INSTALL_FN[$ACTION_DISPATCH_ID]:-}"
  [[ -n "$install_fn" ]] || die "Unknown custom action: $action"
  log_progress "Running custom action: $action"
  if [[ "$action" == *:* ]]; then
    "$install_fn" "$ACTION_DISPATCH_ARG"
  else
    "$install_fn"
  fi
}

verify_custom_action() {
  local action="$1" verify_fn
  [[ "$DRY_RUN" -eq 0 ]] || return 0
  split_action_id "$action"
  verify_fn="${ACTION_VERIFY_FN[$ACTION_DISPATCH_ID]:-}"
  [[ -n "$verify_fn" ]] || return 0
  if [[ "$action" == *:* ]]; then
    "$verify_fn" "$ACTION_DISPATCH_ARG"
  else
    "$verify_fn"
  fi
}

run_actions_from_plan_file() {
  local plan_file="$1"
  local mode="${2:-optional}"
  local label="${3:-custom actions}"
  [[ -f "$plan_file" ]] || return 0

  local action
  while IFS= read -r action; do
    [[ -n "$action" ]] || continue
    printf 'action: %s\n' "$action"
    log_progress "Starting $label action: $action"
    if run_custom_action "$action" && verify_custom_action "$action"; then
      log_progress "Completed $label action: $action"
      continue
    fi
    if [[ "$mode" == "required" ]]; then
      log_error "Required $label action failed verification: $action"
      return 1
    fi
    log_warn "Optional custom action failed and will be skipped for now: $action"
    append_warning "Optional custom action failed and was skipped: $action"
  done < <(read_plan_file "$plan_file")
}
