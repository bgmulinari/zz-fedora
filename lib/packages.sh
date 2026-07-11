#!/usr/bin/env bash
set -Eeuo pipefail

native_backend() {
  printf 'dnf\n'
}

package_file_for_backend() {
  case "$1" in
    dnf) printf '%s/packages/dnf.pkgs\n' "$PLAN_DIR" ;;
    flatpak) printf '%s/flatpak/apps.flatpaks\n' "$PLAN_DIR" ;;
    action) printf '%s/actions/actions.list\n' "$PLAN_DIR" ;;
    *) die "Unsupported plan package backend: $1" ;;
  esac
}

prereq_file_for_backend() {
  case "$1" in
    dnf) printf '%s/prereqs/dnf.pkgs\n' "$PLAN_DIR" ;;
    flatpak) printf '%s/prereqs/flatpak.flatpaks\n' "$PLAN_DIR" ;;
    action) printf '%s/prereqs/actions.list\n' "$PLAN_DIR" ;;
    *) die "Unsupported prereq backend: $1" ;;
  esac
}

backend_prerequisite_backend() {
  case "$1" in
    dnf|action) return 1 ;;
    flatpak) native_backend ;;
    *) die "Unsupported backend: $1" ;;
  esac
}

backend_prerequisite_items() {
  case "$1" in
    dnf|action) return 0 ;;
    flatpak)
      manifest_entries "$ROOT_DIR/packages/official/flatpak.pkgs"
      ;;
    *)
      die "Unsupported backend: $1"
      ;;
  esac
}

append_plan_entries() {
  local destination="$1"
  shift
  local destination_dir="."
  [[ "$destination" == */* ]] && destination_dir="${destination%/*}"
  [[ -d "$destination_dir" ]] || mkdir -p "$destination_dir"
  [[ -e "$destination" ]] || : >"$destination"

  local -A seen=()
  local existing
  while IFS= read -r existing; do
    [[ -n "$existing" ]] || continue
    seen["$existing"]=1
  done <"$destination"

  local item
  local changed=0
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    [[ -n "${seen[$item]:-}" ]] && continue
    printf '%s\n' "$item" >>"$destination"
    seen["$item"]=1
    changed=1
  done
  if [[ "$changed" -ne 0 && "${DEFER_PLAN_SORT:-0}" -ne 1 ]]; then
    sort -u "$destination" -o "$destination"
  fi
}

read_plan_file() {
  local plan_file="$1"
  [[ -f "$plan_file" ]] || return 0
  read_clean_lines "$plan_file" | sort -u
}

remove_plan_entries() {
  local plan_file="$1"
  shift
  [[ -f "$plan_file" ]] || return 0
  [[ "$#" -gt 0 ]] || return 0

  local filtered
  filtered="$(mktemp "$CACHE_DIR/plan-filter.XXXXXX")"
  local entry
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    array_contains "$entry" "$@" && continue
    printf '%s\n' "$entry" >>"$filtered"
  done < <(read_plan_file "$plan_file")
  mv -f "$filtered" "$plan_file"
}

record_system_skip() {
  local backend="$1"
  local item="$2"
  local reason="$3"
  local skip_file="$PLAN_DIR/system-skips.tsv"
  mkdir -p "$(dirname "$skip_file")"
  touch "$skip_file"
  grep -Fx "$backend	$item	$reason" "$skip_file" >/dev/null 2>&1 && return 0
  printf '%s\t%s\t%s\n' "$backend" "$item" "$reason" >>"$skip_file"
}
