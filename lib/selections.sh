#!/usr/bin/env bash
set -Eeuo pipefail

# Selection state and persistence: per-category choice overrides/additions
# collected from the CLI or wizard, plus saved-selection round-tripping.

declare -Ag CATEGORY_OVERRIDES=()
declare -Ag CATEGORY_ADDITIONS=()
declare -Ag CATEGORY_OVERRIDE_PRESENT=()
# The choices the catalog offered in each category when the selections were
# saved (the offered.<category> lines), so a later update can tell a default
# the user never saw from one they declined.
declare -Ag CATEGORY_OFFERED=()
declare -Ag CATEGORY_OFFERED_PRESENT=()
# "category<TAB>choice" pairs: the new defaults update mode selected for
# this run, and the ones whose install failed and stay unrecorded so the
# next update offers them again.
declare -ag NEW_DEFAULT_CHOICES=()
declare -ag DEFERRED_DEFAULT_CHOICES=()

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
    for category in $(category_names); do
      local offered=()
      while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        array_contains "$category"$'\t'"$item" "${DEFERRED_DEFAULT_CHOICES[@]:-}" && continue
        offered+=("$item")
      done < <(all_choice_ids "$category")
      printf 'offered.%s=%s\n' "$category" "$(join_by , "${offered[@]:-}")"
    done
  } >"$SAVED_SELECTIONS"
}

load_saved_selections() {
  [[ -f "$SAVED_SELECTIONS" ]] || die "Saved selections not found at $SAVED_SELECTIONS"
  local key value category
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ -z "$key" ]] && continue
    case "$key" in
      target_user) TARGET_USER="$value" ;;
      desktop_app_profile) DESKTOP_APP_PROFILE="$value" ;;
      preferred_browser) PREFERRED_BROWSER="$value" ;;
      select.*)
        set_category_override "${key#select.}" "$value"
        ;;
      offered.*)
        category="$(normalize_category_name "${key#offered.}")"
        CATEGORY_OFFERED["$category"]="$value"
        CATEGORY_OFFERED_PRESENT["$category"]=1
        ;;
    esac
  done <"$SAVED_SELECTIONS"
}

normalize_saved_selections_for_update() {
  [[ "$UPDATE_MODE" -eq 1 ]] || return 0
  catalog_ensure_loaded

  local category choice_id record
  local -a valid_choices=()
  local -A current_categories=()
  while IFS= read -r category; do
    [[ -n "$category" ]] && current_categories["$category"]=1
  done < <(category_names)

  for category in "${!CATEGORY_OVERRIDE_PRESENT[@]}"; do
    [[ -n "${CATEGORY_OVERRIDE_PRESENT[$category]:-}" ]] || continue
    if [[ -z "${current_categories[$category]:-}" ]]; then
      log_warn "Saved selection category '$category' is no longer available and was removed."
      CATEGORY_OVERRIDES["$category"]=""
      CATEGORY_OVERRIDE_PRESENT["$category"]=""
      continue
    fi

    valid_choices=()
    while IFS= read -r choice_id; do
      [[ -n "$choice_id" ]] || continue
      record="$(choice_record "$category" "$choice_id" || true)"
      if [[ -n "$record" ]]; then
        valid_choices+=("$choice_id")
      else
        log_warn "Saved choice '$choice_id' in category '$category' is no longer available and was removed."
      fi
    done < <(split_csv "${CATEGORY_OVERRIDES[$category]}")
    CATEGORY_OVERRIDES["$category"]="$(join_by , "${valid_choices[@]:-}")"
  done

  if [[ -n "$PREFERRED_BROWSER" ]] &&
    [[ -z "$(choice_record browsers "$PREFERRED_BROWSER" || true)" ]]; then
    log_warn "Saved preferred browser '$PREFERRED_BROWSER' is no longer available and was removed."
    PREFERRED_BROWSER=""
  fi

  select_new_default_choices
}

# Selects the defaults the catalog gained since the selections were saved.
# A category's offered list records what the catalog had at the time, so a
# default outside it was never declined; it joins the selection and
# modules/40-new-defaults.sh installs it. A saved category without an
# offered list says nothing about what was declined, so nothing is added to
# it; a category the file does not know at all takes its defaults through
# effective_choice_ids already. A nested default stays out while its
# parent is unselected: the parent was offered and not taken.
select_new_default_choices() {
  local category choice_id parent
  local -a offered=() selected=()
  NEW_DEFAULT_CHOICES=()
  for category in $(category_names); do
    [[ -n "${CATEGORY_OVERRIDE_PRESENT[$category]:-}" ]] || continue
    [[ -n "${CATEGORY_OFFERED_PRESENT[$category]:-}" ]] || continue
    category_default_choices_enabled "$category" || continue
    mapfile -t offered < <(split_csv "${CATEGORY_OFFERED[$category]}")
    mapfile -t selected < <(effective_choice_ids "$category")
    while IFS= read -r choice_id; do
      [[ -n "$choice_id" ]] || continue
      array_contains "$choice_id" "${offered[@]:-}" && continue
      array_contains "$choice_id" "${selected[@]:-}" && continue
      parent="$(choice_parent_id "$category" "$choice_id")"
      if [[ -n "$parent" ]] && ! array_contains "$parent" "${selected[@]:-}"; then
        log_info "New default choice '$choice_id' in category '$category' stays unselected because its parent '$parent' is not selected."
        continue
      fi
      log_info "New default choice '$choice_id' in category '$category' was added to the saved selections."
      add_category_selection "$category" "$choice_id"
      NEW_DEFAULT_CHOICES+=("$category"$'\t'"$choice_id")
      selected+=("$choice_id")
    done < <(default_choice_ids "$category")
  done
}

# Takes the new defaults out of the selection again and keeps them off the
# offered lists, so an update whose install of them failed does not
# remember them as done: the next update selects and installs them again.
defer_new_default_choices() {
  local pair category choice_id
  local -a kept=() removed=()
  local -A dropped=()
  for pair in "${NEW_DEFAULT_CHOICES[@]:-}"; do
    [[ -n "$pair" ]] || continue
    IFS=$'\t' read -r category choice_id <<<"$pair"
    dropped["$category"]+="${dropped[$category]:+,}$choice_id"
    DEFERRED_DEFAULT_CHOICES+=("$pair")
  done
  for category in "${!dropped[@]}"; do
    mapfile -t removed < <(split_csv "${dropped[$category]}")
    kept=()
    while IFS= read -r choice_id; do
      [[ -n "$choice_id" ]] || continue
      array_contains "$choice_id" "${removed[@]}" && continue
      kept+=("$choice_id")
    done < <(split_csv "${CATEGORY_ADDITIONS[$category]:-}")
    CATEGORY_ADDITIONS["$category"]="$(join_by , "${kept[@]:-}")"
  done
  NEW_DEFAULT_CHOICES=()
}
