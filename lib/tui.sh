#!/usr/bin/env bash
set -Eeuo pipefail

tui_require_gum() {
  have_cmd gum || die "gum is required for wizard mode"
}

tui_has_gum() {
  command -v gum >/dev/null 2>&1
}

tui_can_style() {
  [[ "${NO_TUI:-0}" -eq 0 ]] && is_tty && tui_has_gum
}

declare -ag TUI_STEP_ORDER=()
declare -Ag TUI_STEP_STATUS=()
TUI_STEP_CURRENT=0
TUI_STEP_TOTAL=0

tui_reset_steps() {
  TUI_STEP_ORDER=()
  TUI_STEP_STATUS=()
  TUI_STEP_CURRENT=0
  TUI_STEP_TOTAL=0
}

tui_register_steps() {
  local title
  tui_reset_steps
  for title in "$@"; do
    TUI_STEP_ORDER+=("$title")
    TUI_STEP_STATUS["$title"]="pending"
  done
  TUI_STEP_TOTAL="${#TUI_STEP_ORDER[@]}"
}

tui_intro() {
  clear
  local title subtitle warning banner
  title="$(gum style --bold --foreground 4 "ZZ Linux Setup")"
  subtitle="Niri + Noctalia desktop bootstrapper"
  warning="$(gum style --foreground 11 "This will install packages and manage selected user config.")"
  banner="$(printf '%s\n%s\n\n%s' "$title" "$subtitle" "$warning")"
  gum style \
    --border double \
    --border-foreground 4 \
    --align center \
    --width 72 \
    --padding "1 2" \
    "$banner"
}

tui_confirm() {
  local prompt="$1"
  if tui_can_style; then
    gum confirm --prompt.foreground "" --selected.background 12 "$prompt"
    return $?
  fi

  if ! is_tty; then
    return 1
  fi

  local reply
  read -r "?$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

tui_step_start() {
  local current="$1"
  local total="$2"
  local title="$3"
  local description="${4:-}"

  TUI_STEP_CURRENT="$current"
  TUI_STEP_TOTAL="$total"
  TUI_STEP_STATUS["$title"]="running"

  if tui_can_style; then
    printf '\n'
    gum style --bold --foreground 12 "Step $current/$total"
    gum style --bold --foreground 4 "$title"
    [[ -n "$description" ]] && gum style --faint "$description"
    return 0
  fi

  printf '\n==> [%s/%s] %s\n' "$current" "$total" "$title"
  [[ -n "$description" ]] && printf '    %s\n' "$description"
}

tui_step_done() {
  local title="$1"
  TUI_STEP_STATUS["$title"]="done"

  if tui_can_style; then
    printf '%s %s\n' "$(gum style --foreground 2 '✓')" "$title"
    return 0
  fi

  printf 'done: %s\n' "$title"
}

tui_step_failed() {
  local title="$1"
  TUI_STEP_STATUS["$title"]="error"

  if tui_can_style; then
    printf '%s %s\n' "$(gum style --foreground 1 '✗')" "$title"
    return 0
  fi

  printf 'failed: %s\n' "$title"
}

tui_step_skipped() {
  local title="$1"
  TUI_STEP_STATUS["$title"]="skipped"

  if tui_can_style; then
    printf '%s %s\n' "$(gum style --foreground 3 '○')" "$title"
    return 0
  fi

  printf 'skipped: %s\n' "$title"
}

tui_completion() {
  local message="$1"

  if tui_can_style; then
    printf '\n'
    gum style \
      --border rounded \
      --border-foreground 2 \
      --padding "0 2" \
      --bold \
      "$message"
    return 0
  fi

  printf '\n%s\n' "$message"
}

tui_count_plan_group() {
  local total=0
  local file
  for file in "$@"; do
    [[ -f "$file" ]] || continue
    total=$((total + $(count_plan_entries "$file")))
  done
  printf '%s\n' "$total"
}

tui_choice_labels_for_category() {
  local category="$1"
  local -a labels=()
  local choice_id record label

  while IFS= read -r choice_id; do
    [[ -n "$choice_id" ]] || continue
    record="$(choice_record "$DISTRO" "$category" "$choice_id")"
    [[ -n "$record" ]] || continue
    label="$(choice_field "$record" 2)"
    [[ -n "$label" ]] && labels+=("$label")
  done < <(effective_choice_ids "$DISTRO" "$category")

  join_by ", " "${labels[@]}"
}

tui_show_install_plan() {
  if ! tui_can_style; then
    print_plan_summary
    return 0
  fi

  local native_backend native_packages aur_packages flatpaks actions sources services dotfiles
  native_backend="$(native_backend_for_distro "$DISTRO")"
  native_packages="$(count_plan_entries "$(package_file_for_backend "$native_backend")")"
  aur_packages="$(count_plan_entries "$(package_file_for_backend aur)")"
  flatpaks="$(count_plan_entries "$PLAN_DIR/flatpak/apps.flatpaks")"
  actions="$(count_plan_entries "$PLAN_DIR/actions/actions.list")"
  sources="$(tui_count_plan_group "$PLAN_DIR"/sources/*.list)"
  services="$(tui_count_plan_group "$PLAN_DIR"/services/*.list)"
  dotfiles="$(count_plan_entries "$PLAN_DIR/stow/packages.list")"

  printf '\n'
  gum style --bold --foreground 4 "Install Plan"
  gum style --faint "Detailed plan: $PLAN_DIR/summary.txt"
  printf '\n'
  gum style --bold "Context"
  printf '  %s %s\n' "$(gum style --foreground 12 '→')" "Distro: ${DISTRO^}"
  printf '  %s %s\n' "$(gum style --foreground 12 '→')" "Target user: $TARGET_USER"

  printf '\n'
  gum style --bold "Selected Choices"
  local category labels
  for category in $(category_names "$DISTRO"); do
    labels="$(tui_choice_labels_for_category "$category")"
    [[ -n "$labels" ]] || continue
    printf '  %s %s: %s\n' "$(gum style --foreground 2 '+')" "$category" "$labels"
  done

  printf '\n'
  gum style --bold "Planned Actions"
  printf '  %s %s %s package%s\n' "$(gum style --foreground 2 '+')" "${native_backend^^}" "$native_packages" "$([[ "$native_packages" -eq 1 ]] && printf '' || printf 's')"
  [[ "$aur_packages" -gt 0 ]] && printf '  %s AUR %s package%s\n' "$(gum style --foreground 2 '+')" "$aur_packages" "$([[ "$aur_packages" -eq 1 ]] && printf '' || printf 's')"
  [[ "$flatpaks" -gt 0 ]] && printf '  %s Flatpak %s app%s\n' "$(gum style --foreground 2 '+')" "$flatpaks" "$([[ "$flatpaks" -eq 1 ]] && printf '' || printf 's')"
  [[ "$actions" -gt 0 ]] && printf '  %s %s custom action%s\n' "$(gum style --foreground 2 '+')" "$actions" "$([[ "$actions" -eq 1 ]] && printf '' || printf 's')"
  [[ "$sources" -gt 0 ]] && printf '  %s %s source%s\n' "$(gum style --foreground 2 '+')" "$sources" "$([[ "$sources" -eq 1 ]] && printf '' || printf 's')"
  [[ "$services" -gt 0 ]] && printf '  %s %s service action%s\n' "$(gum style --foreground 2 '+')" "$services" "$([[ "$services" -eq 1 ]] && printf '' || printf 's')"
  [[ "$dotfiles" -gt 0 ]] && printf '  %s %s dotfile package%s\n' "$(gum style --foreground 2 '+')" "$dotfiles" "$([[ "$dotfiles" -eq 1 ]] && printf '' || printf 's')"

  if [[ "${#INFO_MESSAGES[@]}" -gt 0 ]]; then
    printf '\n'
    gum style --bold "Notes"
    local info
    for info in "${INFO_MESSAGES[@]}"; do
      printf '  %s %s\n' "$(gum style --foreground 12 '•')" "$info"
    done
  fi

  if [[ "${#WARNING_MESSAGES[@]}" -gt 0 ]]; then
    printf '\n'
    gum style --bold --foreground 11 "Warnings"
    local warning
    for warning in "${WARNING_MESSAGES[@]}"; do
      printf '  %s %s\n' "$(gum style --foreground 11 '!')" "$warning"
    done
  fi
}

tui_summary() {
  local succeeded=0
  local failed=0
  local skipped=0
  local title

  for title in "${TUI_STEP_ORDER[@]:-}"; do
    case "${TUI_STEP_STATUS[$title]:-pending}" in
      done) ((++succeeded)) ;;
      error) ((++failed)) ;;
      skipped) ((++skipped)) ;;
    esac
  done

  if tui_can_style; then
    local border_color=2
    [[ "$failed" -gt 0 ]] && border_color=1

    local counts=""
    [[ "$succeeded" -gt 0 ]] && counts+="$(gum style --bold --foreground 2 '✓') $succeeded succeeded"
    [[ "$failed" -gt 0 ]] && { [[ -n "$counts" ]] && counts+="  "; counts+="$(gum style --bold --foreground 1 '✗') $failed failed"; }
    [[ "$skipped" -gt 0 ]] && { [[ -n "$counts" ]] && counts+="  "; counts+="$(gum style --bold --foreground 3 '○') $skipped skipped"; }

    printf '\n'
    gum style \
      --border rounded \
      --border-foreground "$border_color" \
      --width 70 \
      --padding "0 2" \
      --bold \
      "Setup complete!" "" "$counts"
    [[ -n "${LOG_FILE:-}" ]] && gum style --faint "log file: $LOG_FILE"
    return 0
  fi

  printf '\nSetup complete! succeeded=%s failed=%s skipped=%s\n' "$succeeded" "$failed" "$skipped"
  [[ -n "${LOG_FILE:-}" ]] && printf 'log file: %s\n' "$LOG_FILE"
}

tui_choice_option_label() {
  local label="$1"
  local description="$2"
  printf '%-30s %s' "$label" "$description"
}

tui_pick_catalog_choices() {
  local category="$1"
  local header="$2"
  local catalog
  catalog="$(choice_catalog_path "$DISTRO" "$category")"
  [[ -f "$catalog" ]] || return 0

  local -a options=()
  local -a selected_options=()
  local -A option_ids=()
  local line choice_id label default_flag description option

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    choice_id="$(choice_field "$line" 1)"
    label="$(choice_field "$line" 2)"
    default_flag="$(choice_field "$line" 3)"
    description="$(choice_field "$line" 5)"
    option="$(tui_choice_option_label "$label" "$description")"
    options+=("$option")
    option_ids["$option"]="$choice_id"
    [[ "$default_flag" == "1" ]] && selected_options+=("$option")
  done <"$catalog"

  [[ "${#options[@]}" -gt 0 ]] || return 0

  local -a choose_args=(
    choose
    --no-limit
    --header "$header"
    --header.foreground ""
    --height 999
    --selected.foreground 2
    --cursor.foreground ""
  )
  if [[ "${#selected_options[@]}" -gt 0 ]]; then
    choose_args+=(--selected "$(join_by , "${selected_options[@]}")")
  fi

  local chosen
  chosen="$(gum "${choose_args[@]}" "${options[@]}")" || return 0
  if [[ -z "$chosen" ]]; then
    printf '__empty__\n'
    return 0
  fi

  while IFS= read -r option; do
    [[ -n "$option" ]] && printf '%s\n' "${option_ids[$option]}"
  done <<<"$chosen"
}

tui_run_wizard() {
  [[ "$NO_TUI" -eq 1 ]] && die "Wizard mode was requested with --no-tui. Use install --yes instead."
  is_tty || die "Wizard mode requires an interactive TTY. Use install --yes or print-plan instead."
  tui_require_gum
  tui_intro
  normalize_distro
  gum style --bold "Detected distro: ${DISTRO^}"
  gum style --faint "Install target user: $TARGET_USER"

  local -a browser_choices=()
  local -a category_choices=()

  local browser_header="Select browser(s). Space toggles, Enter continues."
  if [[ "$DISTRO" == "arch" ]]; then
    browser_header="Select browser(s). Firefox is the default. Space toggles, Enter continues."
  fi
  mapfile -t browser_choices < <(tui_pick_catalog_choices "browsers" "$browser_header" || true)
  if [[ "${#browser_choices[@]}" -gt 0 ]]; then
    if [[ "${browser_choices[0]}" == "__empty__" ]]; then
      set_category_override "browsers" ""
      browser_choices=()
    else
      set_category_override "browsers" "$(join_by , "${browser_choices[@]}")"
    fi
  fi

  local category header
  for category in ai dev dotnet office gaming media; do
    header="Select ${category} components. Space toggles, Enter continues."
    mapfile -t category_choices < <(tui_pick_catalog_choices "$category" "$header" || true)
    if [[ "${#category_choices[@]}" -gt 0 ]]; then
      if [[ "${category_choices[0]}" == "__empty__" ]]; then
        set_category_override "$category" ""
      else
        set_category_override "$category" "$(join_by , "${category_choices[@]}")"
      fi
    fi
  done

  if [[ "${#browser_choices[@]}" -gt 1 ]]; then
    local -a preferred_browser_options=()
    local browser_id record label description
    for browser_id in "${browser_choices[@]}"; do
      record="$(choice_record "$DISTRO" "browsers" "$browser_id")"
      label="$(choice_field "$record" 2)"
      description="$(choice_field "$record" 5)"
      preferred_browser_options+=("$(tui_choice_option_label "$label" "$description")")
    done
    local preferred_label
    preferred_label="$(gum choose \
      --header "Choose the default browser." \
      --header.foreground "" \
      --height 999 \
      --cursor.foreground "" \
      "${preferred_browser_options[@]}")"
    local index=0
    for index in "${!preferred_browser_options[@]}"; do
      if [[ "${preferred_browser_options[$index]}" == "$preferred_label" ]]; then
        PREFERRED_BROWSER="${browser_choices[$index]}"
        break
      fi
    done
  fi
}
