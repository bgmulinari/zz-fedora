#!/usr/bin/env bash
set -Eeuo pipefail

plan_reset() {
  rm -rf "$PLAN_DIR"
  mkdir -p \
    "$PLAN_DIR/sources" \
    "$PLAN_DIR/packages" \
    "$PLAN_DIR/prereqs" \
    "$PLAN_DIR/flatpak" \
    "$PLAN_DIR/services" \
    "$PLAN_DIR/files" \
    "$PLAN_DIR/stow"
  : >"$PLAN_DIR/bundles.list"
  : >"$PLAN_DIR/summary.txt"
}

append_warning() {
  append_unique WARNING_MESSAGES "$1"
}

append_info() {
  append_unique INFO_MESSAGES "$1"
}

append_bundle_payload_to_plan() {
  local destination
  destination="$(package_file_for_backend "$BUNDLE_INSTALLER")"
  mapfile -t bundle_items < <(manifest_entries "$ROOT_DIR/$BUNDLE_ITEMS_FILE")
  append_plan_entries "$destination" "${bundle_items[@]:-}"
}

append_bundle_stow_plan() {
  local stow_package
  while IFS= read -r stow_package; do
    [[ -n "$stow_package" ]] || continue
    append_plan_entries "$PLAN_DIR/stow/packages.list" "$stow_package"
    append_managed_files_for_stow_package "$stow_package"
  done < <(split_csv "${BUNDLE_STOW_PACKAGES:-}")
}

append_bundle_to_plan() {
  local bundle_id="$1"
  local plan_sources_name="$2"
  local plan_backends_name="$3"
  local -n plan_sources_ref="$plan_sources_name"
  local -n plan_backends_ref="$plan_backends_name"

  load_bundle_descriptor "$DISTRO" "$bundle_id" || die "Unknown bundle: $bundle_id"
  append_plan_entries "$PLAN_DIR/bundles.list" "$bundle_id"
  append_unique plan_backends_ref "$BUNDLE_INSTALLER"
  if [[ -n "${BUNDLE_SOURCE_ID:-}" ]]; then
    append_unique plan_sources_ref "$BUNDLE_SOURCE_ID"
  fi
  append_bundle_payload_to_plan
  append_bundle_stow_plan
}

append_backend_prereqs() {
  local backend="$1"
  local prereq_backend=""

  prereq_backend="$(backend_prerequisite_backend "$backend" || true)"
  [[ -n "$prereq_backend" ]] || return 0

  mapfile -t prereq_items < <(backend_prerequisite_items "$backend")
  [[ "${#prereq_items[@]}" -gt 0 ]] || return 0
  append_plan_entries "$(prereq_file_for_backend "$prereq_backend")" "${prereq_items[@]}"
}

build_plan_from_selections() {
  ensure_state_dirs
  plan_reset
  validate_bundle_catalog "$DISTRO"

  local -a selected_bundle_ids=()
  local -a plan_sources=()
  local -a plan_backends=()
  local base_var="BASE_BUNDLE_IDS_${DISTRO}"
  local -n base_bundle_ids_ref="$base_var"
  local bundle_id

  for bundle_id in "${base_bundle_ids_ref[@]}"; do
    append_unique selected_bundle_ids "$bundle_id"
  done

  local category choice_id record choice_bundles
  for category in $(category_names "$DISTRO"); do
    validate_choice_catalog "$DISTRO" "$category"
    while IFS= read -r choice_id; do
      [[ -n "$choice_id" ]] || continue
      record="$(choice_record "$DISTRO" "$category" "$choice_id")"
      [[ -n "$record" ]] || die "Unknown choice '$choice_id' in category '$category'"
      choice_bundles="$(choice_field "$record" 4)"
      while IFS= read -r bundle_id; do
        [[ -n "$bundle_id" ]] && append_unique selected_bundle_ids "$bundle_id"
      done < <(split_csv "$choice_bundles")
    done < <(effective_choice_ids "$DISTRO" "$category")
  done

  for bundle_id in "${selected_bundle_ids[@]:-}"; do
    append_bundle_to_plan "$bundle_id" plan_sources plan_backends
  done

  for bundle_id in "${plan_backends[@]:-}"; do
    append_backend_prereqs "$bundle_id"
  done

  local source_id
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

    printf '\nBundles:\n'
    if [[ -f "$PLAN_DIR/bundles.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/bundles.list"
    fi

    printf '\nPrerequisites:\n'
    local prereq_list
    for prereq_list in "$PLAN_DIR"/prereqs/*; do
      [[ -f "$prereq_list" ]] || continue
      printf '  %s (%s)\n' "$(basename "$prereq_list")" "$(count_plan_entries "$prereq_list")"
      sed 's/^/    - /' "$prereq_list" 2>/dev/null || true
    done

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
