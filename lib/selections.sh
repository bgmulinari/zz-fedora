#!/usr/bin/env bash
set -Eeuo pipefail

# Selection state and persistence: per-category choice overrides/additions
# collected from the CLI or wizard, plus saved-selection round-tripping.

declare -Ag CATEGORY_OVERRIDES=()
declare -Ag CATEGORY_ADDITIONS=()
declare -Ag CATEGORY_OVERRIDE_PRESENT=()

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

category_default_choices_enabled() {
  local category
  category="$(normalize_category_name "$1")"
  if [[ "$category" == "desktop" && "$(resolved_desktop_app_profile)" == "minimal" ]]; then
    return 1
  fi
  return 0
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
  local key value
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
