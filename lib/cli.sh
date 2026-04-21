#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./install.sh [wizard|install|doctor|print-plan|list-profiles|list-choices|list-sources] [options]

Common options:
  --yes
  --dry-run
  --use-saved
  --skip-dotfiles
  --skip-services
  --skip-login-manager
  --target-user USER
  --distro auto|fedora|arch
  --select category=a,b,c
  --enable-source SOURCE_ID
  --no-tui
  --stow-adopt
EOF
}

parse_cli() {
  local args=("$@")
  local idx=0
  if [[ "${#args[@]}" -gt 0 && "${args[0]}" != --* ]]; then
    COMMAND="${args[0]}"
    idx=1
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
      --skip-services)
        SKIP_SERVICES=1
        ;;
      --skip-login-manager)
        SKIP_LOGIN_MANAGER=1
        ;;
      --no-tui)
        NO_TUI=1
        ;;
      --stow-adopt)
        STOW_ADOPT=1
        ;;
      --target-user)
        idx=$((idx + 1))
        TARGET_USER="${args[$idx]:-}"
        ;;
      --distro)
        idx=$((idx + 1))
        DISTRO="${args[$idx]:-}"
        ;;
      --select)
        idx=$((idx + 1))
        parse_select_arg "${args[$idx]:-}"
        ;;
      --enable-source)
        idx=$((idx + 1))
        append_unique EXPLICIT_ENABLED_SOURCES "${args[$idx]:-}"
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
