#!/usr/bin/env bash
set -Eeuo pipefail

# Generic Bash helpers with no repository knowledge.

is_tty() {
  [[ -t 0 && -t 1 ]]
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

join_by() {
  local delimiter="$1"
  shift || true
  local first=1
  local item
  for item in "$@"; do
    if [[ $first -eq 1 ]]; then
      printf '%s' "$item"
      first=0
    else
      printf '%s%s' "$delimiter" "$item"
    fi
  done
}

append_unique() {
  local array_name="$1"
  local value="$2"
  local -n array_ref="$array_name"
  local current
  for current in "${array_ref[@]:-}"; do
    [[ "$current" == "$value" ]] && return 0
  done
  array_ref+=("$value")
}

array_contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

split_csv() {
  local raw="${1:-}"
  local IFS=','
  local -a parts=()
  read -r -a parts <<<"$raw"
  local part
  for part in "${parts[@]}"; do
    part="${part#"${part%%[![:space:]]*}"}"
    part="${part%"${part##*[![:space:]]}"}"
    [[ -n "$part" ]] && printf '%s\n' "$part"
  done
}

resolve_target_home() {
  local user="$1"
  local entry
  entry="$(getent passwd "$user" 2>/dev/null || true)"
  if [[ -n "$entry" ]]; then
    printf '%s\n' "$(cut -d: -f6 <<<"$entry")"
    return 0
  fi
  if [[ -d "/home/$user" ]]; then
    printf '%s\n' "/home/$user"
    return 0
  fi
  return 1
}

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

read_clean_lines() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  sed -E 's/[[:space:]]*#.*$//' "$file" | sed -E '/^[[:space:]]*$/d' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

manifest_entries() {
  local file="$1"
  awk '
    {
      sub(/[[:space:]]*#.*/, "")
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      if (length($0) > 0) print
    }
  ' "$file" | sort -u
}
