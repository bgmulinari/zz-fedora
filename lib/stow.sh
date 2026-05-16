#!/usr/bin/env bash
set -Eeuo pipefail

stow_packages_from_plan() {
  read_plan_file "$PLAN_DIR/stow/packages.list"
}

stow_package_required_command() {
  case "$1" in
    btop) printf 'btop\n' ;;
    ghostty) printf 'ghostty\n' ;;
    nvim) printf 'nvim\n' ;;
    niri) printf 'niri\n' ;;
    noctalia) printf 'qs\n' ;;
    shell-fastfetch) printf 'fastfetch\n' ;;
    shell-fzf) printf 'fzf\n' ;;
    shell-starship|starship) printf 'starship\n' ;;
    shell-yazi) printf 'yazi\n' ;;
    shell-zoxide) printf 'zoxide\n' ;;
    vscode) printf 'code\n' ;;
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

stow_backup_existing_target() {
  local relative_path="$1"
  local target_path backup_path

  target_path="$TARGET_HOME/$relative_path"
  [[ -e "$target_path" || -L "$target_path" ]] || return 0
  [[ -L "$target_path" ]] && return 0

  backup_path="$STATE_DIR/backups/$(timestamp)$target_path"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: move %s -> %s\n' "$target_path" "$backup_path"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$backup_path")"
  run_cmd_as_user "$TARGET_USER" mv "$target_path" "$backup_path" || return 1
  log_info "Moved existing $target_path to $backup_path before stowing managed config"
}

stow_path_has_managed_descendant() {
  local package_dir="$1"
  local relative_path="$2"
  local child
  while IFS= read -r child; do
    [[ -n "$child" ]] || continue
    [[ "$child" == "$relative_path"/* ]] && return 0
  done < <(find "$package_dir" -mindepth 1 -printf '%P\n')
  return 1
}

stow_prepare_known_shell_files() {
  local file_name
  for file_name in .bashrc .bash_profile .profile; do
    stow_backup_existing_target "$file_name"
  done
}

stow_prepare_known_conflicts() {
  local package_name
  for package_name in "$@"; do
    case "$package_name" in
      noctalia)
        stow_backup_existing_target ".config/noctalia/plugins.json"
        stow_backup_existing_target ".config/noctalia/user-templates.toml"
        stow_backup_existing_target ".config/noctalia/templates/neovim.lua"
        stow_backup_existing_target ".config/noctalia/templates/zsh-syntax-highlighting.zsh"
        ;;
      shell)
        stow_prepare_known_shell_files
        ;;
    esac
  done
}

stow_prepare_package_conflicts() {
  local package_name="$1"
  local package_dir="$ROOT_DIR/dotfiles/$package_name"
  [[ -d "$package_dir" ]] || return 0

  local relative_path
  while IFS= read -r relative_path; do
    [[ -n "$relative_path" ]] || continue
    if [[ -d "$package_dir/$relative_path" ]] && stow_path_has_managed_descendant "$package_dir" "$relative_path"; then
      continue
    fi
    stow_backup_existing_target "$relative_path"
  done < <(find "$package_dir" -mindepth 1 -printf '%P\n' | sort -u)
}

stow_prepare_conflicts() {
  local package_name
  for package_name in "$@"; do
    stow_prepare_package_conflicts "$package_name"
  done
  stow_prepare_known_conflicts "$@"
}

stow_preview_conflict_path() {
  printf '%s/files/config-conflicts.tsv\n' "$PLAN_DIR"
}

stow_preview_record_conflict() {
  local relative_path="$1"
  local package_name="$2"
  local target_path="$TARGET_HOME/$relative_path"
  [[ -e "$target_path" || -L "$target_path" ]] || return 0
  [[ -L "$target_path" ]] && return 0
  printf '%s\t%s\tbackup-before-stow\n' "~/$relative_path" "$package_name" >>"$(stow_preview_conflict_path)"
}

stow_preview_package_conflicts() {
  local package_name="$1"
  local package_dir="$ROOT_DIR/dotfiles/$package_name"
  [[ -d "$package_dir" ]] || return 0

  local relative_path
  while IFS= read -r relative_path; do
    [[ -n "$relative_path" ]] || continue
    if [[ -d "$package_dir/$relative_path" ]] && stow_path_has_managed_descendant "$package_dir" "$relative_path"; then
      continue
    fi
    stow_preview_record_conflict "$relative_path" "$package_name"
  done < <(find "$package_dir" -mindepth 1 -printf '%P\n' | sort -u)
}

stow_preview_known_conflicts() {
  local package_name
  for package_name in "$@"; do
    case "$package_name" in
      noctalia)
        stow_preview_record_conflict ".config/noctalia/plugins.json" "$package_name"
        stow_preview_record_conflict ".config/noctalia/user-templates.toml" "$package_name"
        stow_preview_record_conflict ".config/noctalia/templates/neovim.lua" "$package_name"
        stow_preview_record_conflict ".config/noctalia/templates/zsh-syntax-highlighting.zsh" "$package_name"
        ;;
      shell)
        stow_preview_record_conflict ".bashrc" "$package_name"
        stow_preview_record_conflict ".bash_profile" "$package_name"
        stow_preview_record_conflict ".profile" "$package_name"
        ;;
    esac
  done
}

stow_write_conflict_preview() {
  local preview_file
  preview_file="$(stow_preview_conflict_path)"
  mkdir -p "$(dirname "$preview_file")"
  : >"$preview_file"

  [[ -n "${TARGET_HOME:-}" && -d "$TARGET_HOME" ]] || return 0

  local -a packages=()
  local package_name
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    stow_package_has_payload "$package_name" || continue
    packages+=("$package_name")
  done < <(stow_packages_from_plan)
  [[ "${#packages[@]}" -gt 0 ]] || return 0

  for package_name in "${packages[@]}"; do
    stow_preview_package_conflicts "$package_name"
  done
  stow_preview_known_conflicts "${packages[@]}"
  sort -u "$preview_file" -o "$preview_file"
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
    --no-folding
    --simulate
    --verbose=2
  )
  local -a apply_cmd=(
    stow
    --dir "$ROOT_DIR/dotfiles"
    --target "$TARGET_HOME"
    --no-folding
    --restow
  )
  if [[ "$STOW_ADOPT" -eq 1 ]]; then
    apply_cmd+=(--adopt)
  fi
  simulate_cmd+=("${packages[@]}")
  apply_cmd+=("${packages[@]}")

  stow_prepare_conflicts "${packages[@]}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd_as_user "$TARGET_USER" "${simulate_cmd[@]}"
    run_cmd_as_user "$TARGET_USER" "${apply_cmd[@]}"
    return 0
  fi

  local output_file
  output_file="$(mktemp "$CACHE_DIR/stow-simulate.XXXXXX")"
  if ! run_cmd_as_user "$TARGET_USER" "${simulate_cmd[@]}" >"$output_file" 2>&1; then
    cat "$output_file" >&2
    rm -f "$output_file"
    die "Stow reported conflicts. Re-run with --stow-adopt only if you intentionally want to adopt existing files."
  fi
  rm -f "$output_file"
  run_cmd_as_user "$TARGET_USER" "${apply_cmd[@]}"
}
