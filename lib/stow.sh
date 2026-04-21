#!/usr/bin/env bash
set -Eeuo pipefail

stow_packages_from_plan() {
  read_plan_file "$PLAN_DIR/stow/packages.list"
}

stow_package_required_command() {
  case "$1" in
    btop) printf 'btop\n' ;;
    fuzzel) printf 'fuzzel\n' ;;
    ghostty) printf 'ghostty\n' ;;
    kde) printf 'kwrite\n' ;;
    niri) printf 'niri\n' ;;
    portals) printf 'xdg-desktop-portal\n' ;;
    shell-fastfetch) printf 'fastfetch\n' ;;
    shell-fzf) printf 'fzf\n' ;;
    shell-starship|starship) printf 'starship\n' ;;
    shell-yazi) printf 'yazi\n' ;;
    shell-zoxide) printf 'zoxide\n' ;;
    zsh) printf 'zsh\n' ;;
  esac
}

stow_package_has_payload() {
  local package_name="$1"
  local package_dir="$ROOT_DIR/dotfiles/$package_name"
  [[ -d "$package_dir" ]] || return 1
  find "$package_dir" -type f ! -name '.keep' -print -quit | grep -q .
}

stow_package_is_applicable() {
  local package_name="$1"
  stow_package_has_payload "$package_name" || return 1

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  local required_command
  required_command="$(stow_package_required_command "$package_name" || true)"
  [[ -n "$required_command" ]] || return 0
  command -v "$required_command" >/dev/null 2>&1
}

stow_apply_plan() {
  [[ "$SKIP_DOTFILES" -eq 1 ]] && return 0
  local -a packages=()
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    if stow_package_is_applicable "$package_name"; then
      packages+=("$package_name")
      continue
    fi
    log_info "Skipping stow package '$package_name' because its payload or required command is unavailable"
  done < <(stow_packages_from_plan)
  [[ "${#packages[@]}" -gt 0 ]] || return 0

  local -a simulate_cmd=(
    stow
    --dir "$ROOT_DIR/dotfiles"
    --target "$TARGET_HOME"
    --simulate
    --verbose=2
  )
  local -a apply_cmd=(
    stow
    --dir "$ROOT_DIR/dotfiles"
    --target "$TARGET_HOME"
    --restow
  )
  if [[ "$STOW_ADOPT" -eq 1 ]]; then
    apply_cmd+=(--adopt)
  fi
  simulate_cmd+=("${packages[@]}")
  apply_cmd+=("${packages[@]}")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd_as_user "$TARGET_USER" "${simulate_cmd[@]}"
    run_cmd_as_user "$TARGET_USER" "${apply_cmd[@]}"
    return 0
  fi

  local output_file
  output_file="$(mktemp "$CACHE_DIR/stow-simulate.XXXXXX")"
  if ! sudo -u "$TARGET_USER" "${simulate_cmd[@]}" >"$output_file" 2>&1; then
    cat "$output_file" >&2
    rm -f "$output_file"
    die "Stow reported conflicts. Re-run with --stow-adopt only if you intentionally want to adopt existing files."
  fi
  rm -f "$output_file"
  run_cmd_as_user "$TARGET_USER" "${apply_cmd[@]}"
}
