#!/usr/bin/env bash
set -Eeuo pipefail

# Declarative user/system configuration ownership. Catalog units select
# components; config/managed-config.tsv maps each component to seeded
# user-owned files, live product links, system files, or generated state.

declare -Ag MANAGED_CONFIG_POLICY_CACHE=()
MANAGED_CONFIG_POLICY_CACHE_LOADED=0

append_managed_file() {
  local path="$1"
  append_plan_entries "$PLAN_DIR/files/managed-files.list" "$path"
}

managed_config_policy_file() {
  printf '%s/config/managed-config.tsv\n' "$ROOT_DIR"
}

managed_config_deployment_plan_file() {
  printf '%s/files/config-deployments.tsv\n' "$PLAN_DIR"
}

managed_config_plan_file() {
  printf '%s/files/managed-config-policy.tsv\n' "$PLAN_DIR"
}

managed_config_source_path() {
  local source="$1"
  [[ -n "$source" && "$source" != "-" ]] || return 1
  printf '%s/%s\n' "$ROOT_DIR" "$source"
}

managed_config_target_path() {
  local path="$1"
  case "$path" in
    \~/*) printf '%s/%s\n' "$TARGET_HOME" "${path#\~/}" ;;
    /*) printf '%s\n' "$path" ;;
    *) die "Managed config path must start with ~/ or /: $path" ;;
  esac
}

load_managed_config_policy_cache() {
  [[ "$MANAGED_CONFIG_POLICY_CACHE_LOADED" -eq 1 ]] && return 0

  local component path mode conflict source required_command description extra
  while IFS=$'\t' read -r component path mode conflict source required_command description extra ||
    [[ -n "$component" ]]; do
    [[ -n "$component" && "$component" != \#* ]] || continue
    [[ "$component" =~ ^[a-z0-9-]+$ ]] ||
      die "Invalid managed config component: $component"
    [[ -n "$path" && -n "$mode" && -n "$conflict" && -n "$source" &&
      -n "$required_command" && -n "$description" && -z "$extra" ]] ||
      die "Invalid managed config row for component '$component'"
    [[ "$path" == \~/* || "$path" == /* ]] ||
      die "Managed config path must start with ~/ or /: $path"
    case "$mode:$conflict" in
      seed-if-missing:preserve | product-link:backup-before-link | system-file:regenerate | directory:preserve | generated:regenerate | first-run:regenerate) ;;
      *) die "Invalid managed config mode/conflict pair '$mode:$conflict' for $path" ;;
    esac
    case "$mode" in
      product-link | system-file)
        [[ "$source" != "-" ]] || die "Managed config mode '$mode' requires a source: $path"
        ;;
      directory | generated | first-run)
        [[ "$source" == "-" ]] || die "Managed config mode '$mode' must not declare a source: $path"
        ;;
    esac
    if [[ "$source" != "-" ]]; then
      [[ "$source" != /* && "$source" != ../* && "$source" != */../* && "$source" != */.. ]] ||
        die "Managed config source must stay inside the repository: $source"
      [[ -e "$ROOT_DIR/$source" || -L "$ROOT_DIR/$source" ]] ||
        die "Managed config source not found: $source"
    fi
    [[ -z "${MANAGED_CONFIG_POLICY_CACHE[$path]:-}" ]] ||
      die "Duplicate managed config path: $path"
    MANAGED_CONFIG_POLICY_CACHE["$path"]="$component"$'\t'"$path"$'\t'"$mode"$'\t'"$conflict"$'\t'"$source"$'\t'"$required_command"$'\t'"$description"
  done <"$(managed_config_policy_file)"
  MANAGED_CONFIG_POLICY_CACHE_LOADED=1
}

append_managed_config_component() {
  local wanted="$1" found=0
  local component path mode conflict source required_command description extra
  load_managed_config_policy_cache
  while IFS=$'\t' read -r component path mode conflict source required_command description extra ||
    [[ -n "$component" ]]; do
    [[ "$component" == "$wanted" ]] || continue
    found=1
    append_managed_file "$path"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$component" "$path" "$mode" "$conflict" "$source" "$required_command" "$description" \
      >>"$(managed_config_deployment_plan_file)"
  done <"$(managed_config_policy_file)"
  [[ "$found" -eq 1 ]] || die "Unknown managed config component: $wanted"
}

managed_config_policy_record() {
  local path="$1"
  load_managed_config_policy_cache
  [[ -n "${MANAGED_CONFIG_POLICY_CACHE[$path]:-}" ]] || return 1
  printf '%s\n' "${MANAGED_CONFIG_POLICY_CACHE[$path]}"
}

managed_config_policy_for_path() {
  local path="$1"
  local record component _path mode conflict _source _required description
  record="$(managed_config_policy_record "$path" || true)"
  if [[ -n "$record" ]]; then
    IFS=$'\t' read -r component _path mode conflict _source _required description <<<"$record"
    printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$mode" "$conflict" "$component" "$description"
    return 0
  fi
  printf '%s\tgenerated\tregenerate\tinstaller\tManaged by installer-generated output.\n' "$path"
}

write_managed_config_policy_plan() {
  local destination managed_path
  destination="$(managed_config_plan_file)"
  mkdir -p "$(dirname "$destination")"
  : >"$destination"
  [[ -f "$PLAN_DIR/files/managed-files.list" ]] || return 0
  while IFS= read -r managed_path; do
    [[ -n "$managed_path" ]] || continue
    managed_config_policy_for_path "$managed_path" >>"$destination"
  done < <(read_plan_file "$PLAN_DIR/files/managed-files.list")
  sort -u "$destination" -o "$destination"
}

managed_config_required_command_available() {
  local required_command="$1"
  [[ -z "$required_command" || "$required_command" == "-" ]] && return 0
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  command -v "$required_command" >/dev/null 2>&1
}

seed_user_config_if_missing() {
  local source="$1" destination="$2"
  [[ -e "$destination" || -L "$destination" ]] && {
    log_info "Preserving user-owned config: $destination"
    return 0
  }
  log_progress "Seeding user-owned config: $destination"
  install_file_if_changed user "$source" "$destination"
}

replace_user_path_with_product_link() {
  local source="$1" destination="$2"
  [[ "$source" == "$ROOT_DIR"/* ]] ||
    die "Product link source must stay inside $ROOT_DIR: $source"
  [[ "$destination" == "$TARGET_HOME"/* ]] ||
    die "Product link destination must stay inside $TARGET_HOME: $destination"
  [[ -e "$source" || -L "$source" ]] || die "Product link source not found: $source"

  local current_target=""
  if [[ -L "$destination" ]]; then
    current_target="$(readlink -f "$destination" 2>/dev/null || true)"
    if [[ "$current_target" == "$(readlink -f "$source")" ]]; then
      log_info "Product link already current: $destination"
      return 0
    fi
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    backup_user_file_if_needed "$destination"
    run_cmd_as_user "$TARGET_USER" rm -rf -- "$destination"
  fi
  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$destination")"
  run_cmd_as_user "$TARGET_USER" ln -s "$source" "$destination"
}

install_system_config_file() {
  local source="$1" destination="$2"
  [[ "$destination" == /etc/* || "$destination" == /usr/lib/* ]] ||
    die "System config destination is outside the supported roots: $destination"
  install_file_if_changed root "$source" "$destination"
}

apply_managed_config_plan() {
  local plan_file
  plan_file="$(managed_config_deployment_plan_file)"
  [[ -f "$plan_file" ]] || return 0

  local component path mode conflict source required_command description
  local source_path destination
  while IFS=$'\t' read -r component path mode conflict source required_command description; do
    [[ -n "$component" ]] || continue
    if [[ "$SKIP_USER_CONFIG" -eq 1 && "$path" == \~/* ]]; then
      log_info "Skipping user config: $path"
      continue
    fi
    if ! managed_config_required_command_available "$required_command"; then
      log_info "Skipping $path because '$required_command' is unavailable"
      continue
    fi
    destination="$(managed_config_target_path "$path")"
    source_path="$(managed_config_source_path "$source" || true)"
    case "$mode" in
      seed-if-missing)
        [[ -n "$source_path" ]] || continue
        seed_user_config_if_missing "$source_path" "$destination"
        ;;
      product-link)
        replace_user_path_with_product_link "$source_path" "$destination"
        ;;
      system-file)
        install_system_config_file "$source_path" "$destination"
        ;;
      directory)
        run_cmd_as_user "$TARGET_USER" mkdir -p "$destination"
        ;;
      generated|first-run)
        ;;
      *)
        die "Unsupported managed config mode '$mode' for $path"
        ;;
    esac
  done <"$plan_file"
}

write_managed_config_conflict_preview() {
  local preview_file="$PLAN_DIR/files/config-conflicts.tsv"
  : >"$preview_file"
  [[ -d "${TARGET_HOME:-}" ]] || return 0

  local component path mode conflict source required_command description
  local destination source_path current_target
  while IFS=$'\t' read -r component path mode conflict source required_command description; do
    [[ "$mode" == "product-link" ]] || continue
    [[ "$SKIP_USER_CONFIG" -eq 0 || "$path" != \~/* ]] || continue
    destination="$(managed_config_target_path "$path")"
    [[ -e "$destination" || -L "$destination" ]] || continue
    source_path="$(managed_config_source_path "$source")"
    current_target=""
    [[ -L "$destination" ]] && current_target="$(readlink -f "$destination" 2>/dev/null || true)"
    [[ "$current_target" == "$(readlink -f "$source_path")" ]] && continue
    printf '%s\t%s\t%s\n' "$path" "$component" "$conflict" >>"$preview_file"
  done <"$(managed_config_deployment_plan_file)"
  sort -u "$preview_file" -o "$preview_file"
}

managed_files_report_path() {
  printf '%s/managed-files-report.txt\n' "$STATE_DIR"
}

write_managed_files_report() {
  ensure_state_dirs
  local report_file
  report_file="$(managed_files_report_path)"
  {
    printf 'Managed files report\n'
    printf 'Generated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'Target user: %s\n' "${TARGET_USER:-}"
    printf 'Target home: %s\n' "${TARGET_HOME:-}"

    printf '\nPlanned managed files:\n'
    [[ -f "$PLAN_DIR/files/managed-files.list" ]] &&
      sed 's/^/  - /' "$PLAN_DIR/files/managed-files.list"

    printf '\nPlanned product-link replacements:\n'
    if [[ -f "$PLAN_DIR/files/config-conflicts.tsv" ]]; then
      awk -F'\t' 'NF>=3 {printf "  - %s (%s: %s)\n", $1, $2, $3}' "$PLAN_DIR/files/config-conflicts.tsv"
    fi

    printf '\nManaged config policy:\n'
    if [[ -f "$PLAN_DIR/files/managed-config-policy.tsv" ]]; then
      awk -F'\t' 'NF>=5 {printf "  - %s (%s, %s, owner=%s) %s\n", $1, $2, $3, $4, $5}' "$PLAN_DIR/files/managed-config-policy.tsv"
    fi

    printf '\nExisting backups:\n'
    if [[ -d "$STATE_DIR/backups" ]]; then
      find "$STATE_DIR/backups" \( -type f -o -type l \) 2>/dev/null | sort | sed 's/^/  - /'
    fi
  } >"$report_file"
}
