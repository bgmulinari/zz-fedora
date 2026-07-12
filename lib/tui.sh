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
TUI_PROGRESS_RENDER_ACTIVE=0
TUI_PROGRESS_HEIGHT=0
TUI_PROGRESS_STEPS_ROW=0
TUI_BANNER_HEIGHT=0

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

tui_progress_enabled() {
  [[ "${TUI_PROGRESS_ACTIVE:-0}" -eq 1 && "${DRY_RUN:-0}" -eq 0 && -n "${LOG_FILE:-}" ]] && tui_can_style
}

tui_ansi() {
  local code="$1"
  local value="$2"
  printf '\033[%sm%s\033[0m' "$code" "$value"
}

tui_banner() {
  local title subtitle warning banner
  title="$(gum style --bold --foreground 4 "ZZ Fedora")"
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

tui_progress_line() {
  local title="$1"
  local status="${TUI_STEP_STATUS[$title]:-pending}"
  case "$status" in
    done) printf '%s %s\n' "$(tui_ansi 32 '✓')" "$title" ;;
    error) printf '%s %s\n' "$(tui_ansi 31 '✗')" "$title" ;;
    skipped) printf '%s %s\n' "$(tui_ansi 33 '○')" "$title" ;;
    running) printf '%s %s\n' "$(tui_ansi 34 '...')" "$(tui_ansi 34 "$title")" ;;
    *) printf '  %s\n' "$title" ;;
  esac
}

tui_progress_render() {
  [[ "$TUI_PROGRESS_RENDER_ACTIVE" -eq 1 ]] || return 0

  printf '\033[s'
  printf '\033[1;1H'
  tui_banner
  printf '\033[2K\n'
  printf '\033[2K%s\n' "$(tui_ansi '1' "Installing selected steps... this may take some time. Please wait!")"
  printf '\033[2K\n'
  printf '\033[u'
}

tui_progress_render_steps() {
  [[ "$TUI_PROGRESS_RENDER_ACTIVE" -eq 1 ]] || return 0

  local width separator step
  width="${COLUMNS:-80}"
  separator="$(printf '%*s' "$width" '' | tr ' ' '-')"

  printf '\033[s'
  printf '\033[%s;1H' "$TUI_PROGRESS_STEPS_ROW"
  for step in "${TUI_STEP_ORDER[@]:-}"; do
    printf '\033[2K'
    tui_progress_line "$step"
  done
  printf '\033[2K\n'
  printf '\033[2K%s\n' "$(tui_ansi 2 "$separator")"
  printf '\033[u'
}

tui_progress_begin() {
  tui_progress_enabled || return 0

  local rows top
  rows="${LINES:-$(tput lines 2>/dev/null || printf '24')}"
  TUI_BANNER_HEIGHT="$(tui_banner | wc -l | awk '{print $1}')"
  TUI_PROGRESS_STEPS_ROW="$((TUI_BANNER_HEIGHT + 4))"
  TUI_PROGRESS_HEIGHT="$((TUI_BANNER_HEIGHT + ${#TUI_STEP_ORDER[@]} + 5))"
  top="$((TUI_PROGRESS_HEIGHT + 1))"

  if [[ "$rows" -le "$((top + 2))" ]]; then
    return 0
  fi

  clear
  printf '\033[?25l'
  TUI_PROGRESS_RENDER_ACTIVE=1
  tui_progress_render
  tui_progress_render_steps
  printf '\033[%s;%sr' "$top" "$rows"
  printf '\033[%s;1H' "$top"
}

tui_progress_end() {
  [[ "$TUI_PROGRESS_RENDER_ACTIVE" -eq 1 ]] || return 0

  local rows
  rows="${LINES:-$(tput lines 2>/dev/null || printf '24')}"

  printf '\033[r'
  printf '\033[?25h'
  printf '\033[%s;1H\n' "$rows"
  TUI_PROGRESS_RENDER_ACTIVE=0
}

tui_sanitize_output_stream() {
  awk '{
    gsub(/\r/, "\n")
    gsub(/\033\[[0-?]*[ -\/]*[@-ln-~]/, "")
    print
    fflush()
  }'
}

tui_run_with_log_capture() {
  [[ "$TUI_PROGRESS_RENDER_ACTIVE" -eq 1 && -n "${LOG_FILE:-}" ]] || {
    run_with_log_capture tee "$@"
    return $?
  }

  local step_status
  set +e
  (
    export LOG_CAPTURE_MODE=tee
    "$@"
  ) 2>&1 | tee -a "$LOG_FILE" | tui_sanitize_output_stream
  step_status="${PIPESTATUS[0]}"
  set -e
  return "$step_status"
}

tui_intro() {
  clear
  tui_banner
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

  tui_progress_render_steps

  if tui_can_style; then
    return 0
  fi

  printf '\n==> [%s/%s] %s\n' "$current" "$total" "$title"
  [[ -n "$description" ]] && printf '    %s\n' "$description"
}

tui_step_spin() {
  local current="$1"
  local total="$2"
  local title="$3"
  local status_file="$4"

  gum spin \
    --spinner points \
    --spinner.foreground 2 \
    --title.foreground 4 \
    --title "$title ($current/$total)" \
    -- bash -c 'while [[ ! -f "$1" ]]; do sleep 0.2; done' _ "$status_file"
}

tui_step_done() {
  local title="$1"
  TUI_STEP_STATUS["$title"]="done"

  if [[ "$TUI_PROGRESS_RENDER_ACTIVE" -eq 1 ]]; then
    tui_progress_render_steps
    return 0
  fi

  if tui_can_style; then
    printf '%s %s\n' "$(gum style --foreground 2 ' ✓')" "$title"
    return 0
  fi

  printf 'done: %s\n' "$title"
}

tui_step_failed() {
  local title="$1"
  TUI_STEP_STATUS["$title"]="error"

  if [[ "$TUI_PROGRESS_RENDER_ACTIVE" -eq 1 ]]; then
    tui_progress_render_steps
    return 0
  fi

  if tui_can_style; then
    printf '%s %s\n' "$(gum style --foreground 1 ' ✗')" "$title"
    return 0
  fi

  printf 'failed: %s\n' "$title"
}

tui_failure_log_tail() {
  [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]] || return 0
  printf '\nLast log lines:\n'
  tail -n "${FAILURE_LOG_TAIL_LINES:-20}" "$LOG_FILE" || true
}

tui_failure_context() {
  local label="$1"
  local exit_code="$2"
  printf '\nRequired step failed: %s\n' "$label" >&2
  printf 'Exit code: %s\n' "$exit_code" >&2
  [[ -n "${LAST_COMMAND_CONTEXT:-}" ]] && printf 'Last command: %s\n' "$LAST_COMMAND_CONTEXT" >&2
  [[ -n "${LOG_FILE:-}" ]] && printf 'Log file: %s\n' "$LOG_FILE" >&2
  tui_failure_log_tail >&2
  if declare -F print_readiness_warnings_for_failure >/dev/null 2>&1; then
    print_readiness_warnings_for_failure
  fi
}

tui_required_failure_action() {
  local label="$1"
  local exit_code="$2"
  local progress_was_active=0
  [[ "${ASSUME_YES:-0}" -ne 1 && "${DRY_RUN:-0}" -eq 0 ]] || return 1
  is_tty || return 1

  if [[ "$TUI_PROGRESS_RENDER_ACTIVE" -eq 1 ]]; then
    progress_was_active=1
    tui_progress_end
  fi

  tui_failure_context "$label" "$exit_code"

  if tui_can_style; then
    local choice
    choice="$(gum choose --header "Required step failed" "Retry step" "Abort install" || true)"
    if [[ "$choice" == "Retry step" ]]; then
      [[ "$progress_was_active" -eq 0 ]] || tui_progress_begin
      return 0
    fi
    return 1
  fi

  local reply=""
  read -r -p "Retry this step? [y/N] " reply
  if [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    [[ "$progress_was_active" -eq 0 ]] || tui_progress_begin
    return 0
  fi
  return 1
}

tui_step_skipped() {
  local title="$1"
  TUI_STEP_STATUS["$title"]="skipped"

  if [[ "$TUI_PROGRESS_RENDER_ACTIVE" -eq 1 ]]; then
    tui_progress_render_steps
    return 0
  fi

  if tui_can_style; then
    printf '%s %s\n' "$(gum style --foreground 3 ' ○')" "$title"
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
    record="$(choice_record "$category" "$choice_id")"
    [[ -n "$record" ]] || continue
    label="$(choice_field "$record" 2)"
    [[ -n "$label" ]] && labels+=("$label")
  done < <(effective_choice_ids "$category")

  join_by ", " "${labels[@]}"
}

tui_show_install_plan() {
  if ! tui_can_style; then
    print_plan_summary
    return 0
  fi

  local native_backend native_packages flatpaks actions sources services dotfiles native_base flatpak_base action_base source_base conflicts first_run
  native_backend="$(native_backend)"
  native_packages="$(count_plan_entries "$(package_file_for_backend "$native_backend")")"
  flatpaks="$(count_plan_entries "$PLAN_DIR/flatpak/apps.flatpaks")"
  actions="$(count_plan_entries "$PLAN_DIR/actions/actions.list")"
  sources="$(tui_count_plan_group "$PLAN_DIR"/sources/*.list)"
  services="$(tui_count_plan_group "$PLAN_DIR"/services/*.list)"
  dotfiles="$(count_plan_entries "$PLAN_DIR/stow/packages.list")"
  native_base="$(base_rationale_count "$native_backend")"
  flatpak_base="$(base_rationale_count flatpak)"
  action_base="$(base_rationale_count action)"
  source_base="$(base_rationale_count source)"
  conflicts="$(count_plan_entries "$PLAN_DIR/files/config-conflicts.tsv")"
  first_run="$(awk -F'\t' '$2=="first-run"{count++} END{print count+0}' "$PLAN_DIR/files/managed-config-policy.tsv" 2>/dev/null || printf '0')"

  printf '\n'
  gum style --bold --foreground 4 "Install Plan"
  gum style --faint "Detailed plan: $PLAN_DIR/summary.txt"
  printf '\n'
  gum style --bold "Context"
  printf '  %s %s\n' "$(gum style --foreground 12 '→')" "Platform: Fedora Linux"
  printf '  %s %s\n' "$(gum style --foreground 12 '→')" "Target user: $TARGET_USER"

  printf '\n'
  gum style --bold "Selected Choices"
  local category labels
  for category in $(category_names); do
    category_always_installed "$category" && continue
    labels="$(tui_choice_labels_for_category "$category")"
    [[ -n "$labels" ]] || continue
    printf '  %s %s: %s\n' "$(gum style --foreground 2 '+')" "$category" "$labels"
  done

  printf '\n'
  gum style --bold "Planned Actions"
  printf '  %s %s packages: %s base, %s optional\n' "$(gum style --foreground 2 '+')" "${native_backend^^}" "$native_base" "$((native_packages - native_base))"
  [[ "$flatpaks" -gt 0 ]] && printf '  %s Flatpaks: %s base, %s optional\n' "$(gum style --foreground 2 '+')" "$flatpak_base" "$((flatpaks - flatpak_base))"
  [[ "$actions" -gt 0 ]] && printf '  %s Actions: %s base, %s optional\n' "$(gum style --foreground 2 '+')" "$action_base" "$((actions - action_base))"
  [[ "$sources" -gt 0 ]] && printf '  %s Sources: %s required/base, %s optional\n' "$(gum style --foreground 2 '+')" "$source_base" "$((sources - source_base))"
  [[ "$services" -gt 0 ]] && printf '  %s %s service action%s\n' "$(gum style --foreground 2 '+')" "$services" "$([[ "$services" -eq 1 ]] && printf '' || printf 's')"
  [[ "$dotfiles" -gt 0 ]] && printf '  %s %s dotfile package%s\n' "$(gum style --foreground 2 '+')" "$dotfiles" "$([[ "$dotfiles" -eq 1 ]] && printf '' || printf 's')"
  [[ "$conflicts" -gt 0 ]] && printf '  %s %s managed config conflict%s will be backed up\n' "$(gum style --foreground 11 '!')" "$conflicts" "$([[ "$conflicts" -eq 1 ]] && printf '' || printf 's')"
  [[ "$first_run" -gt 0 ]] && printf '  %s %s first-run config task%s\n' "$(gum style --foreground 12 '→')" "$first_run" "$([[ "$first_run" -eq 1 ]] && printf '' || printf 's')"

  if [[ -f "$PLAN_DIR/base-rationale.tsv" ]]; then
    local trust_exceptions
    trust_exceptions="$(awk -F'\t' '$1=="source" {print $2}' "$PLAN_DIR/base-rationale.tsv" | while IFS= read -r source_id; do
      [[ -n "$source_id" ]] || continue
      load_source_descriptor "$source_id" || continue
      [[ "${SOURCE_BOOTSTRAP_EXCEPTION:-0}" -eq 1 ]] && printf '%s (%s)\n' "$SOURCE_ID" "$SOURCE_GPG_POLICY"
    done)"
    if [[ -n "$trust_exceptions" ]]; then
      printf '\n'
      gum style --bold --foreground 11 "Trust Exceptions"
      while IFS= read -r line; do
        [[ -n "$line" ]] && printf '  %s %s\n' "$(gum style --foreground 11 '!')" "$line"
      done <<<"$trust_exceptions"
    fi
  fi

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
  catalog="$(choice_catalog_path "$category")"
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
    local escaped_option
    for option in "${selected_options[@]}"; do
      escaped_option="${option//\\/\\\\}"
      escaped_option="${escaped_option//,/\\,}"
      choose_args+=(--selected "$escaped_option")
    done
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
  gum style --bold "Platform: Fedora Linux"
  gum style --faint "Install target user: $TARGET_USER"

  local -a browser_choices=()
  local -a category_choices=()

  local browser_header="Select browser(s). Space toggles, Enter continues."
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
      record="$(choice_record "browsers" "$browser_id")"
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
