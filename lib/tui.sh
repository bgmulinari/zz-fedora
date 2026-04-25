#!/usr/bin/env bash
set -Eeuo pipefail

tui_require_gum() {
  have_cmd gum || die "gum is required for wizard mode"
}

tui_intro() {
  gum style --border rounded --padding "1 2" \
    "Niri + Noctalia Bootstrapper" \
    "KDE/Qt-oriented desktop" \
    "Ghostty terminal" \
    "Fedora primary, Arch experimental"
}

tui_choose_target_user() {
  local current_default="$TARGET_USER"
  local entered
  entered="$(gum input --placeholder "$current_default" --prompt "Target user > " --value "$current_default")"
  TARGET_USER="${entered:-$current_default}"
}

tui_pick_multiple() {
  local prompt="$1"
  shift
  local choices=("$@")
  gum style "$prompt" >&2
  gum choose --no-limit "${choices[@]}"
}

tui_run_wizard() {
  [[ "$NO_TUI" -eq 1 ]] && die "Wizard mode was requested with --no-tui. Use install --yes instead."
  is_tty || die "Wizard mode requires an interactive TTY. Use install --yes or print-plan instead."
  tui_require_gum
  tui_intro
  normalize_distro
  gum style "Detected: ${DISTRO^}" "Target user: $TARGET_USER"
  tui_choose_target_user

  local -a browser_choices=()
  local -a gaming_choices=()
  local -a optional_choices=()
  local -a shell_choices=()
  local -a browser_options=()

  case "$DISTRO" in
    fedora)
      if gum confirm "Install full multimedia codecs?"; then
        add_category_selection "media" "codecs"
      fi
      browser_options=(firefox chromium chrome brave zen-flatpak zen-copr helium-copr)
      ;;
    arch)
      browser_options=(firefox chromium brave zen-aur zen-flatpak helium)
      ;;
  esac

  mapfile -t browser_choices < <(tui_pick_multiple "Browsers" "${browser_options[@]}" 2>/dev/null || true)
  if [[ "${#browser_choices[@]}" -gt 0 ]]; then
    set_category_override "browsers" "$(join_by , "${browser_choices[@]}")"
  fi

  mapfile -t gaming_choices < <(tui_pick_multiple "Gaming" steam game-tools lutris heroic 2>/dev/null || true)
  if [[ "${#gaming_choices[@]}" -gt 0 ]]; then
    set_category_override "gaming" "$(join_by , "${gaming_choices[@]}")"
  fi

  mapfile -t optional_choices < <(tui_pick_multiple "Optional categories" base nvidia libvirt communication creative 2>/dev/null || true)
  if array_contains "base" "${optional_choices[@]:-}"; then
    add_category_selection "dev" "base"
    add_category_selection "hardware" "base"
    add_category_selection "print-scan" "base"
  fi
  if array_contains "nvidia" "${optional_choices[@]:-}"; then
    add_category_selection "hardware" "nvidia"
  fi
  if array_contains "libvirt" "${optional_choices[@]:-}"; then
    add_category_selection "virtualization" "libvirt"
  fi
  if array_contains "communication" "${optional_choices[@]:-}"; then
    add_category_selection "flatpak-apps" "communication"
  fi
  if array_contains "creative" "${optional_choices[@]:-}"; then
    add_category_selection "flatpak-apps" "creative"
  fi

  mapfile -t shell_choices < <(tui_pick_multiple "Shell / CLI tools" zsh starship zoxide fastfetch gh btop fd fzf bat yazi 2>/dev/null || true)
  if [[ "${#shell_choices[@]}" -gt 0 ]]; then
    set_category_override "shell" "$(join_by , "${shell_choices[@]}")"
  fi

  if [[ "${#browser_choices[@]}" -gt 1 ]]; then
    PREFERRED_BROWSER="$(gum choose "${browser_choices[@]}")"
  fi
}
