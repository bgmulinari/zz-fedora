#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
  # shellcheck source=../lib/choices.sh
  source "$ROOT_DIR/lib/choices.sh"
  TARGET_USER="$(id -un)"
  TARGET_HOME="$TEST_ROOT/home"
  COMMAND=install
  UPDATE_MODE=1
  DRY_RUN=1
  ensure_state_dirs
  write_managed_config_conflict_preview() { :; }
}

# A selections file the way an earlier catalog saved it: each offered list
# names the choices that catalog had in the category.
write_saved_selections() {
  mkdir -p "$(dirname "$SAVED_SELECTIONS")"
  {
    printf 'target_user=%s\n' "$TARGET_USER"
    printf 'desktop_app_profile=%s\n' "${DESKTOP_APP_PROFILE:-full}"
    printf 'preferred_browser=firefox\n'
    printf '%s\n' "$@"
  } >"$SAVED_SELECTIONS"
}

# Every choice of a category except the given ones: the offered list of a
# catalog that did not have them yet.
offered_without() {
  local category="$1"
  shift
  local -a ids=()
  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    array_contains "$id" "$@" && continue
    ids+=("$id")
  done < <(all_choice_ids "$category")
  join_by , "${ids[@]}"
}

selected_ids() {
  effective_choice_ids "$1" | paste -sd ,
}

# Runs a function in this shell, so the selection state it changes stays,
# with its output and status in $output and $status.
run_in_shell() {
  local had_errexit=0
  [[ "$-" == *e* ]] && had_errexit=1
  set +e
  run_without_bats_debug_trap "$@" >"$TEST_ROOT/run-in-shell.log" 2>&1
  status=$?
  [[ "$had_errexit" -eq 1 ]] && set -e
  output="$(cat "$TEST_ROOT/run-in-shell.log")"
  [[ "$status" -eq 0 ]] || printf '%s\n' "$output" >&2
}

@test "update mode selects a default the catalog gained since the selections were saved" {
  write_saved_selections \
    "select.gaming=steam" "offered.gaming=$(offered_without gaming proton-manager)" \
    "select.dev=vscode" "offered.dev=$(offered_without dev)"
  load_saved_selections

  run_in_shell normalize_saved_selections_for_update
  [ "$status" -eq 0 ]
  assert_contains "$output" "New default choice 'proton-manager' in category 'gaming' was added to the saved selections."
  assert_equal "steam,proton-manager" "$(selected_ids gaming)"
  assert_equal $'gaming\tproton-manager' "$(printf '%s\n' "${NEW_DEFAULT_CHOICES[@]}")"
  # Zed is a default the saved catalog offered and the user did not keep.
  assert_equal "vscode" "$(selected_ids dev)"
  refute_contains "$output" "'zed'"
}

@test "a saved category without an offered list gets nothing added" {
  write_saved_selections "select.gaming=steam"
  load_saved_selections

  run_in_shell normalize_saved_selections_for_update
  [ "$status" -eq 0 ]
  refute_contains "$output" "New default choice"
  assert_equal "steam" "$(selected_ids gaming)"
  [ "${#NEW_DEFAULT_CHOICES[@]}" -eq 0 ]
}

@test "a new nested default follows its parent's selection" {
  write_saved_selections "select.dotnet=" "offered.dotnet=sdk"
  load_saved_selections

  run_in_shell normalize_saved_selections_for_update
  [ "$status" -eq 0 ]
  assert_contains "$output" "New default choice 'ef' in category 'dotnet' stays unselected because its parent 'sdk' is not selected."
  assert_equal "" "$(selected_ids dotnet)"
  [ "${#NEW_DEFAULT_CHOICES[@]}" -eq 0 ]

  # A newly offered parent brings its new default children along.
  write_saved_selections "select.dotnet=" "offered.dotnet="
  load_saved_selections
  run_in_shell normalize_saved_selections_for_update
  [ "$status" -eq 0 ]
  assert_contains "$output" "New default choice 'sdk' in category 'dotnet' was added to the saved selections."
  assert_contains "$output" "New default choice 'ef' in category 'dotnet' was added to the saved selections."
  run grep -E '(^|,)sdk(,|$)' <<<"$(selected_ids dotnet)"
  [ "$status" -eq 0 ]
  run grep -E '(^|,)ef(,|$)' <<<"$(selected_ids dotnet)"
  [ "$status" -eq 0 ]
}

@test "the minimal desktop profile takes no new desktop defaults" {
  DESKTOP_APP_PROFILE=minimal
  write_saved_selections "select.desktop=" "offered.desktop=$(offered_without desktop calculator)"
  load_saved_selections

  run_in_shell normalize_saved_selections_for_update
  [ "$status" -eq 0 ]
  refute_contains "$output" "New default choice"
  assert_equal "" "$(selected_ids desktop)"
}

@test "saving selections records the choices the catalog offered" {
  reset_test_selections
  set_category_override gaming "steam"
  save_selections

  assert_file_contains "$SAVED_SELECTIONS" "select.gaming=steam"
  assert_file_contains "$SAVED_SELECTIONS" "offered.gaming=$(offered_without gaming)"
  assert_file_contains "$SAVED_SELECTIONS" "offered.dev=$(offered_without dev)"
}

@test "the new-defaults step installs the new choices' units and saves them once they are in place" {
  write_saved_selections \
    "select.gaming=steam" "offered.gaming=$(offered_without gaming proton-manager)" \
    "select.dev=vscode" "offered.dev=$(offered_without dev zed)"
  load_saved_selections
  run_in_shell normalize_saved_selections_for_update
  run_in_shell build_plan_from_selections

  # The plan carries the new choices, but the selections wait for the step.
  assert_plan_has "$PLAN_DIR/bundles.list" "dev-zed"
  assert_plan_has "$PLAN_DIR/bundles.list" "gaming-proton-manager"
  assert_plan_has "$PLAN_DIR/config/components.list" "dms-plugin-proton-manager"
  assert_file_contains "$SAVED_SELECTIONS" "select.dev=vscode"
  refute_saved_choice dev zed

  apply_units_focused() { printf 'APPLY: %s\n' "$*"; }
  run run_without_bats_debug_trap module_40_new_defaults
  [ "$status" -eq 0 ]
  assert_contains "$output" "Development / Zed"
  assert_contains "$output" "Gaming / Proton Manager"
  assert_contains "$output" "APPLY: "
  assert_contains "$output" "dev-zed"
  assert_contains "$output" "gaming-proton-manager"
  assert_file_contains "$SAVED_SELECTIONS" "select.dev=vscode,zed"
  assert_file_contains "$SAVED_SELECTIONS" "select.gaming=steam,proton-manager"
  assert_file_contains "$SAVED_SELECTIONS" "offered.dev=$(offered_without dev)"
}

@test "a failed new-defaults install leaves the choices for the next update to retry" {
  write_saved_selections \
    "select.dev=vscode" "offered.dev=$(offered_without dev zed)"
  load_saved_selections
  run_in_shell normalize_saved_selections_for_update
  run_in_shell build_plan_from_selections

  apply_units_focused() { return 1; }
  run_in_shell module_40_new_defaults
  [ "$status" -ne 0 ]
  assert_contains "$(printf '%s\n' "${WARNING_MESSAGES[@]}")" "New defaults were not installed and will be retried by the next update: Development / Zed"
  assert_equal "vscode" "$(selected_ids dev)"
  assert_file_contains "$SAVED_SELECTIONS" "select.dev=vscode"
  assert_file_contains "$SAVED_SELECTIONS" "offered.dev=$(offered_without dev zed)"

  # The next update finds the same new default again.
  DEFERRED_DEFAULT_CHOICES=()
  CATEGORY_OFFERED=()
  CATEGORY_OFFERED_PRESENT=()
  load_saved_selections
  run_in_shell normalize_saved_selections_for_update
  [ "$status" -eq 0 ]
  assert_contains "$output" "New default choice 'zed' in category 'dev' was added to the saved selections."
}
