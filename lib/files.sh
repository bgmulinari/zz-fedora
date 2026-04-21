#!/usr/bin/env bash
set -Eeuo pipefail

append_managed_file() {
  local path="$1"
  append_plan_entries "$PLAN_DIR/files/managed-files.list" "$path"
}

append_managed_files_for_stow_package() {
  local package_name="$1"
  local package_dir="$ROOT_DIR/dotfiles/$package_name"
  [[ -d "$package_dir" ]] || return 0

  local relative_path
  while IFS= read -r relative_path; do
    [[ -n "$relative_path" ]] || continue
    append_managed_file "~/$relative_path"
  done < <(find "$package_dir" -type f ! -name '.keep' -printf '%P\n' | sort)
}
