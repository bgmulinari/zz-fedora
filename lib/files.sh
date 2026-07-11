#!/usr/bin/env bash
set -Eeuo pipefail

declare -Ag MANAGED_CONFIG_POLICY_CACHE=()
MANAGED_CONFIG_POLICY_CACHE_LOADED=0
declare -Ag MANAGED_CONFIG_STOW_OWNER_CACHE=()

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
    MANAGED_CONFIG_STOW_OWNER_CACHE["~/$relative_path"]="$package_name"
    append_managed_file "~/$relative_path"
  done < <(find "$package_dir" -type f ! -name '.keep' -printf '%P\n' | sort)
}

managed_config_policy_file() {
  printf '%s/config/managed-config.tsv\n' "$ROOT_DIR"
}

managed_config_plan_file() {
  printf '%s/files/managed-config-policy.tsv\n' "$PLAN_DIR"
}

managed_config_policy_record() {
  local managed_path="$1"
  load_managed_config_policy_cache
  [[ -n "${MANAGED_CONFIG_POLICY_CACHE[$managed_path]:-}" ]] || return 1
  printf '%s\n' "${MANAGED_CONFIG_POLICY_CACHE[$managed_path]}"
}

load_managed_config_policy_cache() {
  [[ "$MANAGED_CONFIG_POLICY_CACHE_LOADED" -eq 1 ]] && return 0

  local policy_file path mode conflict owner description
  policy_file="$(managed_config_policy_file)"
  [[ -f "$policy_file" ]] || return 0
  while IFS=$'\t' read -r path mode conflict owner description _extra || [[ -n "$path" ]]; do
    [[ -n "$path" && "$path" != \#* ]] || continue
    [[ -n "$mode" && -n "$conflict" && -n "$owner" ]] || continue
    MANAGED_CONFIG_POLICY_CACHE["$path"]="$path"$'\t'"$mode"$'\t'"$conflict"$'\t'"$owner"$'\t'"$description"
  done <"$policy_file"
  MANAGED_CONFIG_POLICY_CACHE_LOADED=1
}

managed_config_stow_owner() {
  local managed_path="$1"
  local relative_path="${managed_path#\~/}"
  local package_name
  [[ "$managed_path" == \~/* ]] || return 1
  if [[ -n "${MANAGED_CONFIG_STOW_OWNER_CACHE[$managed_path]:-}" ]]; then
    printf '%s\n' "${MANAGED_CONFIG_STOW_OWNER_CACHE[$managed_path]}"
    return 0
  fi
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    [[ -e "$ROOT_DIR/dotfiles/$package_name/$relative_path" || -L "$ROOT_DIR/dotfiles/$package_name/$relative_path" ]] || continue
    printf '%s\n' "$package_name"
    return 0
  done < <(read_plan_file "$PLAN_DIR/stow/packages.list")
  return 1
}

managed_config_policy_for_path() {
  local managed_path="$1"
  local record owner
  load_managed_config_policy_cache
  record="${MANAGED_CONFIG_POLICY_CACHE[$managed_path]:-}"
  if [[ -n "$record" ]]; then
    printf '%s\n' "$record"
    return 0
  fi

  owner="${MANAGED_CONFIG_STOW_OWNER_CACHE[$managed_path]:-}"
  if [[ -z "$owner" ]]; then
    owner="$(managed_config_stow_owner "$managed_path" || true)"
  fi
  if [[ -n "$owner" ]]; then
    printf '%s\tstow\tbackup-before-stow\t%s\tStowed from dotfiles/%s.\n' "$managed_path" "$owner" "$owner"
    return 0
  fi

  printf '%s\tgenerated\tregenerate\tinstaller\tManaged by installer-generated output.\n' "$managed_path"
}

write_managed_config_policy_plan() {
  local destination managed_path
  destination="$(managed_config_plan_file)"
  mkdir -p "$(dirname "$destination")"
  : >"$destination"
  [[ -f "$PLAN_DIR/files/managed-files.list" ]] || return 0
  load_managed_config_policy_cache
  while IFS= read -r managed_path; do
    [[ -n "$managed_path" ]] || continue
    managed_config_policy_for_path "$managed_path" >>"$destination"
  done < <(read_plan_file "$PLAN_DIR/files/managed-files.list")
  sort -u "$destination" -o "$destination"
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
    if [[ -f "$PLAN_DIR/files/managed-files.list" ]]; then
      sed 's/^/  - /' "$PLAN_DIR/files/managed-files.list"
    fi

    printf '\nPlanned backup-before-stow conflicts:\n'
    if [[ -f "$PLAN_DIR/files/config-conflicts.tsv" ]]; then
      awk -F'\t' 'NF>=3 {printf "  - %s (%s: %s)\n", $1, $2, $3}' "$PLAN_DIR/files/config-conflicts.tsv"
    fi

    printf '\nManaged config policy:\n'
    if [[ -f "$PLAN_DIR/files/managed-config-policy.tsv" ]]; then
      awk -F'\t' 'NF>=5 {printf "  - %s (%s, %s, owner=%s) %s\n", $1, $2, $3, $4, $5}' "$PLAN_DIR/files/managed-config-policy.tsv"
    fi

    printf '\nExisting backups:\n'
    if [[ -d "$STATE_DIR/backups" ]]; then
      find "$STATE_DIR/backups" -mindepth 1 -type f -o -type l 2>/dev/null | sort | sed 's/^/  - /'
    fi
  } >"$report_file"
}
