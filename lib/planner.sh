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

plan_file_has_entry() {
  local plan_file="$1"
  local entry="$2"
  [[ -f "$plan_file" ]] || return 1
  grep -Fx "$entry" "$plan_file" >/dev/null 2>&1
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
  validate_source_catalog "$DISTRO"
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
  if plan_file_has_entry "$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")" "ghostty"; then
    append_plan_entries "$PLAN_DIR/services/user-enable.list" "app-com.mitchellh.ghostty.service"
  fi
  append_managed_file "~/Wallpapers/SilentPeaks.jpg"
  append_managed_file "~/.cache/noctalia/wallpapers.json"
  append_managed_file "~/.config/noctalia/settings.json"
  append_managed_file "~/.config/niri/noctalia.kdl"
  append_managed_file "~/.config/starship.toml"
  append_managed_file "~/.config/autostart/zz-first-run.desktop"
  append_managed_file "~/.local/bin/zz"
  if [[ "${SKIP_DOTFILES:-0}" -ne 1 ]] && declare -F stow_write_conflict_preview >/dev/null 2>&1; then
    stow_write_conflict_preview
  fi

  write_base_rationale_report
  if declare -F write_managed_config_policy_plan >/dev/null 2>&1; then
    write_managed_config_policy_plan
  fi
  write_plan_summary
  write_managed_files_report
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

base_responsibility_file() {
  printf '%s/config/base-responsibility.tsv\n' "$ROOT_DIR"
}

declare -Ag BASE_RESPONSIBILITY_CACHE=()
BASE_RESPONSIBILITY_CACHE_LOADED=0

load_base_responsibility_cache() {
  [[ "$BASE_RESPONSIBILITY_CACHE_LOADED" -eq 1 ]] && return 0

  local policy_file backend item classification consumer reason
  policy_file="$(base_responsibility_file)"
  [[ -f "$policy_file" ]] || return 0
  while IFS=$'\t' read -r backend item classification consumer reason _extra || [[ -n "$backend" ]]; do
    [[ -n "$backend" ]] || continue
    [[ "$backend" == \#* ]] && continue
    [[ -n "$item" && -n "$classification" && -n "$consumer" ]] || continue
    BASE_RESPONSIBILITY_CACHE["$backend	$item"]="$classification	$consumer	$reason"
  done <"$policy_file"
  BASE_RESPONSIBILITY_CACHE_LOADED=1
}

base_responsibility_record() {
  local backend="$1"
  local item="$2"
  local policy_file
  policy_file="$(base_responsibility_file)"
  [[ -f "$policy_file" ]] || return 1
  awk -F'\t' -v backend="$backend" -v item="$item" 'NF>=5 && $1 !~ /^#/ && $1 == backend && $2 == item {print; found=1; exit} END {exit found ? 0 : 1}' "$policy_file"
}

base_responsibility_fields() {
  local backend="$1"
  local item="$2"
  local key="$backend	$item"
  load_base_responsibility_cache
  [[ -n "${BASE_RESPONSIBILITY_CACHE[$key]:-}" ]] || die "Missing base responsibility metadata for $backend item: $item"
  printf '%s\n' "${BASE_RESPONSIBILITY_CACHE[$key]}"
}

write_base_rationale_row() {
  local report="$1"
  local backend="$2"
  local item="$3"
  local owner_bundle="$4"
  local fallback_reason="$5"
  local metadata classification consumer reason
  metadata="$(base_responsibility_fields "$backend" "$item")"
  classification="$(awk -F'\t' '{print $1}' <<<"$metadata")"
  consumer="$(awk -F'\t' '{print $2}' <<<"$metadata")"
  reason="$(awk -F'\t' '{print $3}' <<<"$metadata")"
  [[ -n "$reason" ]] || reason="$fallback_reason"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$backend" "$item" "$owner_bundle" "$classification" "$consumer" "$reason" >>"$report"
}

write_base_rationale_report() {
  local report="$PLAN_DIR/base-rationale.tsv"
  local base_var="BASE_BUNDLE_IDS_${DISTRO}"
  printf 'backend\titem\towner_bundle\tclassification\tconsumer\treason\n' >"$report"
  declare -p "$base_var" >/dev/null 2>&1 || return 0
  local -n base_bundle_ids_ref="$base_var"

  local bundle_id item
  local -A seen_base_sources=()
  for bundle_id in "${base_bundle_ids_ref[@]:-}"; do
    load_bundle_descriptor "$DISTRO" "$bundle_id" || die "Unknown base bundle: $bundle_id"
    if [[ -n "${BUNDLE_SOURCE_ID:-}" && -z "${seen_base_sources[$BUNDLE_SOURCE_ID]:-}" ]]; then
      write_base_rationale_row "$report" source "$BUNDLE_SOURCE_ID" "$BUNDLE_ID" "$BUNDLE_DESCRIPTION"
      seen_base_sources["$BUNDLE_SOURCE_ID"]=1
    fi
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      write_base_rationale_row "$report" "$BUNDLE_INSTALLER" "$item" "$BUNDLE_ID" "$BUNDLE_DESCRIPTION"
    done < <(manifest_entries "$ROOT_DIR/$BUNDLE_ITEMS_FILE")
  done

  if grep -Fx 'base-source-flathub' "$PLAN_DIR/bundles.list" >/dev/null 2>&1; then
    write_base_rationale_row "$report" flatpak "org.gtk.Gtk3theme.adw-gtk3" "base-source-flathub" "GTK Flatpak theme runtime for the base desktop"
    write_base_rationale_row "$report" flatpak "org.gtk.Gtk3theme.adw-gtk3-dark" "base-source-flathub" "GTK Flatpak dark theme runtime for the base desktop"
  fi
  {
    head -n 1 "$report"
    tail -n +2 "$report" | sort -u
  } >"$report.tmp"
  mv "$report.tmp" "$report"
}

base_rationale_count() {
  local backend="$1"
  local file="$PLAN_DIR/base-rationale.tsv"
  [[ -f "$file" ]] || {
    printf '0\n'
    return 0
  }
  awk -F'\t' -v backend="$backend" 'NR>1 && $1 == backend {count++} END {print count+0}' "$file"
}

plan_source_count() {
  tui_count_plan_group "$PLAN_DIR"/sources/*.list 2>/dev/null || {
    local total=0 source_list
    for source_list in "$PLAN_DIR"/sources/*.list; do
      [[ -f "$source_list" ]] || continue
      total=$((total + $(count_plan_entries "$source_list")))
    done
    printf '%s\n' "$total"
  }
}

write_plan_summary() {
  {
    printf 'Distro: %s\n' "$DISTRO"
    printf 'Target user: %s\n' "$TARGET_USER"

    local native_backend native_total native_base flatpak_total flatpak_base action_total action_base source_total source_base
    native_backend="$(native_backend_for_distro "$DISTRO")"
    native_total="$(count_plan_entries "$(package_file_for_backend "$native_backend")")"
    native_base="$(base_rationale_count "$native_backend")"
    flatpak_total="$(count_plan_entries "$PLAN_DIR/flatpak/apps.flatpaks")"
    flatpak_base="$(base_rationale_count flatpak)"
    action_total="$(count_plan_entries "$PLAN_DIR/actions/actions.list")"
    action_base="$(base_rationale_count action)"
    source_total="$(plan_source_count)"
    source_base="$(base_rationale_count source)"

    printf '\nPlan counts:\n'
    printf '  %s packages: base=%s optional=%s total=%s\n' "${native_backend^^}" "$native_base" "$((native_total - native_base))" "$native_total"
    printf '  Flatpaks: base=%s optional=%s total=%s\n' "$flatpak_base" "$((flatpak_total - flatpak_base))" "$flatpak_total"
    printf '  Actions: base=%s optional=%s total=%s\n' "$action_base" "$((action_total - action_base))" "$action_total"
    printf '  Sources: required/base=%s optional=%s total=%s\n' "$source_base" "$((source_total - source_base))" "$source_total"

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
    local source_list source_id required_label exception_label
    for source_list in "$PLAN_DIR"/sources/*.list; do
      [[ -f "$source_list" ]] || continue
      printf '  %s (%s)\n' "$(basename "$source_list")" "$(count_plan_entries "$source_list")"
      while IFS= read -r source_id; do
        [[ -n "$source_id" ]] || continue
        load_source_descriptor "$DISTRO" "$source_id" || continue
        required_label="optional"
        [[ "${SOURCE_REQUIRED:-0}" -eq 1 ]] && required_label="required"
        exception_label=""
        [[ "${SOURCE_BOOTSTRAP_EXCEPTION:-0}" -eq 1 ]] && exception_label=", bootstrap-exception"
        printf '    - %s (%s, %s%s): %s\n' "$SOURCE_ID" "$required_label" "$SOURCE_GPG_POLICY" "$exception_label" "$SOURCE_REASON"
      done < <(read_plan_file "$source_list")
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
    if [[ -f "$PLAN_DIR/services/user-enable.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/services/user-enable.list"
    fi

    printf '\nFiles:\n'
    if [[ -f "$PLAN_DIR/files/managed-files.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/files/managed-files.list"
    fi

    printf '\nConfig conflicts:\n'
    if [[ -f "$PLAN_DIR/files/config-conflicts.tsv" ]]; then
      awk -F'\t' 'NF>=3 {printf "  - %s (%s: %s)\n", $1, $2, $3}' "$PLAN_DIR/files/config-conflicts.tsv"
    fi

    printf '\nManaged config policy:\n'
    if [[ -f "$PLAN_DIR/files/managed-config-policy.tsv" ]]; then
      awk -F'\t' 'NF>=5 {printf "  - %s (%s, %s, owner=%s) %s\n", $1, $2, $3, $4, $5}' "$PLAN_DIR/files/managed-config-policy.tsv"
    fi

    printf '\nStow:\n'
    if [[ -f "$PLAN_DIR/stow/packages.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/stow/packages.list"
    fi

    printf '\nBase rationale:\n'
    if [[ -f "$PLAN_DIR/base-rationale.tsv" ]]; then
      awk -F'\t' 'NR>1 {printf "  - %s (%s: %s, %s, consumer=%s) %s\n", $2, $1, $3, $4, $5, $6}' "$PLAN_DIR/base-rationale.tsv"
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
  for warning in "${WARNING_MESSAGES[@]}"; do
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

json_source_details_array() {
  local first=1
  local source_file source_id required bootstrap_exception
  printf '['
  for source_file in "$PLAN_DIR"/sources/*.list; do
    [[ -f "$source_file" ]] || continue
    while IFS= read -r source_id; do
      [[ -n "$source_id" ]] || continue
      load_source_descriptor "$DISTRO" "$source_id" || continue
      [[ "$first" -eq 1 ]] || printf ','
      required=false
      bootstrap_exception=false
      [[ "${SOURCE_REQUIRED:-0}" -eq 1 ]] && required=true
      [[ "${SOURCE_BOOTSTRAP_EXCEPTION:-0}" -eq 1 ]] && bootstrap_exception=true
      printf '{"id":"%s","kind":"%s","label":"%s","required":%s,"gpg_policy":"%s","bootstrap_exception":%s,"reason":"%s"}' \
        "$(json_escape "$SOURCE_ID")" \
        "$(json_escape "$SOURCE_KIND")" \
        "$(json_escape "$SOURCE_LABEL")" \
        "$required" \
        "$(json_escape "$SOURCE_GPG_POLICY")" \
        "$bootstrap_exception" \
        "$(json_escape "$SOURCE_REASON")"
      first=0
    done < <(read_plan_file "$source_file")
  done
  printf ']'
}

json_base_rationale_array() {
  local file="$PLAN_DIR/base-rationale.tsv"
  local first=1 backend item owner classification consumer reason
  printf '['
  if [[ -f "$file" ]]; then
    while IFS=$'\t' read -r backend item owner classification consumer reason; do
      [[ "$backend" != "backend" && -n "$backend" ]] || continue
      [[ "$first" -eq 1 ]] || printf ','
      printf '{"backend":"%s","item":"%s","owner_bundle":"%s","classification":"%s","consumer":"%s","reason":"%s"}' \
        "$(json_escape "$backend")" \
        "$(json_escape "$item")" \
        "$(json_escape "$owner")" \
        "$(json_escape "$classification")" \
        "$(json_escape "$consumer")" \
        "$(json_escape "$reason")"
      first=0
    done <"$file"
  fi
  printf ']'
}

json_managed_config_policy_array() {
  local file="$PLAN_DIR/files/managed-config-policy.tsv"
  local first=1 path mode conflict owner description
  printf '['
  if [[ -f "$file" ]]; then
    while IFS=$'\t' read -r path mode conflict owner description; do
      [[ -n "$path" ]] || continue
      [[ "$first" -eq 1 ]] || printf ','
      printf '{"path":"%s","mode":"%s","conflict":"%s","owner":"%s","description":"%s"}' \
        "$(json_escape "$path")" \
        "$(json_escape "$mode")" \
        "$(json_escape "$conflict")" \
        "$(json_escape "$owner")" \
        "$(json_escape "$description")"
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
  printf ',"source_details":'
  json_source_details_array
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
  printf ',"managed_config_policy":'
  json_managed_config_policy_array
  printf ',"base_rationale":'
  json_base_rationale_array
  printf ',"warnings":'
  json_warnings_array
  printf '}\n'
}
