#!/usr/bin/env bash
set -Eeuo pipefail

tui_require_gum() {
  have_cmd gum || die "gum is required for wizard mode"
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
  gum confirm --prompt.foreground "" --selected.background 12 "$prompt"
}

tui_choose_target_user() {
  local current_default="$TARGET_USER"
  local entered
  entered="$(gum input --placeholder "$current_default" --prompt "Target user > " --value "$current_default")"
  TARGET_USER="${entered:-$current_default}"
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
  [[ -n "$chosen" ]] || return 0

  while IFS= read -r option; do
    [[ -n "$option" ]] && printf '%s\n' "${option_ids[$option]}"
  done <<<"$chosen"
}

tui_pick_workstation_extras() {
  local -a options=()
  local -A option_targets=()
  local category choice_id record label description option

  for category in dev hardware print-scan virtualization flatpak-apps; do
    while IFS= read -r choice_id; do
      [[ -n "$choice_id" ]] || continue
      record="$(choice_record "$DISTRO" "$category" "$choice_id")"
      [[ -n "$record" ]] || continue
      label="$(choice_field "$record" 2)"
      description="$(choice_field "$record" 5)"
      option="$(tui_choice_option_label "$label" "$description")"
      options+=("$option")
      option_targets["$option"]="$category=$choice_id"
    done < <(awk -F'\t' 'NF==5 && $1 !~ /^#/ {print $1}' "$(choice_catalog_path "$DISTRO" "$category")")
  done

  [[ "${#options[@]}" -gt 0 ]] || return 0

  local chosen
  chosen="$(gum choose \
    --no-limit \
    --header "Select workstation extras. Space toggles, Enter continues." \
    --header.foreground "" \
    --height 999 \
    --selected.foreground 2 \
    --cursor.foreground "" \
    "${options[@]}")" || return 0
  [[ -n "$chosen" ]] || return 0

  while IFS= read -r option; do
    [[ -n "$option" ]] && printf '%s\n' "${option_targets[$option]}"
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
  tui_choose_target_user

  local -a browser_choices=()
  local -a gaming_choices=()
  local -a extra_choices=()
  local -a shell_choices=()

  case "$DISTRO" in
    fedora)
      if tui_confirm "Enable RPM Fusion multimedia codecs for broader audio/video playback?"; then
        add_category_selection "media" "codecs"
      fi
      ;;
    arch)
      ;;
  esac

  mapfile -t browser_choices < <(tui_pick_catalog_choices "browsers" "Select browser(s). Firefox is the default. Space toggles, Enter continues." || true)
  if [[ "${#browser_choices[@]}" -gt 0 ]]; then
    set_category_override "browsers" "$(join_by , "${browser_choices[@]}")"
  fi

  mapfile -t gaming_choices < <(tui_pick_catalog_choices "gaming" "Select gaming components. Space toggles, Enter continues." || true)
  if [[ "${#gaming_choices[@]}" -gt 0 ]]; then
    set_category_override "gaming" "$(join_by , "${gaming_choices[@]}")"
  fi

  mapfile -t extra_choices < <(tui_pick_workstation_extras || true)
  local extra
  for extra in "${extra_choices[@]:-}"; do
    [[ -n "$extra" && "$extra" == *=* ]] || continue
    add_category_selection "${extra%%=*}" "${extra#*=}"
  done

  mapfile -t shell_choices < <(tui_pick_catalog_choices "shell" "Select shell and CLI tools. Space toggles, Enter continues." || true)
  if [[ "${#shell_choices[@]}" -gt 0 ]]; then
    set_category_override "shell" "$(join_by , "${shell_choices[@]}")"
  fi

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
