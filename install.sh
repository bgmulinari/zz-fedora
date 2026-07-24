#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=./lib/idempotency.sh
source "$ROOT_DIR/lib/idempotency.sh"
# shellcheck source=./lib/hardware.sh
source "$ROOT_DIR/lib/hardware.sh"
# shellcheck source=./lib/cli.sh
source "$ROOT_DIR/lib/cli.sh"
# shellcheck source=./lib/packages.sh
source "$ROOT_DIR/lib/packages.sh"
# shellcheck source=./lib/dotnet.sh
source "$ROOT_DIR/lib/dotnet.sh"
# shellcheck source=./lib/noctalia.sh
source "$ROOT_DIR/lib/noctalia.sh"
# shellcheck source=./lib/actions.sh
source "$ROOT_DIR/lib/actions.sh"
# shellcheck source=./lib/sources.sh
source "$ROOT_DIR/lib/sources.sh"
# shellcheck source=./lib/systemd.sh
source "$ROOT_DIR/lib/systemd.sh"
# shellcheck source=./lib/files.sh
source "$ROOT_DIR/lib/files.sh"
# shellcheck source=./lib/files-user.sh
source "$ROOT_DIR/lib/files-user.sh"
# shellcheck source=./lib/theme-seeds.sh
source "$ROOT_DIR/lib/theme-seeds.sh"
# shellcheck source=./lib/first-run.sh
source "$ROOT_DIR/lib/first-run.sh"
# shellcheck source=./lib/tui.sh
source "$ROOT_DIR/lib/tui.sh"
# shellcheck source=./lib/planner.sh
source "$ROOT_DIR/lib/planner.sh"
# shellcheck source=./lib/readiness.sh
source "$ROOT_DIR/lib/readiness.sh"
# shellcheck source=./lib/fedora.sh
source "$ROOT_DIR/lib/fedora.sh"

for module_file in "$ROOT_DIR"/modules/*.sh; do
  # shellcheck disable=SC1090
  source "$module_file"
done

prepare_context() {
  parse_cli "$@"
  [[ "$COMMAND" != "apply" || "${ZZ_INTERNAL_APPLY:-0}" -eq 1 ]] || die "apply is internal; run install or wizard so the plan is generated first"
  if [[ "$UPDATE_MODE" -eq 1 ]]; then
    [[ "$COMMAND" == "install" ]] || die "--update is supported only with the install command"
    [[ "$USE_SAVED_SELECTIONS" -eq 1 ]] || die "--update requires --use-saved"
  fi
  exec_setup_as_root_if_needed "$@"
  init_log_file
  trap 'fatal_error_handler $?' ERR
  trap cleanup_on_exit EXIT
  if [[ "$USE_SAVED_SELECTIONS" -eq 1 ]]; then
    load_saved_selections
    normalize_saved_selections_for_update
  fi
  require_fedora
  TARGET_HOME="$(resolve_target_home "$TARGET_USER")" || die "Could not resolve home directory for target user '$TARGET_USER'"
}

# First-run owns per-user session state (the completion marker and the
# deferred Flatpak queue) that resolves against the invoking user's home. A
# root invocation would consume root's state tree, write root's marker, and
# strand the target user's pending queue while removing their autostart
# hook, so it is refused instead.
require_first_run_user_context() {
  [[ "$EUID" -eq 0 ]] || return 0
  [[ "$TARGET_USER" != "root" ]] || return 0
  die "first-run manages per-user session state; run it as the target user: su - $TARGET_USER -c 'zz first-run'"
}

step_should_run_always() {
  return 0
}

step_should_run_doctor() {
  [[ "$COMMAND" == "doctor" || "$COMMAND" == "apply" || "$DRY_RUN" -ne 1 ]]
}

step_should_run_optional_software() {
  [[ "$UPDATE_MODE" -eq 0 ]]
}

declare -ag STEP_IDS=()
declare -ag STEP_LABELS=()
declare -ag STEP_DESCRIPTIONS=()
declare -ag STEP_FUNCTIONS=()
declare -ag STEP_PREDICATES=()
declare -ag STEP_FAILURE_POLICIES=()

register_step() {
  STEP_IDS+=("$1")
  STEP_LABELS+=("$2")
  STEP_DESCRIPTIONS+=("$3")
  STEP_FUNCTIONS+=("$4")
  STEP_PREDICATES+=("$5")
  STEP_FAILURE_POLICIES+=("$6")
}

reset_step_registry() {
  STEP_IDS=()
  STEP_LABELS=()
  STEP_DESCRIPTIONS=()
  STEP_FUNCTIONS=()
  STEP_PREDICATES=()
  STEP_FAILURE_POLICIES=()
}

# Declarative install pipeline: one tab-separated row per step with the
# fields id, label, module entrypoint, predicate, failure policy, and
# description. Each entrypoint is a module_NN_* function defined in the
# matching modules/NN-*.sh file. The planning row is included only when the
# registry is built with include_planning=1.
declare -ag INSTALL_STEP_TABLE=(
  $'preflight\tPreflight\tmodule_00_preflight\tstep_should_run_always\tfatal\tValidate the environment, target user, and install prerequisites.'
  $'planning\tPlanning\tmodule_20_plan\tstep_should_run_always\tfatal\tBuild and review the final install plan from defaults and selected bundles.'
  $'bootstrap-tools\tBootstrap Tools\tmodule_05_bootstrap_tools\tstep_should_run_always\tfatal\tInstall the Fedora package-manager helpers needed by the plan.'
  $'sources\tSoftware Sources\tmodule_10_sources\tstep_should_run_always\tfatal\tEnable repositories and remotes required by the current plan.'
  $'base-setup\tBase Setup\tmodule_30_packages\tstep_should_run_always\tfatal\tInstall non-optional base packages and configure the base shell before optional selections.'
  $'optional-packages\tOptional Packages\tmodule_32_optional_packages\tstep_should_run_optional_software\tcontinue\tInstall optional Fedora and Flatpak packages from the generated plan.'
  $'custom-actions\tCustom Actions\tmodule_35_custom_actions\tstep_should_run_optional_software\tcontinue\tRun selected direct installers and package-manager actions.'
  $'user-config\tUser Configuration\tmodule_60_user_config\tstep_should_run_always\tfatal\tInstall product-owned links and seed user-owned configuration.'
  $'post-actions\tPost Actions\tmodule_80_post_actions\tstep_should_run_always\tcontinue\tApply defaults, desktop associations, and final user/system tweaks.'
  $'doctor\tDoctor\tmodule_90_doctor\tstep_should_run_doctor\tfatal\tRun the final verification checks and environment summary.'
)

build_step_registry() {
  local include_planning="${1:-0}"
  reset_step_registry
  local row step_id label function_name predicate failure_policy description
  for row in "${INSTALL_STEP_TABLE[@]}"; do
    IFS=$'\t' read -r step_id label function_name predicate failure_policy description <<<"$row"
    if [[ "$step_id" == "planning" && "$include_planning" -ne 1 ]]; then
      continue
    fi
    register_step "$step_id" "$label" "$description" "$function_name" "$predicate" "$failure_policy"
  done
}

exec_setup_as_root_if_needed() {
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  [[ "$EUID" -eq 0 ]] && return 0
  [[ "$COMMAND" == "wizard" || "$COMMAND" == "install" ]] || return 0

  local -a root_env=(
    "STATE_DIR=$STATE_DIR"
    "CACHE_DIR=$CACHE_DIR"
    "CONFIG_DIR=$CONFIG_DIR"
    "LOG_DIR=$LOG_DIR"
    "STATE_OWNER_USER=${STATE_OWNER_USER:-${USER:-}}"
    "TARGET_USER=$TARGET_USER"
    "TARGET_HOME=$TARGET_HOME"
    "DESKTOP_APP_PROFILE=$DESKTOP_APP_PROFILE"
    # Forward the resolved flag state under the external ZZ_ names so
    # env-only overrides survive the sudo elevation boundary alongside the
    # re-parsed CLI arguments.
    "ZZ_ASSUME_YES=$ASSUME_YES"
    "ZZ_NO_TUI=$NO_TUI"
    "ZZ_INSTALL_WEAK_DEPS=$INSTALL_WEAK_DEPS"
    "ZZ_VERIFY_INSTALLS=$VERIFY_INSTALLS"
    "ZZ_SKIP_USER_CONFIG=$SKIP_USER_CONFIG"
    "ZZ_UPDATE_MODE=$UPDATE_MODE"
  )
  local optional_env
  for optional_env in \
    DISPLAY \
    WAYLAND_DISPLAY \
    XAUTHORITY \
    XDG_RUNTIME_DIR \
    DBUS_SESSION_BUS_ADDRESS \
    XDG_CURRENT_DESKTOP \
    DESKTOP_SESSION \
    TERM \
    COLORTERM; do
    [[ -n "${!optional_env:-}" ]] && root_env+=("$optional_env=${!optional_env}")
  done

  exec_as_root_via_sudo "setup" "${root_env[@]}" "$ROOT_DIR/install.sh" "$@"
}

run_install_step() {
  local current="$1"
  local total="$2"
  local label="$3"
  local description="$4"
  local function_name="$5"
  local predicate="${6:-step_should_run_always}"
  local failure_policy="${7:-fatal}"
  local step_status

  if ! "$predicate"; then
    tui_step_start "$current" "$total" "$label" "$description"
    log_info "Skipped step: $label"
    write_install_progress skipped "$current" "$total" "$label" "$description"
    tui_step_skipped "$label"
    return 0
  fi

  while true; do
    tui_step_start "$current" "$total" "$label" "$description"
    log_info "Running step $current/$total: $label"
    write_install_progress running "$current" "$total" "$label" "$description"
    ACTIVE_STEP_ID="${STEP_IDS[$((current - 1))]:-}"
    ACTIVE_STEP_LABEL="$label"
    ACTIVE_STEP_CURRENT="$current"
    ACTIVE_STEP_TOTAL="$total"
    ACTIVE_STEP_STARTED_AT="$(date +%s)"
    if [[ "$DRY_RUN" -eq 0 && -n "${LOG_FILE:-}" ]]; then
      if tui_run_with_log_capture "$function_name"; then
        step_status=0
      else
        step_status=$?
      fi
    else
      if "$function_name"; then
        step_status=0
      else
        step_status=$?
      fi
    fi

    if [[ "$step_status" -eq 0 ]]; then
      local completed_at elapsed
      completed_at="$(date +%s)"
      elapsed=$((completed_at - ACTIVE_STEP_STARTED_AT))
      ACTIVE_STEP_LABEL=""
      ACTIVE_STEP_ID=""
      ACTIVE_STEP_CURRENT=0
      ACTIVE_STEP_TOTAL=0
      ACTIVE_STEP_STARTED_AT=""
      log_info "Completed step $current/$total: $label (${elapsed}s)"
      write_install_progress "done" "$current" "$total" "$label" "Completed in ${elapsed}s"
      tui_step_done "$label"
      return 0
    fi

    log_error "Failed step $current/$total: $label"
    write_install_progress failed "$current" "$total" "$label" "Exit code $step_status"
    tui_step_failed "$label"
    if [[ "$failure_policy" == "continue" ]]; then
      append_warning "Step failed and setup continued: $label"
      ACTIVE_STEP_LABEL=""
      ACTIVE_STEP_ID=""
      ACTIVE_STEP_CURRENT=0
      ACTIVE_STEP_TOTAL=0
      ACTIVE_STEP_STARTED_AT=""
      return 0
    fi
    if declare -F tui_required_failure_action >/dev/null 2>&1 && tui_required_failure_action "$label" "$step_status"; then
      log_warn "Retrying failed required step: $label"
      continue
    fi
    return 1
  done
}

run_registered_steps() {
  local include_planning="${1:-0}"
  build_step_registry "$include_planning"
  local total="${#STEP_FUNCTIONS[@]}"
  local idx
  local failed=0

  tui_register_steps "${STEP_LABELS[@]}"
  tui_progress_begin
  write_install_progress running 0 "$total" "ZZ Fedora" "Starting installation"

  for idx in "${!STEP_FUNCTIONS[@]}"; do
    if ! run_install_step \
      "$((idx + 1))" \
      "$total" \
      "${STEP_LABELS[$idx]}" \
      "${STEP_DESCRIPTIONS[$idx]}" \
      "${STEP_FUNCTIONS[$idx]}" \
      "${STEP_PREDICATES[$idx]}" \
      "${STEP_FAILURE_POLICIES[$idx]}"; then
      failed=1
      break
    fi
  done
  tui_progress_end
  if [[ "$failed" -eq 0 ]]; then
    write_install_progress "done" "$total" "$total" "ZZ Fedora" "Installation complete"
  else
    write_install_progress failed "$total" "$total" "ZZ Fedora" "Installation failed"
  fi
  return "$failed"
}

apply_install_plan() {
  if tui_can_style; then
    tui_intro
    printf '\n'
    gum style --bold "Installing selected steps... this may take some time. Please wait!"
    printf '\n'
  fi

  TUI_PROGRESS_ACTIVE=1
  local install_status=0
  run_registered_steps 0 || install_status=$?
  tui_progress_end
  TUI_PROGRESS_ACTIVE=0
  tui_summary
  if [[ "$install_status" -eq 0 ]]; then
    prompt_for_reboot
  fi
  return "$install_status"
}

prompt_for_reboot() {
  [[ "$COMMAND" == "install" || "$COMMAND" == "wizard" || "$COMMAND" == "apply" ]] || return 0
  [[ "$DRY_RUN" -eq 0 ]] || return 0

  if [[ "$ASSUME_YES" -eq 1 ]] || ! is_tty; then
    log_info "Reboot recommended to ensure all system changes take effect."
    return 0
  fi

  printf '\n'
  if tui_confirm "Reboot now?"; then
    if [[ "$EUID" -eq 0 ]]; then
      reboot
    else
      run_cmd_as_root reboot
    fi
    return 0
  fi

  log_info "Reboot skipped. Restart later to apply all system changes."
}

main() {
  prepare_context "$@"

  case "$COMMAND" in
    wizard)
      tui_run_wizard
      build_plan_from_selections
      module_20_plan
      apply_install_plan
      ;;
    install)
      build_plan_from_selections
      module_20_plan
      apply_install_plan
      ;;
    apply)
      apply_install_plan
      ;;
    print-plan)
      build_plan_from_selections
      print_plan_summary
      ;;
    check)
      DRY_RUN=1
      build_plan_from_selections
      generate_readiness_status
      print_plan_summary
      printf '\n'
      render_readiness_report
      ;;
    doctor)
      module_00_preflight
      [[ -f "$PLAN_DIR/bundles.list" ]] || build_plan_from_selections
      generate_readiness_status
      render_readiness_report
      module_90_doctor
      ;;
    first-run)
      require_first_run_user_context
      [[ -f "$PLAN_DIR/bundles.list" ]] || build_plan_from_selections
      module_85_first_run
      ;;
    defaults)
      [[ -f "$PLAN_DIR/bundles.list" ]] || build_plan_from_selections
      module_80_defaults
      ;;
    list-profiles)
      list_install_profiles
      ;;
    list-choices)
      local category catalog
      for category in $(category_names); do
        catalog="$(choice_catalog_path "$category")"
        printf '[%s]\n' "$category"
        awk -F'\t' 'NF==5 {printf "%s\t%s\tdefault=%s\n", $1, $2, $3}' "$catalog"
        printf '\n'
      done
      ;;
    list-sources)
      list_sources_pretty
      ;;
    *)
      # parse_cli validates COMMAND against the command catalog, so reaching
      # this arm means a cataloged command has no dispatch case.
      die "Command is in the catalog but has no dispatch arm: $COMMAND"
      ;;
  esac
}

main "$@"
