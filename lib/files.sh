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

managed_config_policy_file() {
  printf '%s/config/managed-config.tsv\n' "$ROOT_DIR"
}

managed_config_plan_file() {
  printf '%s/files/managed-config-policy.tsv\n' "$PLAN_DIR"
}

managed_config_policy_record() {
  local managed_path="$1"
  local policy_file
  policy_file="$(managed_config_policy_file)"
  [[ -f "$policy_file" ]] || return 1
  awk -F'\t' -v managed_path="$managed_path" 'NF>=5 && $1 !~ /^#/ && $1 == managed_path {print; found=1; exit} END {exit found ? 0 : 1}' "$policy_file"
}

managed_config_stow_owner() {
  local managed_path="$1"
  local relative_path="${managed_path#\~/}"
  local package_name
  [[ "$managed_path" == \~/* ]] || return 1
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
  record="$(managed_config_policy_record "$managed_path" || true)"
  if [[ -n "$record" ]]; then
    printf '%s\n' "$record"
    return 0
  fi

  owner="$(managed_config_stow_owner "$managed_path" || true)"
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
