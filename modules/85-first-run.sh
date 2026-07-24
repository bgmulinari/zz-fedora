#!/usr/bin/env bash
set -Eeuo pipefail

planned_noctalia_app_templates() {
  local action_plan="$PLAN_DIR/actions/actions.list"
  plan_file_has_entry "$action_plan" pywalfox && printf 'pywalfox\n'
  plan_file_has_entry "$action_plan" vscode-extension:noctalia.noctaliatheme && printf 'vscode\n'
}

apply_managed_noctalia_app_themes() {
  local config_file="$TARGET_HOME/.config/noctalia/config.toml"
  local state_home="${XDG_STATE_HOME:-$TARGET_HOME/.local/state}"
  local palette_name palette_file mode
  local template_id template_config attempt applied
  local -a template_ids=()

  mapfile -t template_ids < <(planned_noctalia_app_templates)
  [[ "${#template_ids[@]}" -gt 0 ]] || return 0

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: render managed Noctalia app themes: %s\n' "${template_ids[*]}"
    return 0
  fi

  # App themes are rendered from the managed custom palette; other theme
  # sources are managed by the running shell itself.
  [[ "$(noctalia_managed_theme_source)" == "custom" ]] || return 0
  palette_name="$(noctalia_managed_custom_palette_name)"
  [[ -n "$palette_name" ]] || return 0
  palette_file="$TARGET_HOME/.config/noctalia/palettes/$palette_name.json"
  mode="$(noctalia_managed_theme_mode)"

  # Missing managed config is expected with --skip-user-config.
  [[ -f "$config_file" && -f "$palette_file" ]] || return 0

  log_progress "Rendering first-launch application themes"
  for template_id in "${template_ids[@]}"; do
    template_config="$state_home/noctalia/community-templates/$template_id/template.toml"
    applied=0
    for ((attempt = 1; attempt <= 120; attempt++)); do
      if [[ -f "$template_config" ]] && run_cmd_as_user "$TARGET_USER" \
        noctalia theme \
        --theme-json "$palette_file" \
        --default-mode "$mode" \
        -c "$template_config" \
        >/dev/null 2>&1; then
        applied=1
        break
      fi
      sleep 0.25
    done
    if [[ "$applied" -ne 1 ]]; then
      log_warn "Noctalia template was not ready: $template_id"
      return 1
    fi
  done
}

module_85_first_run() {
  local marker
  marker="$(first_run_marker)"
  if [[ -f "$marker" && "${ZZ_FIRST_RUN_FORCE:-0}" -ne 1 ]]; then
    log_info "First-run tasks already completed: $marker"
    # A deferred Flatpak queue can appear after first-run already completed
    # (an install re-run in a sandbox-restricted environment re-registers
    # the hook); consume it and clear the hook instead of stranding both.
    install_deferred_flatpaks || return 1
    remove_first_run_hook
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" systemctl --user daemon-reload || true
  enable_user_services
  run_cmd_as_user "$TARGET_USER" xdg-user-dirs-update || true
  if [[ "$(resolved_desktop_app_profile)" == "full" ]]; then
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark || true
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
  fi
  apply_desktop_defaults
  apply_managed_noctalia_app_themes || return 1
  install_deferred_flatpaks || return 1

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: mark first-run complete -> %s\n' "$marker"
    remove_first_run_hook
    return 0
  fi

  mkdir -p "$(dirname "$marker")"
  printf 'completed_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >"$marker"
  remove_first_run_hook
}
