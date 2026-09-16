#!/usr/bin/env bash
set -Eeuo pipefail

# Update mode installs no optional software from the saved selections, so
# the defaults the catalog gained since those selections were saved get a
# focused install of their own, the way `zz app install` applies one
# choice. The selections are saved once the units are in place; a failed
# install defers the new defaults to the next update instead.
module_40_new_defaults() {
  local pair category choice_id record unit
  local -a units=() closure=() labels=()
  for pair in "${NEW_DEFAULT_CHOICES[@]:-}"; do
    [[ -n "$pair" ]] || continue
    IFS=$'\t' read -r category choice_id <<<"$pair"
    record="$(choice_record "$category" "$choice_id")"
    [[ -n "$record" ]] || die "Unknown new default choice '$choice_id' in category '$category'"
    labels+=("$(category_label "$category") / $(choice_field "$record" 2)")
    while IFS= read -r unit; do
      [[ -n "$unit" ]] && append_unique units "$unit"
    done < <(split_csv "$(choice_field "$record" 4)")
  done
  if [[ "${#units[@]}" -eq 0 ]]; then
    save_selections
    return 0
  fi

  log_progress "Installing new defaults: $(join_by ', ' "${labels[@]}")"
  mapfile -t closure < <(choice_optional_units "${units[@]}")
  if [[ "${#closure[@]}" -eq 0 ]]; then
    log_info "Nothing to install: every unit of the new defaults is already part of the base install"
  else
    log_progress "Installing units: ${closure[*]}"
    if ! apply_units_focused "${closure[@]}"; then
      append_warning "New defaults were not installed and will be retried by the next update: $(join_by ', ' "${labels[@]}")"
      defer_new_default_choices
      save_selections
      return 1
    fi
  fi
  save_selections
}
