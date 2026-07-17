#!/usr/bin/env bash
set -Eeuo pipefail

module_35_custom_actions() {
  [[ -f "$PLAN_DIR/actions/actions.list" ]] || return 0

  log_progress "Building optional custom action list"
  local base_action_plan optional_action_plan action
  base_action_plan="$(mktemp "$CACHE_DIR/base-actions.XXXXXX")"
  optional_action_plan="$(mktemp "$CACHE_DIR/optional-actions.XXXXXX")"
  build_base_package_plan_for_backend action "$base_action_plan"

  while IFS= read -r action; do
    [[ -n "$action" ]] || continue
    if grep -Fx "$action" "$base_action_plan" >/dev/null 2>&1; then
      continue
    fi
    append_plan_entries "$optional_action_plan" "$action"
  done < <(read_plan_file "$PLAN_DIR/actions/actions.list")

  run_actions_from_plan_file "$optional_action_plan" optional "optional custom actions"
  rm -f "$base_action_plan" "$optional_action_plan"
}
