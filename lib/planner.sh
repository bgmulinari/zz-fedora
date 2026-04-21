#!/usr/bin/env bash
set -Eeuo pipefail

plan_reset() {
  rm -rf "$PLAN_DIR"
  mkdir -p \
    "$PLAN_DIR/sources" \
    "$PLAN_DIR/packages" \
    "$PLAN_DIR/flatpak" \
    "$PLAN_DIR/services" \
    "$PLAN_DIR/files" \
    "$PLAN_DIR/stow"
  : >"$PLAN_DIR/summary.txt"
}

append_warning() {
  append_unique WARNING_MESSAGES "$1"
}

append_info() {
  append_unique INFO_MESSAGES "$1"
}

add_source_to_plan() {
  local source_id="$1"
  append_unique ENABLED_SOURCES "$source_id"
}

add_manifest_to_plan() {
  local manifest_path="$1"
  local kind
  kind="$(manifest_kind_from_path "$manifest_path")"
  local destination
  destination="$(package_file_for_kind "$kind")"
  mapfile -t manifest_items < <(manifest_entries "$ROOT_DIR/$manifest_path")
  append_plan_entries "$destination" "${manifest_items[@]:-}"
}

manifest_required_sources() {
  case "$1" in
    packages/fedora/copr/yalter-niri/*) printf 'copr:yalter/niri\n' ;;
    packages/fedora/copr/scottames-ghostty/*) printf 'copr:scottames/ghostty\n' ;;
    packages/fedora/copr/sneexy-zen-browser/*) printf 'copr:sneexy/zen-browser\n' ;;
    packages/fedora/copr/v8v88v8v88-helium/*) printf 'copr:v8v88v8v88/helium\n' ;;
    packages/fedora/copr/atim-starship/*) printf 'copr:atim/starship\n' ;;
    packages/fedora/copr/lihaohong-yazi/*) printf 'copr:lihaohong/yazi\n' ;;
    packages/fedora/terra/*) printf 'terra\n' ;;
    packages/fedora/vendor/brave/*) printf 'vendor:brave\n' ;;
    packages/fedora/vendor/google-chrome/*) printf 'vendor:google-chrome\n' ;;
    packages/fedora/rpmfusion/*)
      printf 'rpmfusion-free\n'
      printf 'rpmfusion-nonfree\n'
      ;;
    packages/*/flatpak/*) printf 'flathub\n' ;;
    packages/arch/aur/*) printf 'aur\n' ;;
  esac
}

stow_packages_for_manifest() {
  case "$1" in
    packages/fedora/official/bootstrap.pkgs|packages/arch/official/bootstrap.pkgs)
      printf 'shell\n'
      ;;
    packages/fedora/copr/yalter-niri/desktop-core.pkgs)
      printf 'environment\n'
      printf 'niri\n'
      ;;
    packages/arch/official/desktop-core.pkgs)
      printf 'environment\n'
      printf 'ghostty\n'
      printf 'niri\n'
      ;;
    packages/fedora/terra/noctalia.pkgs|packages/arch/aur/desktop-core.pkgs)
      printf 'noctalia\n'
      ;;
    packages/fedora/terra/ghostty.pkgs|packages/fedora/copr/scottames-ghostty/terminal.pkgs)
      printf 'ghostty\n'
      ;;
    packages/fedora/official/portals-kde.pkgs|packages/arch/official/portals-kde.pkgs)
      printf 'portals\n'
      ;;
    packages/fedora/official/wayland-tools.pkgs|packages/arch/official/wayland-tools.pkgs)
      printf 'fuzzel\n'
      ;;
    packages/fedora/official/kde-apps.pkgs|packages/arch/official/kde-apps.pkgs)
      printf 'kde\n'
      ;;
    packages/fedora/official/shell/zsh.pkgs|packages/arch/official/shell/zsh.pkgs)
      printf 'zsh\n'
      ;;
    packages/fedora/copr/atim-starship/starship.pkgs|packages/arch/official/shell/starship.pkgs)
      printf 'shell-starship\n'
      printf 'starship\n'
      ;;
    packages/fedora/official/shell/zoxide.pkgs|packages/arch/official/shell/zoxide.pkgs)
      printf 'shell-zoxide\n'
      ;;
    packages/fedora/official/shell/fastfetch.pkgs|packages/arch/official/shell/fastfetch.pkgs)
      printf 'shell-fastfetch\n'
      ;;
    packages/fedora/official/shell/btop.pkgs|packages/arch/official/shell/btop.pkgs)
      printf 'btop\n'
      ;;
    packages/fedora/official/shell/fzf.pkgs|packages/arch/official/shell/fzf.pkgs)
      printf 'shell-fzf\n'
      ;;
    packages/fedora/copr/lihaohong-yazi/yazi.pkgs|packages/arch/official/shell/yazi.pkgs)
      printf 'shell-yazi\n'
      ;;
  esac
}

append_manifest_stow_plan() {
  local manifest_path="$1"
  local stow_package
  while IFS= read -r stow_package; do
    [[ -n "$stow_package" ]] || continue
    append_plan_entries "$PLAN_DIR/stow/packages.list" "$stow_package"
    append_managed_files_for_stow_package "$stow_package"
  done < <(stow_packages_for_manifest "$manifest_path")
}

append_manifest_managed_files() {
  :
}

build_plan_from_selections() {
  ensure_state_dirs
  plan_reset

  local -a manifest_paths=()
  local -a plan_sources=()
  local source_id
  for source_id in "${ENABLED_SOURCES[@]:-}"; do
    append_unique plan_sources "$source_id"
  done
  for source_id in "${EXPLICIT_ENABLED_SOURCES[@]:-}"; do
    append_unique plan_sources "$source_id"
  done

  local manifest_path
  case "$DISTRO" in
    fedora)
      for manifest_path in "${BASE_PACKAGE_MANIFESTS_fedora[@]}"; do
        append_unique manifest_paths "$manifest_path"
      done
      ;;
    arch)
      for manifest_path in "${BASE_PACKAGE_MANIFESTS_arch[@]}"; do
        append_unique manifest_paths "$manifest_path"
      done
      ;;
  esac

  local category choice_id record choice_sources choice_manifests
  for category in $(category_names "$DISTRO"); do
    validate_choice_catalog "$DISTRO" "$category"
    while IFS= read -r choice_id; do
      [[ -n "$choice_id" ]] || continue
      record="$(choice_record "$DISTRO" "$category" "$choice_id")"
      [[ -n "$record" ]] || die "Unknown choice '$choice_id' in category '$category'"
      choice_sources="$(choice_field "$record" 4)"
      choice_manifests="$(choice_field "$record" 5)"
      while IFS= read -r item; do
        [[ -n "$item" ]] && append_unique plan_sources "$item"
      done < <(split_csv "$choice_sources")
      while IFS= read -r item; do
        [[ -n "$item" ]] && append_unique manifest_paths "$item"
      done < <(split_csv "$choice_manifests")

      if [[ "$category" == "media" && "$choice_id" == "codecs" ]]; then
        CODECS_SELECTED=1
      fi
    done < <(effective_choice_ids "$DISTRO" "$category")
  done

  if array_contains "ghostty-copr" $(effective_choice_ids "$DISTRO" "sources"); then
    remove_value manifest_paths "packages/fedora/terra/ghostty.pkgs"
    append_unique manifest_paths "packages/fedora/copr/scottames-ghostty/terminal.pkgs"
  fi

  for manifest_path in "${manifest_paths[@]:-}"; do
    while IFS= read -r source_id; do
      [[ -n "$source_id" ]] && append_unique plan_sources "$source_id"
    done < <(manifest_required_sources "$manifest_path")
  done

  local wants_flatpak=0
  for manifest_path in "${manifest_paths[@]:-}"; do
    if [[ "$manifest_path" == *"/flatpak/"* || "$manifest_path" == packages/*/flatpak/*.flatpaks ]]; then
      wants_flatpak=1
      break
    fi
  done
  if array_contains "flathub" "${plan_sources[@]:-}"; then
    wants_flatpak=1
  fi
  if [[ "$wants_flatpak" -eq 1 ]]; then
    append_unique plan_sources "flathub"
    append_unique manifest_paths "packages/$DISTRO/official/flatpak.pkgs"
  fi

  for manifest_path in "${manifest_paths[@]:-}"; do
    add_manifest_to_plan "$manifest_path"
    append_manifest_stow_plan "$manifest_path"
    append_manifest_managed_files "$manifest_path"
  done

  for source_id in "${plan_sources[@]:-}"; do
    [[ -n "$source_id" ]] || continue
    append_plan_source "$source_id"
  done

  append_plan_entries "$PLAN_DIR/services/system-enable-now.list" "${DEFAULT_SYSTEM_SERVICES[@]}"
  append_plan_entries "$PLAN_DIR/services/system-enable.list" "plasmalogin"
  : >"$PLAN_DIR/services/user-enable.list"

  if array_contains "libvirt" $(effective_choice_ids "$DISTRO" "virtualization"); then
    append_plan_entries "$PLAN_DIR/services/system-enable-now.list" "libvirtd"
  fi
  if array_contains "base" $(effective_choice_ids "$DISTRO" "print-scan"); then
    append_plan_entries "$PLAN_DIR/services/system-enable-now.list" "cups"
  fi

  write_plan_summary
  save_selections
}

count_plan_entries() {
  local file="$1"
  [[ -f "$file" ]] || {
    printf '0\n'
    return 0
  }
  wc -l <"$file" | tr -d ' '
}

write_plan_summary() {
  {
    printf 'Distro: %s\n' "$DISTRO"
    printf 'Target user: %s\n' "$TARGET_USER"
    printf '\nSources:\n'
    local source_list
    for source_list in "$PLAN_DIR"/sources/*.list; do
      [[ -f "$source_list" ]] || continue
      printf '  %s (%s)\n' "$(basename "$source_list")" "$(count_plan_entries "$source_list")"
      sed 's/^/    - /' "$source_list" 2>/dev/null || true
    done
    printf '\nPackages:\n'
    local package_list
    for package_list in "$PLAN_DIR"/packages/*.pkgs; do
      [[ -f "$package_list" ]] || continue
      printf '  %s (%s)\n' "$(basename "$package_list")" "$(count_plan_entries "$package_list")"
      sed 's/^/    - /' "$package_list" 2>/dev/null || true
    done
    printf '\nFlatpaks:\n'
    if [[ -f "$PLAN_DIR/flatpak/apps.flatpaks" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/flatpak/apps.flatpaks"
    fi
    printf '\nServices:\n'
    if [[ -f "$PLAN_DIR/services/system-enable-now.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/services/system-enable-now.list"
    fi
    if [[ -f "$PLAN_DIR/services/system-enable.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/services/system-enable.list"
    fi
    printf '\nFiles:\n'
    if [[ -f "$PLAN_DIR/files/managed-files.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/files/managed-files.list"
    fi
    printf '\nStow:\n'
    if [[ -f "$PLAN_DIR/stow/packages.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/stow/packages.list"
    fi
    if [[ "${#WARNING_MESSAGES[@]}" -gt 0 ]]; then
      printf '\nWarnings:\n'
      printf '  - %s\n' "${WARNING_MESSAGES[@]}"
    fi
  } >"$PLAN_DIR/summary.txt"
}

print_plan_summary() {
  [[ -f "$PLAN_DIR/summary.txt" ]] || die "No generated plan found."
  cat "$PLAN_DIR/summary.txt"
}
