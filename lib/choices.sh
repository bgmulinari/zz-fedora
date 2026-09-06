#!/usr/bin/env bash
set -Eeuo pipefail

# Per-choice install and removal: the installer commands behind `zz app`.
# A choice is one row of a wizard category (dev/zed). Adding one applies
# only that choice's units, with their dependencies, sources, packages,
# and actions, and then converges managed configuration; removing one
# takes away what no remaining unit still needs. Both rewrite the saved
# selections once the change is in place, so a later `zz update zz` keeps
# it.

# Category ids carry no labels in the catalog; these are the names the
# CLI table and the desktop menu show.
category_label() {
  case "$1" in
    ai) printf 'AI\n' ;;
    browsers) printf 'Browsers\n' ;;
    desktop) printf 'Desktop apps\n' ;;
    dev) printf 'Development\n' ;;
    dotnet) printf '.NET\n' ;;
    gaming) printf 'Gaming\n' ;;
    media) printf 'Media\n' ;;
    office) printf 'Office\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# resolve_choice_ref <ref> prints "category<TAB>choice". A ref is
# category/choice, category=choice, or a bare choice id when that id exists
# in exactly one category.
resolve_choice_ref() {
  local ref="$1" category="" choice="" record
  catalog_ensure_loaded
  case "$ref" in
    */*)
      category="${ref%%/*}"
      choice="${ref#*/}"
      ;;
    *=*)
      category="${ref%%=*}"
      choice="${ref#*=}"
      ;;
    *)
      choice="$ref"
      ;;
  esac
  [[ -n "$choice" ]] || die "Empty choice reference"
  if [[ -n "$category" ]]; then
    category="$(normalize_category_name "$category")"
    record="$(choice_record "$category" "$choice" || true)"
    [[ -n "$record" ]] || die "Unknown choice '$choice' in category '$category' (see zz app list)"
    printf '%s\t%s\n' "$category" "$choice"
    return 0
  fi
  local -a matches=()
  for category in $(category_names); do
    record="$(choice_record "$category" "$choice" || true)"
    [[ -n "$record" ]] && matches+=("$category")
  done
  case "${#matches[@]}" in
    0) die "Unknown choice '$choice' (see zz app list)" ;;
    1) printf '%s\t%s\n' "${matches[0]}" "$choice" ;;
    *) die "Choice '$choice' exists in several categories (${matches[*]}); use <category>/$choice" ;;
  esac
}

# The units a choice selects directly (its unit plus any `also` units).
choice_unit_ids() {
  local record
  record="$(choice_record "$1" "$2" || true)"
  [[ -n "$record" ]] || return 1
  split_csv "$(choice_field "$record" 4)"
}

# The given units with their dependencies, minus the base and default units
# every install carries already.
choice_optional_units() {
  local -a units=("$@") always=()
  local unit
  expand_bundle_dependencies units
  mapfile -t always < <(effective_base_bundle_ids)
  for unit in "${units[@]:-}"; do
    [[ -n "$unit" ]] || continue
    array_contains "$unit" "${always[@]:-}" "${DEFAULT_BUNDLE_IDS[@]:-}" && continue
    printf '%s\n' "$unit"
  done
}

# Installed-state lookups ask each package manager once per process and
# answer from the result: the listing checks every catalog item, and one
# rpm, flatpak, or Homebrew login shell per item takes seconds.
CHOICE_STATE_PRIMED=0
declare -Ag INSTALLED_RPM_NAMES=()
declare -Ag INSTALLED_FLATPAK_IDS=()
declare -Ag INSTALLED_BREW_FORMULAE=()
declare -Ag INSTALLED_NPM_GLOBALS=()

prime_choice_state() {
  [[ "$CHOICE_STATE_PRIMED" -eq 0 ]] || return 0
  CHOICE_STATE_PRIMED=1
  local name
  if have_cmd rpm; then
    while IFS= read -r name; do
      [[ -n "$name" ]] && INSTALLED_RPM_NAMES["$name"]=1
    done < <(rpm -qa --queryformat '%{NAME}\n' 2>/dev/null || true)
  fi
  if have_cmd flatpak; then
    while IFS= read -r name; do
      [[ -n "$name" ]] && INSTALLED_FLATPAK_IDS["$name"]=1
    done < <({ flatpak list --system --app --columns=application 2>/dev/null; flatpak list --user --app --columns=application 2>/dev/null; } || true)
  fi
  if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
    while IFS= read -r name; do
      [[ -n "$name" ]] && INSTALLED_BREW_FORMULAE["$name"]=1
    done < <("$BREW_PREFIX/bin/brew" list --formula -1 2>/dev/null || true)
  fi
  if have_cmd npm; then
    while IFS= read -r name; do
      [[ -n "$name" ]] && INSTALLED_NPM_GLOBALS["$name"]=1
    done < <(npm ls -g --depth=0 --parseable --long 2>/dev/null | awk -F: 'NR > 1 && NF > 1 { sub(/@[^@]*$/, "", $2); print $2 }' || true)
  fi
}

rpm_name_installed() {
  [[ -n "${INSTALLED_RPM_NAMES[$(rpm_spec_name "$1")]:-}" ]]
}

# Whether an action's verifier passes now. Unlike verify_custom_action this
# ignores DRY_RUN: it reports state instead of gating an install. Homebrew
# and npm actions answer from the primed lists instead of their verifiers,
# which shell out per package.
action_present() {
  local action="$1" verify_fn
  split_action_id "$action"
  case "$ACTION_DISPATCH_ID" in
    brew)
      prime_choice_state
      [[ -n "${INSTALLED_BREW_FORMULAE[$ACTION_DISPATCH_ARG]:-}" ]]
      return
      ;;
    npm-global)
      prime_choice_state
      [[ -n "${INSTALLED_NPM_GLOBALS[$ACTION_DISPATCH_ARG]:-}" ]]
      return
      ;;
  esac
  verify_fn="${ACTION_VERIFY_FN[$ACTION_DISPATCH_ID]:-}"
  [[ -n "$verify_fn" ]] || return 0
  if [[ "$action" == *:* ]]; then
    "$verify_fn" "$ACTION_DISPATCH_ARG"
  else
    "$verify_fn"
  fi
}

choice_item_present() {
  local backend="$1" item="$2"
  case "$backend" in
    dnf)
      # The primed names answer most items; groups, arch-qualified specs,
      # and virtual provides fall through to the installer's own check.
      prime_choice_state
      rpm_name_installed "$item" || fedora_package_installed "$item"
      ;;
    flatpak)
      prime_choice_state
      [[ -n "${INSTALLED_FLATPAK_IDS[$item]:-}" ]]
      ;;
    action) action_present "$item" ;;
    *) return 1 ;;
  esac
}

unit_installed() {
  local unit="$1" step_index backend _sources item
  while IFS=$'\t' read -r step_index backend _sources; do
    [[ -n "$step_index" ]] || continue
    while IFS= read -r item; do
      [[ -n "$item" ]] || continue
      choice_item_present "$backend" "$item" || return 1
    done < <(bundle_step_items "$unit" "$step_index")
  done < <(bundle_steps "$unit")
  return 0
}

# Installed when every payload item of every unit the choice selects is
# present; dependencies are not consulted, they belong to other choices or
# to the base.
units_installed() {
  local unit
  for unit in "$@"; do
    [[ -n "$unit" ]] || continue
    unit_installed "$unit" || return 1
  done
  return 0
}

choice_installed() {
  local -a units=()
  mapfile -t units < <(choice_unit_ids "$1" "$2")
  units_installed "${units[@]:-}"
}

# Every catalog choice with its saved-selection and installed state, as a
# JSON array; `zz app list` and the desktop menu read this.
print_choices_json() {
  local category choice_id label default_flag units description
  local first=1 selected installed unit units_json
  local -a selected_ids=() unit_ids=()
  # Loaded here, in this shell: the lookups below run in command and process
  # substitutions, and a catalog first loaded inside one of those is loaded
  # again by every one that follows.
  catalog_ensure_loaded
  printf '['
  for category in $(category_names); do
    mapfile -t selected_ids < <(effective_choice_ids "$category")
    while IFS=$'\t' read -r choice_id label default_flag units description; do
      [[ -n "$choice_id" ]] || continue
      selected=false
      array_contains "$choice_id" "${selected_ids[@]:-}" && selected=true
      mapfile -t unit_ids < <(split_csv "$units")
      installed=false
      units_installed "${unit_ids[@]:-}" && installed=true
      units_json=""
      for unit in "${unit_ids[@]:-}"; do
        [[ -n "$unit" ]] || continue
        units_json+="${units_json:+,}\"$(json_escape "$unit")\""
      done
      [[ "$first" -eq 1 ]] || printf ','
      first=0
      printf '{"category":"%s","category_label":"%s","id":"%s","label":"%s","description":"%s","default":%s,"selected":%s,"installed":%s,"units":[%s]}' \
        "$(json_escape "$category")" \
        "$(json_escape "$(category_label "$category")")" \
        "$(json_escape "$choice_id")" \
        "$(json_escape "$label")" \
        "$(json_escape "$description")" \
        "$([[ "$default_flag" == "1" ]] && printf 'true' || printf 'false')" \
        "$selected" \
        "$installed" \
        "$units_json"
    done <"$(choice_catalog_path "$category")"
  done
  printf ']\n'
}

# The --select values of add-choice and remove-choice, one
# "category<TAB>choice" per line.
requested_choice_pairs() {
  local category choice
  for category in "${!CATEGORY_ADDITIONS[@]}"; do
    while IFS= read -r choice; do
      [[ -n "$choice" ]] && printf '%s\t%s\n' "$category" "$choice"
    done < <(split_csv "${CATEGORY_ADDITIONS[$category]}")
  done
}

# Validates the requested pairs and collects their units into the array
# named by $1.
collect_requested_choice_units() {
  # shellcheck disable=SC2034  # Filled through append_unique by name.
  local -n units_ref="$1"
  local verb="$2"
  local -a pairs=()
  local pair category choice record unit
  mapfile -t pairs < <(requested_choice_pairs)
  [[ "${#pairs[@]}" -gt 0 ]] || die "$COMMAND needs at least one --select category=choice"
  for pair in "${pairs[@]}"; do
    IFS=$'\t' read -r category choice <<<"$pair"
    record="$(choice_record "$category" "$choice" || true)"
    [[ -n "$record" ]] || die "Unknown choice '$choice' in category '$category' (see zz app list)"
    log_info "$verb $(category_label "$category") choice: $(choice_field "$record" 2)"
    while IFS= read -r unit; do
      [[ -n "$unit" ]] && append_unique units_ref "$unit"
    done < <(split_csv "$(choice_field "$record" 4)")
  done
}

# Runs the install steps for these units only, from a plan built beside the
# full one, so one choice never re-runs the whole package transaction: the
# optional-software modules read only PLAN_DIR, so they run unchanged on the
# focused plan. The full plan (already built from the updated selections)
# comes back as PLAN_DIR afterwards.
apply_units_focused() {
  local full_plan_dir="$PLAN_DIR" focus_dir unit backend source_id status=0
  local -a plan_sources=() plan_backends=()
  focus_dir="$(mktemp -d "$CACHE_DIR/choice-plan.XXXXXX")"
  PLAN_DIR="$focus_dir"
  plan_reset
  for unit in "$@"; do
    append_bundle_to_plan "$unit" plan_sources plan_backends
  done
  for backend in "${plan_backends[@]:-}"; do
    [[ -n "$backend" ]] && append_backend_prereqs "$backend"
  done
  for source_id in "${plan_sources[@]:-}"; do
    [[ -n "$source_id" ]] && append_plan_source "$source_id"
  done
  normalize_plan_files
  install_focused_plan || status=$?
  PLAN_DIR="$full_plan_dir"
  rm -rf "$focus_dir"
  return "$status"
}

install_focused_plan() {
  module_05_bootstrap_tools || return 1
  module_10_sources || return 1
  module_32_optional_packages
  module_35_custom_actions
}

# The saved selections record what is installed, so a choice is written
# there once its units are in place: a change that fails halfway is not
# remembered as done, since `zz update zz` never installs optional software.
save_choice_selections() {
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  save_selections
}

apply_choice_additions() {
  local -a units=() closure=()
  collect_requested_choice_units units "Adding"
  # The full plan from the saved selections plus the additions. Its planner
  # warnings describe the whole install, not this change.
  build_plan_from_selections
  WARNING_MESSAGES=()
  mapfile -t closure < <(choice_optional_units "${units[@]}")
  if [[ "${#closure[@]}" -eq 0 ]]; then
    log_info "Nothing to install: every unit of this choice is already part of the base install"
  else
    log_progress "Installing units: ${closure[*]}"
    apply_units_focused "${closure[@]}" || return 1
  fi
  save_choice_selections
  log_progress "Converging managed configuration and desktop defaults"
  module_60_user_config
  module_80_post_actions
}

# Removes the product links of a managed-config component when they point
# into this checkout; seeded user-owned files stay.
remove_component_product_links() {
  local component="$1" row_component path mode _rest target root_real
  # Both sides resolved: the checkout path may itself go through a symlink.
  root_real="$(readlink -f "$ROOT_DIR")"
  load_managed_config_policy_cache
  while IFS=$'\t' read -r row_component path mode _rest || [[ -n "$row_component" ]]; do
    [[ "$row_component" == "$component" && "$mode" == "product-link" ]] || continue
    target="$(managed_config_target_path "$path")"
    [[ -L "$target" ]] || continue
    case "$(readlink -f "$target" 2>/dev/null || true)" in
      "$root_real"/*)
        log_info "Removing product link: $target"
        run_cmd_as_user "$TARGET_USER" rm -f "$target"
        ;;
    esac
  done <"$(managed_config_policy_file)"
}

remove_choice_action() {
  local action="$1" package
  split_action_id "$action"
  case "$ACTION_DISPATCH_ID" in
    brew)
      package="$ACTION_DISPATCH_ARG"
      log_progress "Removing Homebrew package: $package"
      run_user_login_shell "brew list '$package' >/dev/null 2>&1 && brew uninstall '$package' || true"
      ;;
    npm-global)
      package="$ACTION_DISPATCH_ARG"
      log_progress "Removing npm global package: $package"
      run_cmd_as_root npm uninstall -g "$package"
      ;;
    *)
      return 1
      ;;
  esac
}

apply_choice_removals() {
  local -a units=() closure=() dnf_remove=() flatpak_remove=() leftovers=() selected_now=() kept_choices=()
  local -A removed_by_category=()
  local pair category choice unit step_index backend _sources item component plugin_id
  local service_kind service_unit _service_parent
  collect_requested_choice_units units "Removing"

  while IFS=$'\t' read -r category choice; do
    removed_by_category["$category"]+="${removed_by_category[$category]:+,}$choice"
  done < <(requested_choice_pairs)
  # The requested choices came in as additions; from here on the selection
  # is the saved one minus them.
  CATEGORY_ADDITIONS=()
  local -a removed=()
  for category in "${!removed_by_category[@]}"; do
    mapfile -t selected_now < <(effective_choice_ids "$category")
    mapfile -t removed < <(split_csv "${removed_by_category[$category]}")
    kept_choices=()
    for choice in "${selected_now[@]:-}"; do
      [[ -n "$choice" ]] || continue
      array_contains "$choice" "${removed[@]}" && continue
      kept_choices+=("$choice")
    done
    for choice in "${removed[@]}"; do
      array_contains "$choice" "${selected_now[@]:-}" ||
        log_warn "Choice '$choice' was not in the saved $category selection; removing whatever of it is installed"
      if [[ "$category" == "browsers" && "$PREFERRED_BROWSER" == "$choice" ]]; then
        log_warn "Removing the preferred browser; run zz defaults after choosing another"
        PREFERRED_BROWSER=""
      fi
    done
    set_category_override "$category" "$(join_by , "${kept_choices[@]:-}")"
  done

  # The full plan of what stays.
  build_plan_from_selections
  WARNING_MESSAGES=()
  mapfile -t closure < <(choice_optional_units "${units[@]}")

  for unit in "${closure[@]:-}"; do
    [[ -n "$unit" ]] || continue
    if plan_file_has_entry "$PLAN_DIR/bundles.list" "$unit"; then
      log_info "Keeping unit still selected elsewhere: $unit"
      continue
    fi
    while IFS=$'\t' read -r step_index backend _sources; do
      [[ -n "$step_index" ]] || continue
      while IFS= read -r item; do
        [[ -n "$item" ]] || continue
        case "$backend" in
          dnf)
            if plan_file_has_entry "$PLAN_DIR/packages/dnf.pkgs" "$item" || plan_file_has_entry "$PLAN_DIR/prereqs/dnf.pkgs" "$item"; then
              log_info "Keeping package still planned: $item"
            elif [[ "$item" == @* ]]; then
              leftovers+=("package group $item")
            elif [[ "$DRY_RUN" -eq 1 ]] || fedora_package_installed "$item"; then
              append_unique dnf_remove "$item"
            fi
            ;;
          flatpak)
            if plan_file_has_entry "$PLAN_DIR/flatpak/apps.flatpaks" "$item"; then
              log_info "Keeping Flatpak still planned: $item"
            elif [[ "$DRY_RUN" -eq 1 ]] || choice_item_present flatpak "$item"; then
              append_unique flatpak_remove "$item"
            fi
            ;;
          action)
            if plan_file_has_entry "$PLAN_DIR/actions/actions.list" "$item"; then
              log_info "Keeping action still planned: $item"
            elif ! remove_choice_action "$item"; then
              leftovers+=("action $item")
            fi
            ;;
        esac
      done < <(bundle_step_items "$unit" "$step_index")
    done < <(bundle_steps "$unit")

    while IFS=$'\t' read -r service_kind service_unit _service_parent; do
      [[ "$service_kind" == "enable" ]] || continue
      plan_file_has_entry "$PLAN_DIR/services/user-enable.list" "$service_unit" && continue
      log_progress "Disabling user service: $service_unit"
      run_cmd_as_user "$TARGET_USER" systemctl --user disable --now "$service_unit" || true
    done < <(bundle_user_services "$unit")

    load_bundle_descriptor "$unit" || continue
    while IFS= read -r component; do
      [[ -n "$component" ]] || continue
      plan_file_has_entry "$PLAN_DIR/config/components.list" "$component" && continue
      # A DMS plugin is unloaded and forgotten while its directory is still
      # linked, so the shell neither lists a vanished widget nor keeps an
      # enablement a later re-add would find already present.
      while IFS= read -r plugin_id; do
        [[ -n "$plugin_id" ]] && dms_forget_plugin "$plugin_id"
      done < <(dms_component_plugin_ids "$component")
      remove_component_product_links "$component"
    done < <(split_csv "${BUNDLE_CONFIG_COMPONENTS:-}")
  done

  if [[ "${#dnf_remove[@]}" -gt 0 ]]; then
    log_progress "Removing native packages: ${dnf_remove[*]}"
    run_cmd_as_root dnf remove -y "${dnf_remove[@]}"
  fi
  for item in "${flatpak_remove[@]:-}"; do
    [[ -n "$item" ]] || continue
    log_progress "Removing Flatpak: $item"
    run_cmd_as_root flatpak uninstall -y "$item" || log_warn "Flatpak removal failed: $item"
  done
  save_choice_selections
  if [[ "${#leftovers[@]}" -gt 0 ]]; then
    log_warn "Left in place, no automatic removal exists for: $(join_by ', ' "${leftovers[@]}")"
  fi
  if [[ -n "${removed_by_category[browsers]:-}" ]]; then
    log_info "Run zz defaults to reapply the default browser and file associations"
  fi
}

print_choice_change_summary() {
  local verb="$1" message
  printf '\n'
  if [[ "${#WARNING_MESSAGES[@]}" -gt 0 ]]; then
    printf 'Choice %s with warnings:\n' "$verb"
    for message in "${WARNING_MESSAGES[@]}"; do
      printf -- '- %s\n' "$message"
    done
  else
    printf 'Choice %s.\n' "$verb"
  fi
  printf 'Saved selections: %s\n' "$SAVED_SELECTIONS"
}
