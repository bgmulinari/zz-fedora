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
  init_log_file
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

step_should_run_services() {
  [[ "$SKIP_SERVICES" -ne 1 ]]
}

step_should_run_login_manager() {
  [[ "$SKIP_LOGIN_MANAGER" -ne 1 ]]
}

step_should_run_dotfiles() {
  [[ "$SKIP_DOTFILES" -ne 1 ]]
}

step_should_run_doctor() {
  [[ "$COMMAND" == "doctor" || "$DRY_RUN" -ne 1 ]]
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
    module_40_services
    module_50_login_manager
    module_55_zsh
    module_60_dotfiles
    module_70_user_services
    module_80_post_actions
    module_90_doctor
  )
  local -a labels=(
    "Preflight"
    "Planning"
    "Bootstrap Tools"
    "Software Sources"
    "Packages"
    "System Services"
    "Login Manager"
    "Shell Setup"
    "Dotfiles"
    "User Services"
    "Post Actions"
    "Doctor"
  )
  local -a descriptions=(
    "Validate the environment, target user, and install prerequisites."
    "Build the final install plan from defaults and selected bundles."
    "Install the package-manager helpers needed for the selected distro."
    "Enable repositories and remotes required by the current plan."
    "Install distro, AUR, and Flatpak packages from the generated plan."
    "Enable or start selected system services."
    "Configure the graphical login target and display manager."
    "Install shell tooling and switch the target user to the configured shell."
    "Stow managed configuration into the target home directory."
    "Reload and enable user-scoped services."
    "Apply defaults, desktop associations, and final user/system tweaks."
    "Run the final verification checks and environment summary."
  )
  local -a predicates=(
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_always
    step_should_run_services
    step_should_run_login_manager
    step_should_run_always
    step_should_run_dotfiles
    step_should_run_always
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

prompt_for_reboot() {
  [[ "$COMMAND" == "install" || "$COMMAND" == "wizard" ]] || return 0
  [[ "$DRY_RUN" -eq 0 ]] || return 0

  if [[ "$ASSUME_YES" -eq 1 || ! is_tty ]]; then
    log_info "Reboot recommended to ensure all system changes take effect."
    return 0
  fi

  printf '\n'
  if tui_confirm "Reboot now?"; then
    if [[ "$EUID" -eq 0 ]]; then
      reboot
    else
      sudo reboot
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
      run_install_modules
      tui_summary
      prompt_for_reboot
      ;;
    install)
      build_plan_from_selections
      run_install_modules
      tui_summary
      prompt_for_reboot
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
