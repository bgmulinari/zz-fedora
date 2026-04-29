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

for module_file in "$ROOT_DIR"/modules/*.sh; do
  # shellcheck disable=SC1090
  source "$module_file"
done

prepare_context() {
  parse_cli "$@"
  exec_setup_as_root_if_needed "$@"
  init_log_file
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

exec_setup_as_root_if_needed() {
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  [[ "$EUID" -eq 0 ]] && return 0
  [[ "$COMMAND" == "wizard" || "$COMMAND" == "install" ]] || return 0

  printf 'Root privileges are required for setup. You may be prompted for your password once.\n'
  sudo -v
  exec sudo env \
    "STATE_DIR=$STATE_DIR" \
    "CACHE_DIR=$CACHE_DIR" \
    "CONFIG_DIR=$CONFIG_DIR" \
    "STATE_OWNER_USER=${STATE_OWNER_USER:-${USER:-}}" \
    "TARGET_USER=$TARGET_USER" \
    "TARGET_HOME=$TARGET_HOME" \
    "DISPLAY=${DISPLAY:-}" \
    "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}" \
    "XAUTHORITY=${XAUTHORITY:-}" \
    "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}" \
    "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-}" \
    "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}" \
    "DESKTOP_SESSION=${DESKTOP_SESSION:-}" \
    "TERM=${TERM:-}" \
    "COLORTERM=${COLORTERM:-}" \
    "$ROOT_DIR/install.sh" "$@"
}

run_install_step() {
  local current="$1"
  local total="$2"
  local label="$3"
  local description="$4"
  local function_name="$5"
  local predicate="${6:-step_should_run_always}"

  tui_step_start "$current" "$total" "$label" "$description"
  if ! "$predicate"; then
    log_info "Skipped step: $label"
    tui_step_skipped "$label"
    return 0
  fi

  log_info "Running step $current/$total: $label"
  if "$function_name"; then
    log_info "Completed step $current/$total: $label"
    tui_step_done "$label"
    return 0
  fi

  log_error "Failed step $current/$total: $label"
  tui_step_failed "$label"
  return 1
}

run_install_modules() {
  local -a functions=(
    module_00_preflight
    module_20_plan
    module_05_bootstrap_tools
    module_10_sources
    module_30_packages
    module_32_optional_packages
    module_35_custom_actions
    module_60_dotfiles
    module_80_post_actions
    module_90_doctor
  )
  local -a labels=(
    "Preflight"
    "Planning"
    "Bootstrap Tools"
    "Software Sources"
    "Base Setup"
    "Optional Packages"
    "Custom Actions"
    "Dotfiles"
    "Post Actions"
    "Doctor"
  )
  local -a descriptions=(
    "Validate the environment, target user, and install prerequisites."
    "Build the final install plan from defaults and selected bundles."
    "Install the package-manager helpers needed for the selected distro."
    "Enable repositories and remotes required by the current plan."
    "Install non-optional base packages and configure the base shell before optional selections."
    "Install optional distro, AUR, and Flatpak packages from the generated plan."
    "Run selected direct installers and package-manager actions."
    "Stow managed configuration into the target home directory."
    "Apply defaults, desktop associations, and final user/system tweaks."
    "Run the final verification checks and environment summary."
  )
  local -a predicates=(
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_dotfiles
    step_should_run_always
    step_should_run_doctor
  )
  local total="${#functions[@]}"
  local idx

  tui_register_steps "${labels[@]}"

  for idx in "${!functions[@]}"; do
    run_install_step \
      "$((idx + 1))" \
      "$total" \
      "${labels[$idx]}" \
      "${descriptions[$idx]}" \
      "${functions[$idx]}" \
      "${predicates[$idx]}"
  done
}

run_apply_modules() {
  local -a functions=(
    module_00_preflight
    module_05_bootstrap_tools
    module_10_sources
    module_30_packages
    module_32_optional_packages
    module_35_custom_actions
    module_60_dotfiles
    module_80_post_actions
    module_90_doctor
  )
  local -a labels=(
    "Preflight"
    "Bootstrap Tools"
    "Software Sources"
    "Base Setup"
    "Optional Packages"
    "Custom Actions"
    "Dotfiles"
    "Post Actions"
    "Doctor"
  )
  local -a descriptions=(
    "Validate the environment, target user, and install prerequisites."
    "Install the package-manager helpers needed for the selected distro."
    "Enable repositories and remotes required by the current plan."
    "Install non-optional base packages and configure the base shell before optional selections."
    "Install optional distro, AUR, and Flatpak packages from the generated plan."
    "Run selected direct installers and package-manager actions."
    "Stow managed configuration into the target home directory."
    "Apply defaults, desktop associations, and final user/system tweaks."
    "Run the final verification checks and environment summary."
  )
  local -a predicates=(
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_dotfiles
    step_should_run_always
    step_should_run_doctor
  )
  local total="${#functions[@]}"
  local idx

  tui_register_steps "${labels[@]}"

  for idx in "${!functions[@]}"; do
    run_install_step \
      "$((idx + 1))" \
      "$total" \
      "${labels[$idx]}" \
      "${descriptions[$idx]}" \
      "${functions[$idx]}" \
      "${predicates[$idx]}"
  done
}

apply_install_plan() {
  run_apply_modules
  tui_summary
  prompt_for_reboot
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
      [[ "${ZZ_INTERNAL_APPLY:-0}" -eq 1 ]] || die "apply is internal; run install or wizard so the plan is generated first"
      apply_install_plan
      ;;
    print-plan)
      build_plan_from_selections
      print_plan_summary
      ;;
    doctor)
      module_00_preflight
      module_90_doctor
      ;;
    list-profiles)
      printf 'base\n'
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
