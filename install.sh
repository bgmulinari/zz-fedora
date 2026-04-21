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
  if [[ "$USE_SAVED_SELECTIONS" -eq 1 ]]; then
    load_saved_selections
  fi
  normalize_distro
  TARGET_HOME="$(resolve_target_home "$TARGET_USER")" || die "Could not resolve home directory for target user '$TARGET_USER'"
  load_adapter
}

run_install_modules() {
  module_00_preflight
  module_05_bootstrap_tools
  module_10_sources
  module_20_plan
  module_30_packages
  module_40_services
  module_50_greetd
  module_55_zsh
  module_60_dotfiles
  module_70_user_services
  module_80_post_actions
  module_90_doctor
}

main() {
  prepare_context "$@"

  case "$COMMAND" in
    wizard)
      tui_run_wizard
      build_plan_from_selections
      run_install_modules
      ;;
    install)
      build_plan_from_selections
      run_install_modules
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
        awk -F'\t' 'NF==6 && $1 !~ /^#/ {printf "%s\t%s\tdefault=%s\n", $1, $2, $3}' "$file"
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
