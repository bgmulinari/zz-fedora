#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../config/defaults.sh
source "$ROOT_DIR/config/defaults.sh"
# shellcheck source=./log.sh
source "$ROOT_DIR/lib/log.sh"

STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/zz-fedora}"
CACHE_DIR="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz-fedora}"
CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zz-fedora}"

LOG_DIR="${LOG_DIR:-$STATE_DIR/logs}"
PLAN_DIR="$STATE_DIR/plan"
SAVED_SELECTIONS="$CONFIG_DIR/selections.conf"
LOCK_FILE="$STATE_DIR/install.lock"
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
declare -Ag SOURCE_FILE_CACHE_LOADED=()
declare -Ag BUNDLE_FILE_CACHE_LOADED=()

COMMAND="${COMMAND:-$DEFAULT_COMMAND}"
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
VERIFY_INSTALLS="${VERIFY_INSTALLS:-1}"
PLAN_FORMAT="${PLAN_FORMAT:-text}"
COMMAND_PREVIEW="${COMMAND_PREVIEW:-0}"
DESKTOP_APP_PROFILE="${DESKTOP_APP_PROFILE:-$DEFAULT_DESKTOP_APP_PROFILE}"
PREFERRED_BROWSER="${PREFERRED_BROWSER:-}"
LOCK_ACQUIRED="${LOCK_ACQUIRED:-0}"
LOCK_FD="${LOCK_FD:-}"
FAILURE_SUMMARY_PRINTED="${FAILURE_SUMMARY_PRINTED:-0}"
IN_FATAL_HANDLER="${IN_FATAL_HANDLER:-0}"
ACTIVE_STEP_LABEL="${ACTIVE_STEP_LABEL:-}"
ACTIVE_STEP_ID="${ACTIVE_STEP_ID:-}"
ACTIVE_STEP_CURRENT="${ACTIVE_STEP_CURRENT:-0}"
ACTIVE_STEP_TOTAL="${ACTIVE_STEP_TOTAL:-0}"
ACTIVE_STEP_STARTED_AT="${ACTIVE_STEP_STARTED_AT:-}"
LAST_COMMAND_CONTEXT="${LAST_COMMAND_CONTEXT:-}"

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

array_contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

desktop_app_profile_value() {
  case "${DESKTOP_APP_PROFILE:-auto}" in
    auto|full|minimal)
      printf '%s\n' "${DESKTOP_APP_PROFILE:-auto}"
      ;;
    *)
      die "Unsupported desktop app profile: $DESKTOP_APP_PROFILE"
      ;;
  esac
}

existing_full_desktop_detected() {
  local current_desktop="${XDG_CURRENT_DESKTOP:-}"
  local desktop_session="${DESKTOP_SESSION:-}"
  local lowered marker

  lowered="$(printf '%s:%s\n' "$current_desktop" "$desktop_session" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    *gnome*|*kde*|*plasma*)
      return 0
      ;;
  esac

  for marker in \
    /usr/share/wayland-sessions/gnome.desktop \
    /usr/share/xsessions/gnome.desktop \
    /usr/share/wayland-sessions/plasma.desktop \
    /usr/share/xsessions/plasma.desktop; do
    [[ -f "$marker" ]] && return 0
  done

  for marker in gnome-shell plasmashell startplasma-wayland startplasma-x11; do
    command -v "$marker" >/dev/null 2>&1 && return 0
  done

  return 1
}

resolved_desktop_app_profile() {
  local profile
  profile="$(desktop_app_profile_value)"
  if [[ "$profile" == "auto" ]]; then
    if existing_full_desktop_detected; then
      printf 'minimal\n'
    else
      printf 'full\n'
    fi
    return 0
  fi
  printf '%s\n' "$profile"
}

minimal_desktop_skips_bundle() {
  array_contains "$1" "${MINIMAL_DESKTOP_SKIP_BUNDLE_IDS[@]:-}"
}

effective_base_bundle_ids() {
  local profile bundle_id
  profile="$(resolved_desktop_app_profile)"

  for bundle_id in "${BASE_BUNDLE_IDS[@]:-}"; do
    if [[ "$profile" == "minimal" ]] && minimal_desktop_skips_bundle "$bundle_id"; then
      continue
    fi
    printf '%s\n' "$bundle_id"
  done
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

bundle_manifest_entries() {
  [[ -n "${BUNDLE_ITEMS_FILE:-}" ]] || return 0
  manifest_entries "$ROOT_DIR/$BUNDLE_ITEMS_FILE"
}

list_source_files() {
  find "$ROOT_DIR/sources" -type f -name '*.source' | sort
}

descriptor_value_from_file() {
  local file="$1"
  local key="$2"
  local result_name="$3"
  local -n result_ref="$result_name"
  local line value

  result_ref=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$key="* ]] || continue
    value="${line#*=}"
    if [[ "$value" == \"*\" ]]; then
      value="${value#\"}"
      value="${value%\"}"
    fi
    result_ref="$value"
    return 0
  done <"$file"
  return 1
}

load_source_file_cache() {
  [[ -n "${SOURCE_FILE_CACHE_LOADED[catalog]:-}" ]] && return 0

  local source_file source_id
  while IFS= read -r source_file; do
    descriptor_value_from_file "$source_file" SOURCE_ID source_id || continue
    [[ -n "$source_id" ]] || continue
    [[ -z "${SOURCE_FILE_CACHE[$source_id]:-}" ]] || die "Duplicate source ID '$source_id': ${SOURCE_FILE_CACHE[$source_id]} and $source_file"
    SOURCE_FILE_CACHE["$source_id"]="$source_file"
  done < <(list_source_files)
  SOURCE_FILE_CACHE_LOADED[catalog]=1
}

source_file_for_id() {
  local source_id="$1"
  load_source_file_cache
  if [[ -n "${SOURCE_FILE_CACHE[$source_id]:-}" ]]; then
    printf '%s\n' "${SOURCE_FILE_CACHE[$source_id]}"
    return 0
  fi
  return 1
}

load_source_descriptor() {
  local source_id="$1"
  local source_file
  source_file="$(source_file_for_id "$source_id")" || return 1
  unset \
    SOURCE_ID \
    SOURCE_KIND \
    SOURCE_LABEL \
    SOURCE_PROJECT \
    SOURCE_REQUIRED \
    SOURCE_DESCRIPTION \
    SOURCE_GPG_POLICY \
    SOURCE_BOOTSTRAP_EXCEPTION \
    SOURCE_REASON
  # shellcheck disable=SC1090
  source "$source_file"
  SOURCE_FILE="$source_file"
}

list_source_ids() {
  local source_file source_id
  while IFS= read -r source_file; do
    descriptor_value_from_file "$source_file" SOURCE_ID source_id || continue
    [[ -n "$source_id" ]] && printf '%s\n' "$source_id"
  done < <(list_source_files)
}

validate_source_descriptor() {
  local source_file="$1"
  unset \
    SOURCE_ID \
    SOURCE_KIND \
    SOURCE_LABEL \
    SOURCE_PROJECT \
    SOURCE_REQUIRED \
    SOURCE_DESCRIPTION \
    SOURCE_GPG_POLICY \
    SOURCE_BOOTSTRAP_EXCEPTION \
    SOURCE_REASON
  # shellcheck disable=SC1090
  source "$source_file"

  [[ -n "${SOURCE_ID:-}" ]] || die "Missing SOURCE_ID in $source_file"
  [[ "$SOURCE_ID" =~ ^[A-Za-z0-9_.:/-]+$ ]] || die "Invalid SOURCE_ID '$SOURCE_ID' in $source_file"
  [[ -n "${SOURCE_KIND:-}" ]] || die "Missing SOURCE_KIND in $source_file"
  [[ -n "${SOURCE_LABEL:-}" ]] || die "Missing SOURCE_LABEL in $source_file"
  [[ -n "${SOURCE_REQUIRED:-}" ]] || die "Missing SOURCE_REQUIRED in $source_file"
  [[ -n "${SOURCE_DESCRIPTION:-}" ]] || die "Missing SOURCE_DESCRIPTION in $source_file"
  [[ -n "${SOURCE_GPG_POLICY:-}" ]] || die "Missing SOURCE_GPG_POLICY in $source_file"
  [[ -n "${SOURCE_BOOTSTRAP_EXCEPTION:-}" ]] || die "Missing SOURCE_BOOTSTRAP_EXCEPTION in $source_file"
  [[ -n "${SOURCE_REASON:-}" ]] || die "Missing SOURCE_REASON in $source_file"
  [[ "$SOURCE_REQUIRED" == "0" || "$SOURCE_REQUIRED" == "1" ]] || die "Invalid SOURCE_REQUIRED in $source_file"
  [[ "$SOURCE_BOOTSTRAP_EXCEPTION" == "0" || "$SOURCE_BOOTSTRAP_EXCEPTION" == "1" ]] || die "Invalid SOURCE_BOOTSTRAP_EXCEPTION in $source_file"
  case "$SOURCE_GPG_POLICY" in
    distro-managed|copr-plugin|rpm-gpg-import|repo-gpg-key|flatpak-gpg|unsigned-bootstrap|pinned-commit|sha256|tls-only)
      ;;
    *)
      die "Invalid SOURCE_GPG_POLICY '$SOURCE_GPG_POLICY' in $source_file"
      ;;
  esac
  if [[ "$SOURCE_GPG_POLICY" == "unsigned-bootstrap" && "$SOURCE_BOOTSTRAP_EXCEPTION" != "1" ]]; then
    die "Unsigned bootstrap source must set SOURCE_BOOTSTRAP_EXCEPTION=1 in $source_file"
  fi
  case "$SOURCE_KIND" in
    official|copr|terra|rpmfusion|cisco-openh264|vendor|flatpak|artifact)
      ;;
    *)
      die "Unsupported source kind '$SOURCE_KIND' in $source_file"
      ;;
  esac
  case "$SOURCE_KIND" in
    artifact|copr)
      [[ -n "${SOURCE_PROJECT:-}" ]] || die "Missing SOURCE_PROJECT for $SOURCE_KIND source in $source_file"
      ;;
  esac
}

validate_source_catalog() {
  local source_file
  load_source_file_cache
  while IFS= read -r source_file; do
    validate_source_descriptor "$source_file"
  done < <(list_source_files)
}

list_bundle_files() {
  find "$ROOT_DIR/bundles" -type f -name '*.bundle' | sort
}

load_bundle_file_cache() {
  [[ -n "${BUNDLE_FILE_CACHE_LOADED[catalog]:-}" ]] && return 0

  local bundle_file bundle_id
  while IFS= read -r bundle_file; do
    descriptor_value_from_file "$bundle_file" BUNDLE_ID bundle_id || continue
    [[ -n "$bundle_id" ]] || continue
    [[ -z "${BUNDLE_FILE_CACHE[$bundle_id]:-}" ]] || die "Duplicate bundle ID '$bundle_id': ${BUNDLE_FILE_CACHE[$bundle_id]} and $bundle_file"
    BUNDLE_FILE_CACHE["$bundle_id"]="$bundle_file"
  done < <(list_bundle_files)
  BUNDLE_FILE_CACHE_LOADED[catalog]=1
}

bundle_file_for_id() {
  local bundle_id="$1"
  load_bundle_file_cache
  if [[ -n "${BUNDLE_FILE_CACHE[$bundle_id]:-}" ]]; then
    printf '%s\n' "${BUNDLE_FILE_CACHE[$bundle_id]}"
    return 0
  fi
  return 1
}

load_bundle_descriptor() {
  local bundle_id="$1"
  local bundle_file
  bundle_file="$(bundle_file_for_id "$bundle_id")" || return 1
  unset \
    BUNDLE_ID \
    BUNDLE_INSTALLER \
    BUNDLE_SOURCE_ID \
    BUNDLE_SOURCE_IDS \
    BUNDLE_DEPENDENCIES \
    BUNDLE_ITEMS_FILE \
    BUNDLE_STOW_PACKAGES \
    BUNDLE_DESCRIPTION
  # shellcheck disable=SC1090
  source "$bundle_file"
  BUNDLE_FILE="$bundle_file"
}

bundle_installer_supported() {
  case "$1" in
    dnf|flatpak|action)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_bundle_descriptor() {
  local bundle_file="$1"

  unset \
    BUNDLE_ID \
    BUNDLE_INSTALLER \
    BUNDLE_SOURCE_ID \
    BUNDLE_SOURCE_IDS \
    BUNDLE_DEPENDENCIES \
    BUNDLE_ITEMS_FILE \
    BUNDLE_STOW_PACKAGES \
    BUNDLE_DESCRIPTION
  # shellcheck disable=SC1090
  source "$bundle_file"

  [[ -n "${BUNDLE_ID:-}" ]] || die "Missing BUNDLE_ID in $bundle_file"
  [[ "$BUNDLE_ID" =~ ^[A-Za-z0-9_.:-]+$ ]] || die "Invalid BUNDLE_ID '$BUNDLE_ID' in $bundle_file"
  [[ -n "${BUNDLE_INSTALLER:-}" ]] || die "Missing BUNDLE_INSTALLER in $bundle_file"
  [[ -n "${BUNDLE_DESCRIPTION:-}" ]] || die "Missing BUNDLE_DESCRIPTION in $bundle_file"
  bundle_installer_supported "$BUNDLE_INSTALLER" || die "Unsupported installer '$BUNDLE_INSTALLER' in $bundle_file"
  if [[ -n "${BUNDLE_ITEMS_FILE:-}" ]]; then
    [[ "$BUNDLE_ITEMS_FILE" =~ \.(pkgs|flatpaks|actions)$ ]] || die "Bundle payload file '$BUNDLE_ITEMS_FILE' must use a manifest suffix (.pkgs, .flatpaks, .actions) in $bundle_file"
    [[ -f "$ROOT_DIR/$BUNDLE_ITEMS_FILE" ]] || die "Missing bundle payload file '$BUNDLE_ITEMS_FILE' in $bundle_file"
  fi

  if [[ -n "${BUNDLE_SOURCE_ID:-}" ]]; then
    source_file_for_id "$BUNDLE_SOURCE_ID" >/dev/null || die "Unknown source ID '$BUNDLE_SOURCE_ID' in $bundle_file"
  fi
  local source_id
  while IFS= read -r source_id; do
    [[ -n "$source_id" ]] || continue
    source_file_for_id "$source_id" >/dev/null || die "Unknown source ID '$source_id' in $bundle_file"
  done < <(split_csv "${BUNDLE_SOURCE_IDS:-}")
  local dependency_id
  while IFS= read -r dependency_id; do
    [[ -n "$dependency_id" ]] || continue
    [[ "$dependency_id" != "$BUNDLE_ID" ]] || die "Bundle '$BUNDLE_ID' cannot depend on itself in $bundle_file"
    bundle_file_for_id "$dependency_id" >/dev/null || die "Unknown bundle dependency '$dependency_id' in $bundle_file"
  done < <(split_csv "${BUNDLE_DEPENDENCIES:-}")
}

validate_bundle_catalog() {
  local bundle_file
  load_bundle_file_cache
  while IFS= read -r bundle_file; do
    validate_bundle_descriptor "$bundle_file"
  done < <(list_bundle_files)
}

choice_catalog_path() {
  local category
  category="$(normalize_category_name "$1")"
  printf '%s\n' "$ROOT_DIR/choices/$category.conf"
}

validate_choice_catalog() {
  local category="$1"
  local catalog
  catalog="$(choice_catalog_path "$category")"
  [[ -f "$catalog" ]] || return 0
  local line
  local -A seen_ids=()
  local line_no=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    local without_tabs field_count
    without_tabs="${line//$'\t'/}"
    field_count=$(( ${#line} - ${#without_tabs} + 1 ))
    [[ "$field_count" -eq 5 ]] || die "Invalid catalog row at $catalog:$line_no"
    local field_line id label default_flag bundle_ids description
    field_line="${line//$'\t'/$'\x1f'}"
    IFS=$'\x1f' read -r id label default_flag bundle_ids description <<<"$field_line"
    [[ -n "$id" && -n "$label" && -n "$default_flag" && -n "$description" ]] || die "Invalid empty field in $catalog:$line_no"
    [[ "$id" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Invalid choice ID '$id' in $catalog:$line_no"
    [[ "$default_flag" == "0" || "$default_flag" == "1" ]] || die "Invalid default flag '$default_flag' in $catalog:$line_no"
    [[ -z "${seen_ids[$id]:-}" ]] || die "Duplicate choice ID '$id' in $catalog:$line_no"
    seen_ids["$id"]=1
    local bundle_id
    while IFS= read -r bundle_id; do
      [[ -z "$bundle_id" ]] && continue
      bundle_file_for_id "$bundle_id" >/dev/null || die "Unknown bundle ID '$bundle_id' in $catalog:$line_no"
      if array_contains "$bundle_id" "${BASE_BUNDLE_IDS[@]:-}"; then
        die "Base bundle '$bundle_id' must not be exposed as an optional choice in $catalog:$line_no"
      fi
    done < <(split_csv "$bundle_ids")
  done <"$catalog"
}

list_choice_catalogs() {
  find "$ROOT_DIR/choices" -maxdepth 1 -type f -name '*.conf' | sort
}

default_choice_ids() {
  local category="$1"
  local catalog
  catalog="$(choice_catalog_path "$category")"
  [[ -f "$catalog" ]] || return 0
  awk -F'\t' 'NF==5 && $1 !~ /^#/ && $3 == 1 {print $1}' "$catalog"
}

all_choice_ids() {
  local category="$1"
  local catalog
  catalog="$(choice_catalog_path "$category")"
  [[ -f "$catalog" ]] || return 0
  awk -F'\t' 'NF==5 && $1 !~ /^#/ {print $1}' "$catalog"
}

category_default_choices_enabled() {
  local category
  category="$(normalize_category_name "$1")"
  if [[ "$category" == "desktop" && "$(resolved_desktop_app_profile)" == "minimal" ]]; then
    return 1
  fi
  return 0
}

choice_record() {
  local category="$1"
  local choice_id="$2"
  local catalog
  catalog="$(choice_catalog_path "$category")"
  [[ -f "$catalog" ]] || return 1
  awk -F'\t' -v choice_id="$choice_id" 'NF==5 && $1 !~ /^#/ && $1 == choice_id {print $0}' "$catalog"
}

choice_field() {
  local line="$1"
  local field_index="$2"
  local -a fields=()
  line="${line//$'\t'/$'\x1f'}"
  IFS=$'\x1f' read -r -a fields <<<"$line"
  printf '%s\n' "${fields[$((field_index - 1))]:-}"
}

category_names() {
  find "$ROOT_DIR/choices" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort
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
  local category
  category="$(normalize_category_name "$1")"
  local -a chosen=()
  local entry
  if [[ -n "${CATEGORY_OVERRIDE_PRESENT[$category]:-}" ]]; then
    while IFS= read -r entry; do
      append_unique chosen "$entry"
    done < <(split_csv "${CATEGORY_OVERRIDES[$category]}")
  elif category_default_choices_enabled "$category"; then
    while IFS= read -r entry; do
      append_unique chosen "$entry"
    done < <(default_choice_ids "$category")
  fi
  while IFS= read -r entry; do
    append_unique chosen "$entry"
  done < <(split_csv "${CATEGORY_ADDITIONS[$category]:-}")
  printf '%s\n' "${chosen[@]:-}"
}

save_selections() {
  ensure_state_dirs
  {
    printf 'target_user=%s\n' "$TARGET_USER"
    printf 'desktop_app_profile=%s\n' "$DESKTOP_APP_PROFILE"
    printf 'preferred_browser=%s\n' "$PREFERRED_BROWSER"
    local category
    for category in $(category_names); do
      local values=()
      while IFS= read -r item; do
        [[ -n "$item" ]] && values+=("$item")
      done < <(effective_choice_ids "$category")
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
      target_user) TARGET_USER="$value" ;;
      desktop_app_profile) DESKTOP_APP_PROFILE="$value" ;;
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

normalize_category_name() {
  case "$1" in
    browser) printf 'browsers\n' ;;
    source) printf 'sources\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}
