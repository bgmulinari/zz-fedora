#!/usr/bin/env bash
set -Eeuo pipefail

# Command catalog: the single source of truth for the usage text and for
# command validation in parse_cli. Tab-separated fields: name, visible flag,
# summary. `apply` stays hidden on purpose: it is internal and guarded in
# prepare_context.
declare -ag CLI_COMMAND_TABLE=(
  $'wizard\t1\tRun the interactive selection wizard, then install'
  $'install\t1\tInstall using defaults, saved selections, or --select overrides'
  $'check\t1\tBuild the plan and report readiness without installing'
  $'doctor\t1\tVerify the installed system and summarize the environment'
  $'first-run\t1\tRun first-login session tasks for the target user'
  $'defaults\t1\tApply desktop defaults and file associations'
  $'print-plan\t1\tPrint the generated install plan'
  $'list-profiles\t1\tList the available install profiles'
  $'list-choices\t1\tList optional choice catalogs and their defaults'
  $'list-sources\t1\tList the software sources the installer can enable'
  $'apply\t0\tInternal: apply a previously generated plan'
)

# Install profiles reported by list-profiles.
declare -ag INSTALL_PROFILES=(
  base
  desktop-app:auto
  desktop-app:full
  desktop-app:minimal
)

list_install_profiles() {
  printf '%s\n' "${INSTALL_PROFILES[@]}"
}

cli_known_command() {
  local candidate="$1"
  local row name _
  for row in "${CLI_COMMAND_TABLE[@]}"; do
    IFS=$'\t' read -r name _ <<<"$row"
    [[ "$name" == "$candidate" ]] && return 0
  done
  return 1
}

usage() {
  local row name visible summary synopsis=""
  for row in "${CLI_COMMAND_TABLE[@]}"; do
    IFS=$'\t' read -r name visible summary <<<"$row"
    [[ "$visible" -eq 1 ]] || continue
    synopsis+="${synopsis:+|}$name"
  done

  printf 'Usage:\n'
  printf '  ./install.sh [%s] [options]\n\n' "$synopsis"
  printf 'Commands:\n'
  for row in "${CLI_COMMAND_TABLE[@]}"; do
    IFS=$'\t' read -r name visible summary <<<"$row"
    [[ "$visible" -eq 1 ]] || continue
    printf '  %-15s %s\n' "$name" "$summary"
  done

  cat <<'EOF'

Common options:
  --yes
  --dry-run
  --use-saved
  --skip-dotfiles
  --target-user USER
  --desktop-app-profile auto|full|minimal
  --select category=a,b,c
  --no-tui
  --stow-adopt
  --preview-commands
  --format text|json
EOF
}

# shellcheck disable=SC2034  # CLI globals are consumed by install.sh and the sourced lib/ modules.
parse_cli() {
  local args=("$@")
  local idx=0
  if [[ "${#args[@]}" -gt 0 && "${args[0]}" != --* ]]; then
    COMMAND="${args[0]}"
    idx=1
    if ! cli_known_command "$COMMAND"; then
      printf "Unknown command: '%s'\n\n" "$COMMAND" >&2
      usage >&2
      exit 1
    fi
  else
    COMMAND="$DEFAULT_COMMAND"
  fi

  while [[ $idx -lt ${#args[@]} ]]; do
    case "${args[$idx]}" in
      --yes)
        ASSUME_YES=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --use-saved)
        USE_SAVED_SELECTIONS=1
        ;;
      --skip-dotfiles)
        SKIP_DOTFILES=1
        ;;
      --no-tui)
        NO_TUI=1
        ;;
      --stow-adopt)
        STOW_ADOPT=1
        ;;
      --preview-commands)
        COMMAND_PREVIEW=1
        ;;
      --format)
        idx=$((idx + 1))
        PLAN_FORMAT="${args[$idx]:-}"
        case "$PLAN_FORMAT" in
          text|json) ;;
          *) die "Unsupported --format value: $PLAN_FORMAT" ;;
        esac
        ;;
      --target-user)
        idx=$((idx + 1))
        TARGET_USER="${args[$idx]:-}"
        ;;
      --desktop-app-profile)
        idx=$((idx + 1))
        DESKTOP_APP_PROFILE="${args[$idx]:-}"
        desktop_app_profile_value >/dev/null
        ;;
      --select)
        idx=$((idx + 1))
        parse_select_arg "${args[$idx]:-}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: ${args[$idx]}"
        ;;
    esac
    idx=$((idx + 1))
  done
}

parse_select_arg() {
  local selection="${1:-}"
  [[ "$selection" == *=* ]] || die "Invalid --select value: $selection"
  local category="${selection%%=*}"
  local values="${selection#*=}"
  [[ -n "$category" ]] || die "Invalid empty selection category"
  add_category_selection "$category" "$values"
}
