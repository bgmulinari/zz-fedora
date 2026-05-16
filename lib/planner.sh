#!/usr/bin/env bash
set -Eeuo pipefail

plan_reset() {
  rm -rf "$PLAN_DIR"
  mkdir -p \
    "$PLAN_DIR/actions" \
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

append_dotfiles_prereqs() {
  local stow_plan_file="$PLAN_DIR/stow/packages.list"
  [[ -f "$stow_plan_file" ]] || return 0
  [[ "$(count_plan_entries "$stow_plan_file")" -gt 0 ]] || return 0
  append_plan_entries "$(prereq_file_for_backend "$(native_backend_for_distro "$DISTRO")")" "stow"
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
  local default_var="DEFAULT_BUNDLE_IDS_${DISTRO}"
  local -n default_bundle_ids_ref="$default_var"
  local bundle_id

  for bundle_id in "${base_bundle_ids_ref[@]}"; do
    append_unique selected_bundle_ids "$bundle_id"
  done

  for bundle_id in "${default_bundle_ids_ref[@]}"; do
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

  if array_contains "dotnet-tools" "${selected_bundle_ids[@]:-}"; then
    append_unique selected_bundle_ids "dotnet-sdk"
  fi

  for bundle_id in "${selected_bundle_ids[@]:-}"; do
    append_bundle_to_plan "$bundle_id" plan_sources plan_backends
  done

  for bundle_id in "${plan_backends[@]:-}"; do
    append_backend_prereqs "$bundle_id"
  done
  append_dotfiles_prereqs

  if array_contains "flatpak" "${plan_backends[@]:-}"; then
    append_plan_entries \
      "$PLAN_DIR/flatpak/apps.flatpaks" \
      "org.gtk.Gtk3theme.adw-gtk3" \
      "org.gtk.Gtk3theme.adw-gtk3-dark"
  fi

  local source_id
  for source_id in "${plan_sources[@]:-}"; do
    [[ -n "$source_id" ]] || continue
    append_plan_source "$source_id"
  done

  append_plan_entries "$PLAN_DIR/services/system-enable-now.list" "${DEFAULT_SYSTEM_SERVICES[@]}"
  : >"$PLAN_DIR/services/user-enable.list"
  append_managed_file "~/Wallpapers/SilentPeaks.jpg"
  append_managed_file "~/.cache/noctalia/wallpapers.json"
  if declare -F stow_write_conflict_preview >/dev/null 2>&1; then
    stow_write_conflict_preview
  fi

  write_plan_summary
  [[ "$COMMAND" == "check" ]] || save_selections
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

    printf '\nActions:\n'
    if [[ -f "$PLAN_DIR/actions/actions.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/actions/actions.list"
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

    printf '\nConfig conflicts:\n'
    if [[ -f "$PLAN_DIR/files/config-conflicts.tsv" ]]; then
      awk -F'\t' 'NF>=3 {printf "  - %s (%s: %s)\n", $1, $2, $3}' "$PLAN_DIR/files/config-conflicts.tsv"
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
  case "$PLAN_FORMAT" in
    text) cat "$PLAN_DIR/summary.txt" ;;
    json) print_plan_json ;;
    *) die "Unsupported plan format: $PLAN_FORMAT" ;;
  esac
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

json_array_from_file() {
  local file="$1"
  local first=1
  local entry
  printf '['
  if [[ -f "$file" ]]; then
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      [[ "$first" -eq 1 ]] || printf ','
      printf '"%s"' "$(json_escape "$entry")"
      first=0
    done < <(read_plan_file "$file")
  fi
  printf ']'
}

json_array_from_files() {
  local first=1
  local file entry
  printf '['
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      [[ "$first" -eq 1 ]] || printf ','
      printf '"%s"' "$(json_escape "$entry")"
      first=0
    done < <(read_plan_file "$file")
  done
  printf ']'
}

json_warnings_array() {
  local first=1
  local warning
  printf '['
  for warning in "${WARNING_MESSAGES[@]:-}"; do
    [[ "$first" -eq 1 ]] || printf ','
    printf '"%s"' "$(json_escape "$warning")"
    first=0
  done
  printf ']'
}

json_conflicts_array() {
  local file="$PLAN_DIR/files/config-conflicts.tsv"
  local first=1
  local path package action
  printf '['
  if [[ -f "$file" ]]; then
    while IFS=$'\t' read -r path package action; do
      [[ -n "$path" ]] || continue
      [[ "$first" -eq 1 ]] || printf ','
      printf '{"path":"%s","package":"%s","action":"%s"}' \
        "$(json_escape "$path")" \
        "$(json_escape "$package")" \
        "$(json_escape "$action")"
      first=0
    done <"$file"
  fi
  printf ']'
}

print_plan_json() {
  local native_backend
  native_backend="$(native_backend_for_distro "$DISTRO")"
  printf '{'
  printf '"distro":"%s",' "$(json_escape "$DISTRO")"
  printf '"target_user":"%s",' "$(json_escape "$TARGET_USER")"
  printf '"selected_bundles":'
  json_array_from_file "$PLAN_DIR/bundles.list"
  printf ',"sources":'
  json_array_from_files "$PLAN_DIR"/sources/*.list
  printf ',"native_backend":"%s",' "$(json_escape "$native_backend")"
  printf '"native_packages":'
  json_array_from_file "$(package_file_for_backend "$native_backend")"
  printf ',"flatpaks":'
  json_array_from_file "$PLAN_DIR/flatpak/apps.flatpaks"
  printf ',"custom_actions":'
  json_array_from_file "$PLAN_DIR/actions/actions.list"
  printf ',"services":{"system_enable_now":'
  json_array_from_file "$PLAN_DIR/services/system-enable-now.list"
  printf ',"system_enable":'
  json_array_from_file "$PLAN_DIR/services/system-enable.list"
  printf ',"user_enable":'
  json_array_from_file "$PLAN_DIR/services/user-enable.list"
  printf '},"stow_packages":'
  json_array_from_file "$PLAN_DIR/stow/packages.list"
  printf ',"managed_files":'
  json_array_from_file "$PLAN_DIR/files/managed-files.list"
  printf ',"config_conflicts":'
  json_conflicts_array
  printf ',"warnings":'
  json_warnings_array
  printf '}\n'
}
