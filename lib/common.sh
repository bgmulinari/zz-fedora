#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../config/defaults.sh
source "$ROOT_DIR/config/defaults.sh"
# shellcheck source=./log.sh
source "$ROOT_DIR/lib/log.sh"

STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/zz-linux-setup}"
CACHE_DIR="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz-linux-setup}"
CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zz-linux-setup}"

LOG_DIR="${LOG_DIR:-$STATE_DIR/logs}"
PLAN_DIR="$STATE_DIR/plan"
SAVED_SELECTIONS="$CONFIG_DIR/selections.conf"
LOCK_DIR="$STATE_DIR/lock"
LOG_FILE="${LOG_FILE:-}"
STATE_OWNER_USER="${STATE_OWNER_USER:-}"

mkdir -p "$STATE_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$LOG_DIR"

declare -ag WARNING_MESSAGES=()
declare -ag INFO_MESSAGES=()
declare -ag PLAN_MODULES=()
declare -Ag CATEGORY_OVERRIDES=()
declare -Ag CATEGORY_ADDITIONS=()
declare -Ag CATEGORY_OVERRIDE_PRESENT=()
declare -Ag SOURCE_FILE_CACHE=()
declare -Ag BUNDLE_FILE_CACHE=()

COMMAND="${COMMAND:-$DEFAULT_COMMAND}"
DISTRO="${DISTRO:-$DEFAULT_DISTRO}"
TARGET_USER="${TARGET_USER:-$DEFAULT_TARGET_USER}"
TARGET_HOME="${TARGET_HOME:-}"
MODE="${MODE:-$DEFAULT_COMMAND}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
USE_SAVED_SELECTIONS="${USE_SAVED_SELECTIONS:-0}"
SKIP_DOTFILES="${SKIP_DOTFILES:-0}"
STOW_ADOPT="${STOW_ADOPT:-0}"
NO_TUI="${NO_TUI:-0}"
INSTALL_WEAK_DEPS="${INSTALL_WEAK_DEPS:-0}"
PLAN_FORMAT="${PLAN_FORMAT:-text}"
PREFERRED_BROWSER="${PREFERRED_BROWSER:-}"
CURRENT_ADAPTER="${CURRENT_ADAPTER:-}"
LOCK_ACQUIRED="${LOCK_ACQUIRED:-0}"

ensure_state_dirs() {
  mkdir -p \
    "$STATE_DIR" \
    "$CACHE_DIR" \
    "$CONFIG_DIR" \
    "$LOG_DIR" \
    "$PLAN_DIR"
}

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

remove_value() {
  local array_name="$1"
  local value="$2"
  local -n array_ref="$array_name"
  local current
  local kept=()
  for current in "${array_ref[@]:-}"; do
    [[ "$current" == "$value" ]] && continue
    kept+=("$current")
  done
  array_ref=("${kept[@]:-}")
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

append_csv_unique() {
  local array_name="$1"
  local raw="${2:-}"
  local entry
  while IFS= read -r entry; do
    append_unique "$array_name" "$entry"
  done < <(split_csv "$raw")
}

detect_distro_from_file() {
  local os_release_file="$1"
  [[ -f "$os_release_file" ]] || return 1
  local id
  id="$(awk -F= '$1=="ID"{gsub(/"/, "", $2); print tolower($2)}' "$os_release_file")"
  case "$id" in
    fedora)
      printf '%s\n' "$id"
      ;;
    *)
      return 1
      ;;
  esac
}

detect_distro() {
  detect_distro_from_file "/etc/os-release"
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

trim_inline_comment() {
  sed -E 's/[[:space:]]*#.*$//'
}

read_clean_lines() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  sed -E 's/[[:space:]]*#.*$//' "$file" | sed -E '/^[[:space:]]*$/d' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

manifest_entries() {
  local file="$1"
  read_clean_lines "$file" | sort -u
}

list_source_files() {
  local distro="$1"
  find "$ROOT_DIR/sources/$distro" -type f -name '*.source' | sort
}

source_file_for_id() {
  local distro="$1"
  local source_id="$2"
  local cache_key="$distro:$source_id"
  if [[ -n "${SOURCE_FILE_CACHE[$cache_key]:-}" ]]; then
    printf '%s\n' "${SOURCE_FILE_CACHE[$cache_key]}"
    return 0
  fi

  local source_file
  for source_file in $(list_source_files "$distro"); do
    local current_id=""
    current_id="$(awk -F= '$1=="SOURCE_ID"{gsub(/"/, "", $2); print $2}' "$source_file")"
    [[ "$current_id" == "$source_id" ]] && {
      SOURCE_FILE_CACHE["$cache_key"]="$source_file"
      printf '%s\n' "$source_file"
      return 0
    }
  done
  return 1
}

load_source_descriptor() {
  local distro="$1"
  local source_id="$2"
  local source_file
  source_file="$(source_file_for_id "$distro" "$source_id")" || return 1
  unset SOURCE_ID SOURCE_KIND SOURCE_LABEL SOURCE_PROJECT SOURCE_REQUIRED SOURCE_DESCRIPTION
  # shellcheck disable=SC1090
  source "$source_file"
  SOURCE_FILE="$source_file"
}

list_source_ids() {
  local distro="$1"
  local source_file
  while IFS= read -r source_file; do
    awk -F= '$1=="SOURCE_ID"{gsub(/"/, "", $2); print $2}' "$source_file"
  done < <(list_source_files "$distro")
}

list_bundle_files() {
  local distro="$1"
  find "$ROOT_DIR/bundles/$distro" -type f -name '*.bundle' | sort
}

bundle_file_for_id() {
  local distro="$1"
  local bundle_id="$2"
  local cache_key="$distro:$bundle_id"
  if [[ -n "${BUNDLE_FILE_CACHE[$cache_key]:-}" ]]; then
    printf '%s\n' "${BUNDLE_FILE_CACHE[$cache_key]}"
    return 0
  fi

  local bundle_file
  for bundle_file in $(list_bundle_files "$distro"); do
    local current_id=""
    current_id="$(awk -F= '$1=="BUNDLE_ID"{gsub(/"/, "", $2); print $2}' "$bundle_file")"
    [[ "$current_id" == "$bundle_id" ]] && {
      BUNDLE_FILE_CACHE["$cache_key"]="$bundle_file"
      printf '%s\n' "$bundle_file"
      return 0
    }
  done
  return 1
}

load_bundle_descriptor() {
  local distro="$1"
  local bundle_id="$2"
  local bundle_file
  bundle_file="$(bundle_file_for_id "$distro" "$bundle_id")" || return 1
  unset \
    BUNDLE_ID \
    BUNDLE_INSTALLER \
    BUNDLE_SOURCE_ID \
    BUNDLE_ITEMS_FILE \
    BUNDLE_STOW_PACKAGES \
    BUNDLE_DESCRIPTION
  # shellcheck disable=SC1090
  source "$bundle_file"
  BUNDLE_FILE="$bundle_file"
}

bundle_supported_for_distro() {
  local distro="$1"
  local installer="$2"
  case "$distro:$installer" in
    fedora:dnf|fedora:flatpak|fedora:action)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_bundle_descriptor() {
  local distro="$1"
  local bundle_file="$2"

  unset \
    BUNDLE_ID \
    BUNDLE_INSTALLER \
    BUNDLE_SOURCE_ID \
    BUNDLE_ITEMS_FILE \
    BUNDLE_STOW_PACKAGES \
    BUNDLE_DESCRIPTION
  # shellcheck disable=SC1090
  source "$bundle_file"

  [[ -n "${BUNDLE_ID:-}" ]] || die "Missing BUNDLE_ID in $bundle_file"
  [[ -n "${BUNDLE_INSTALLER:-}" ]] || die "Missing BUNDLE_INSTALLER in $bundle_file"
  [[ -n "${BUNDLE_ITEMS_FILE:-}" ]] || die "Missing BUNDLE_ITEMS_FILE in $bundle_file"
  [[ -n "${BUNDLE_DESCRIPTION:-}" ]] || die "Missing BUNDLE_DESCRIPTION in $bundle_file"
  bundle_supported_for_distro "$distro" "$BUNDLE_INSTALLER" || die "Unsupported installer '$BUNDLE_INSTALLER' in $bundle_file"
  [[ -f "$ROOT_DIR/$BUNDLE_ITEMS_FILE" ]] || die "Missing bundle payload file '$BUNDLE_ITEMS_FILE' in $bundle_file"

  if [[ -n "${BUNDLE_SOURCE_ID:-}" ]]; then
    source_file_for_id "$distro" "$BUNDLE_SOURCE_ID" >/dev/null || die "Unknown source ID '$BUNDLE_SOURCE_ID' in $bundle_file"
  fi
}

validate_bundle_catalog() {
  local distro="$1"
  local bundle_file
  while IFS= read -r bundle_file; do
    validate_bundle_descriptor "$distro" "$bundle_file"
  done < <(list_bundle_files "$distro")
}

choice_catalog_path() {
  local distro="$1"
  local category
  category="$(normalize_category_name "$2")"
  printf '%s\n' "$ROOT_DIR/choices/$distro/$category.conf"
}

common_choice_catalog_path() {
  local category="$1"
  printf '%s\n' "$ROOT_DIR/choices/common/$category.conf"
}

validate_choice_catalog() {
  local distro="$1"
  local category="$2"
  local catalog
  catalog="$(choice_catalog_path "$distro" "$category")"
  [[ -f "$catalog" ]] || return 0
  local line
  local line_no=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    local field_count
    field_count="$(awk -F'\t' '{print NF}' <<<"$line")"
    [[ "$field_count" -eq 5 ]] || die "Invalid catalog row at $catalog:$line_no"
    local id label default_flag bundle_ids description
    id="$(choice_field "$line" 1)"
    label="$(choice_field "$line" 2)"
    default_flag="$(choice_field "$line" 3)"
    bundle_ids="$(choice_field "$line" 4)"
    description="$(choice_field "$line" 5)"
    [[ -n "$id" && -n "$label" && -n "$default_flag" && -n "$description" ]] || die "Invalid empty field in $catalog:$line_no"
    local bundle_id
    while IFS= read -r bundle_id; do
      [[ -z "$bundle_id" ]] && continue
      bundle_file_for_id "$distro" "$bundle_id" >/dev/null || die "Unknown bundle ID '$bundle_id' in $catalog:$line_no"
    done < <(split_csv "$bundle_ids")
  done <"$catalog"
}

list_choice_catalogs() {
  local distro="$1"
  find "$ROOT_DIR/choices/$distro" -maxdepth 1 -type f -name '*.conf' | sort
}

default_choice_ids() {
  local distro="$1"
  local category="$2"
  local catalog
  catalog="$(choice_catalog_path "$distro" "$category")"
  [[ -f "$catalog" ]] || return 0
  awk -F'\t' 'NF==5 && $1 !~ /^#/ && $3 == 1 {print $1}' "$catalog"
}

all_choice_ids() {
  local distro="$1"
  local category="$2"
  local catalog
  catalog="$(choice_catalog_path "$distro" "$category")"
  [[ -f "$catalog" ]] || return 0
  awk -F'\t' 'NF==5 && $1 !~ /^#/ {print $1}' "$catalog"
}

category_always_installed() {
  case "$1" in
    shell) return 0 ;;
    *) return 1 ;;
  esac
}

choice_record() {
  local distro="$1"
  local category="$2"
  local choice_id="$3"
  local catalog
  catalog="$(choice_catalog_path "$distro" "$category")"
  [[ -f "$catalog" ]] || return 1
  awk -F'\t' -v choice_id="$choice_id" 'NF==5 && $1 !~ /^#/ && $1 == choice_id {print $0}' "$catalog"
}

choice_field() {
  local line="$1"
  local field_index="$2"
  awk -F'\t' -v field_index="$field_index" '{print $field_index}' <<<"$line"
}

category_names() {
  find "$ROOT_DIR/choices/$1" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort
}

set_category_override() {
  local category="$1"
  category="$(normalize_category_name "$category")"
  [[ -n "$category" ]] || die "Invalid empty selection category"
  local values="${2:-}"
  CATEGORY_OVERRIDES["$category"]="$values"
  CATEGORY_OVERRIDE_PRESENT["$category"]=1
}

add_category_selection() {
  local category="$1"
  category="$(normalize_category_name "$category")"
  [[ -n "$category" ]] || return 0
  local values="${2:-}"
  [[ -n "$values" ]] || return 0
  if [[ -n "${CATEGORY_ADDITIONS[$category]:-}" && -n "$values" ]]; then
    CATEGORY_ADDITIONS["$category"]+=",${values}"
  else
    CATEGORY_ADDITIONS["$category"]="$values"
  fi
}

effective_choice_ids() {
  local distro="$1"
  local category
  category="$(normalize_category_name "$2")"
  local -a chosen=()
  local entry
  if category_always_installed "$category"; then
    while IFS= read -r entry; do
      append_unique chosen "$entry"
    done < <(all_choice_ids "$distro" "$category")
  elif [[ -n "${CATEGORY_OVERRIDE_PRESENT[$category]:-}" ]]; then
    while IFS= read -r entry; do
      append_unique chosen "$entry"
    done < <(split_csv "${CATEGORY_OVERRIDES[$category]}")
  else
    while IFS= read -r entry; do
      append_unique chosen "$entry"
    done < <(default_choice_ids "$distro" "$category")
  fi
  while IFS= read -r entry; do
    append_unique chosen "$entry"
  done < <(split_csv "${CATEGORY_ADDITIONS[$category]:-}")
  printf '%s\n' "${chosen[@]:-}"
}

save_selections() {
  ensure_state_dirs
  {
    printf 'distro=%s\n' "$DISTRO"
    printf 'target_user=%s\n' "$TARGET_USER"
    printf 'preferred_browser=%s\n' "$PREFERRED_BROWSER"
    local category
    for category in $(category_names "$DISTRO"); do
      local values=()
      while IFS= read -r item; do
        [[ -n "$item" ]] && values+=("$item")
      done < <(effective_choice_ids "$DISTRO" "$category")
      printf 'select.%s=%s\n' "$category" "$(join_by , "${values[@]:-}")"
    done
  } >"$SAVED_SELECTIONS"
}

load_saved_selections() {
  [[ -f "$SAVED_SELECTIONS" ]] || die "Saved selections not found at $SAVED_SELECTIONS"
  local line key value
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ -z "$key" ]] && continue
    case "$key" in
      distro) DISTRO="$value" ;;
      target_user) TARGET_USER="$value" ;;
      preferred_browser) PREFERRED_BROWSER="$value" ;;
      select.*)
        set_category_override "${key#select.}" "$value"
        ;;
    esac
  done <"$SAVED_SELECTIONS"
}

browser_desktop_file() {
  case "$1" in
    firefox) printf 'firefox.desktop\n' ;;
    chromium) printf 'chromium.desktop\n' ;;
    chrome) printf 'google-chrome.desktop\n' ;;
    brave) printf 'brave-browser.desktop\n' ;;
    zen-copr) printf 'zen.desktop\n' ;;
    helium|helium-copr) printf 'helium.desktop\n' ;;
    *) return 1 ;;
  esac
}

load_adapter() {
  CURRENT_ADAPTER="$ROOT_DIR/distros/$DISTRO.sh"
  [[ -f "$CURRENT_ADAPTER" ]] || die "Unsupported distro adapter: $DISTRO"
  # shellcheck disable=SC1090
  source "$CURRENT_ADAPTER"
}

normalize_category_name() {
  case "$1" in
    browser) printf 'browsers\n' ;;
    source) printf 'sources\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}
