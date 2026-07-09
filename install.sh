#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=./lib/idempotency.sh
source "$ROOT_DIR/lib/idempotency.sh"
# shellcheck source=./lib/cli.sh
source "$ROOT_DIR/lib/cli.sh"
# shellcheck source=./lib/packages.sh
source "$ROOT_DIR/lib/packages.sh"
# shellcheck source=./lib/sources.sh
source "$ROOT_DIR/lib/sources.sh"
# shellcheck source=./lib/systemd.sh
source "$ROOT_DIR/lib/systemd.sh"
# shellcheck source=./lib/stow.sh
source "$ROOT_DIR/lib/stow.sh"
# shellcheck source=./lib/files.sh
source "$ROOT_DIR/lib/files.sh"
# shellcheck source=./lib/os.sh
source "$ROOT_DIR/lib/os.sh"
# shellcheck source=./lib/tui.sh
source "$ROOT_DIR/lib/tui.sh"
# shellcheck source=./lib/planner.sh
source "$ROOT_DIR/lib/planner.sh"
# shellcheck source=./lib/readiness.sh
source "$ROOT_DIR/lib/readiness.sh"

for module_file in "$ROOT_DIR"/modules/*.sh; do
  # shellcheck disable=SC1090
  source "$module_file"
done

prepare_context() {
  parse_cli "$@"
  [[ "$COMMAND" != "apply" || "${ZZ_INTERNAL_APPLY:-0}" -eq 1 ]] || die "apply is internal; run install or wizard so the plan is generated first"
  exec_setup_as_root_if_needed "$@"
  init_log_file
  trap 'fatal_error_handler $?' ERR
  trap cleanup_on_exit EXIT
  if [[ "$USE_SAVED_SELECTIONS" -eq 1 ]]; then
    load_saved_selections
  fi
  normalize_distro
  TARGET_HOME="$(resolve_target_home "$TARGET_USER")" || die "Could not resolve home directory for target user '$TARGET_USER'"
  load_adapter
}

step_should_run_always() {
  return 0
}

step_should_run_dotfiles() {
  [[ "$SKIP_DOTFILES" -ne 1 ]]
}

step_should_run_doctor() {
  [[ "$COMMAND" == "doctor" || "$COMMAND" == "apply" || "$DRY_RUN" -ne 1 ]]
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

build_step_registry() {
  local include_planning="${1:-0}"
  reset_step_registry
  register_step preflight "Preflight" "Validate the environment, target user, and install prerequisites." module_00_preflight step_should_run_always fatal
  if [[ "$include_planning" -eq 1 ]]; then
    register_step planning "Planning" "Build and review the final install plan from defaults and selected bundles." module_20_plan step_should_run_always fatal
  fi
  register_step bootstrap-tools "Bootstrap Tools" "Install the package-manager helpers needed for the selected distro." module_05_bootstrap_tools step_should_run_always fatal
  register_step sources "Software Sources" "Enable repositories and remotes required by the current plan." module_10_sources step_should_run_always fatal
  register_step base-setup "Base Setup" "Install non-optional base packages and configure the base shell before optional selections." module_30_packages step_should_run_always fatal
  register_step optional-packages "Optional Packages" "Install optional Fedora and Flatpak packages from the generated plan." module_32_optional_packages step_should_run_always continue
  register_step custom-actions "Custom Actions" "Run selected direct installers and package-manager actions." module_35_custom_actions step_should_run_always continue
  register_step dotfiles "Dotfiles" "Stow managed configuration into the target home directory." module_60_dotfiles step_should_run_dotfiles fatal
  register_step post-actions "Post Actions" "Apply defaults, desktop associations, and final user/system tweaks." module_80_post_actions step_should_run_always continue
  register_step doctor "Doctor" "Run the final verification checks and environment summary." module_90_doctor step_should_run_doctor fatal
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

  printf 'Root privileges are required for setup. You may be prompted for your password once.\n'
  sudo -v
  exec sudo env "${root_env[@]}" "$ROOT_DIR/install.sh" "$@"
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
      write_install_progress done "$current" "$total" "$label" "Completed in ${elapsed}s"
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
  write_install_progress running 0 "$total" "ZZ Linux Setup" "Starting installation"

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
    write_install_progress done "$total" "$total" "ZZ Linux Setup" "Installation complete"
  else
    write_install_progress failed "$total" "$total" "ZZ Linux Setup" "Installation failed"
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
      [[ -f "$PLAN_DIR/bundles.list" ]] || build_plan_from_selections
      module_80_first_run
      ;;
    defaults)
      [[ -f "$PLAN_DIR/bundles.list" ]] || build_plan_from_selections
      module_80_defaults
      ;;
    list-profiles)
      printf 'base\n'
      printf 'desktop-app:auto\n'
      printf 'desktop-app:full\n'
      printf 'desktop-app:minimal\n'
      ;;
    list-choices)
      local category file
      for file in $(list_choice_catalogs "$DISTRO"); do
        category="$(basename "$file" .conf)"
        printf '[%s]\n' "$category"
        awk -F'\t' 'NF==5 && $1 !~ /^#/ {printf "%s\t%s\tdefault=%s\n", $1, $2, $3}' "$file"
        printf '\n'
      done
      ;;
    list-sources)
      list_sources_pretty "$DISTRO"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
