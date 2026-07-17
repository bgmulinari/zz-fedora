#!/usr/bin/env bash
set -Eeuo pipefail

install_user_file_if_changed() {
  local source_file="$1"
  local destination="$2"
  local mode="${3:-0644}"

  if [[ -f "$destination" ]] && cmp -s "$source_file" "$destination"; then
    log_info "Unchanged file: $destination"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install %s -> %s (mode %s)\n' "$source_file" "$destination" "$mode"
    return 0
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    local backup_root backup_path
    backup_root="$STATE_DIR/backups/$(timestamp)"
    backup_path="$backup_root$destination"
    run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$backup_path")"
    run_cmd_as_user "$TARGET_USER" cp -a "$destination" "$backup_path"
    log_info "Backed up $destination to $backup_path"
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$destination")"
  run_cmd_as_user "$TARGET_USER" install -m "$mode" "$source_file" "$destination"
}

install_bundled_wallpapers() {
  local source_file wallpaper_name destination

  log_progress "Installing bundled wallpapers"
  for source_file in "$ROOT_DIR"/assets/wallpapers/*.{jpg,jpeg,png,webp,avif}; do
    [[ -f "$source_file" ]] || continue
    wallpaper_name="$(basename "$source_file")"
    destination="$TARGET_HOME/.local/share/backgrounds/$wallpaper_name"
    if [[ -e "$destination" || -L "$destination" ]]; then
      log_info "Preserving existing wallpaper: $destination"
      continue
    fi
    install_user_file_if_changed "$source_file" "$destination"
  done

  source_file="$ROOT_DIR/assets/wallpapers/PROVENANCE.md"
  destination="$TARGET_HOME/.local/share/backgrounds/PROVENANCE.md"
  if [[ -f "$source_file" && ! -e "$destination" && ! -L "$destination" ]]; then
    install_user_file_if_changed "$source_file" "$destination"
  fi
}

plan_has_any_backend_entry() {
  local plan_file="$1"
  shift
  local entry
  for entry in "$@"; do
    [[ -f "$plan_file" ]] || continue
    if grep -Fx "$entry" "$plan_file" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

starship_theming_available_for_plan() {
  local native_plan="$1"

  plan_has_any_backend_entry "$native_plan" starship && return 0

  return 1
}

install_starship_fallback_palette_if_needed() {
  local config_file="$1"
  [[ -f "$config_file" || -L "$config_file" ]] || return 0
  grep -Eq '^[[:space:]]*palette[[:space:]]*=[[:space:]]*"noctalia"' "$config_file" || return 0
  grep -Eq '^[[:space:]]*\[palettes\.noctalia\]' "$config_file" && return 0

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: append fallback Noctalia Starship palette -> %s\n' "$config_file"
    return 0
  fi

  local backup_root backup_path palette_file
  backup_root="$STATE_DIR/backups/$(timestamp)"
  backup_path="$backup_root$config_file"
  palette_file="$(mktemp "$CACHE_DIR/starship-palette.XXXXXX")"

  awk '
    /^# >>> NOCTALIA STARSHIP PALETTE >>>$/ { copy = 1 }
    copy { print }
    /^# <<< NOCTALIA STARSHIP PALETTE <<<$/{ copy = 0 }
  ' "$ROOT_DIR/templates/starship.toml" >"$palette_file"
  chmod 0644 "$palette_file"

  if [[ ! -s "$palette_file" ]]; then
    rm -f "$palette_file"
    log_warn "Could not find fallback Noctalia Starship palette in template"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$backup_path")"
  run_cmd_as_user "$TARGET_USER" cp -a "$config_file" "$backup_path"
  run_cmd_as_user "$TARGET_USER" sh -c 'printf "\n" >> "$1"; cat "$2" >> "$1"' sh "$config_file" "$palette_file"
  rm -f "$palette_file"
  log_info "Added fallback Noctalia Starship palette to $config_file"
}

install_starship_config() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend)")"
  destination="$TARGET_HOME/.config/starship.toml"

  starship_theming_available_for_plan "$native_plan" || return 0
  log_progress "Installing Starship shell prompt config"
  if [[ -e "$destination" || -L "$destination" ]]; then
    install_starship_fallback_palette_if_needed "$destination"
    return 0
  fi
  install_user_file_if_changed "$ROOT_DIR/templates/starship.toml" "$destination"
}

install_ghostty_theme_seed_if_missing() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend)")"
  destination="$TARGET_HOME/.config/ghostty/themes/noctalia"

  plan_has_any_backend_entry "$native_plan" ghostty || return 0
  [[ -e "$destination" || -L "$destination" ]] && return 0
  log_progress "Installing Ghostty Noctalia theme seed"
  install_user_file_if_changed "$ROOT_DIR/templates/ghostty/noctalia" "$destination"
}

install_niri_noctalia_seed_if_missing() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" niri || return 0

  destination="$TARGET_HOME/.config/niri/noctalia.kdl"
  [[ -e "$destination" || -L "$destination" ]] && return 0
  log_progress "Installing Niri Noctalia config seed"
  install_user_file_if_changed "$ROOT_DIR/templates/niri/noctalia.kdl" "$destination"
}

install_niri_display_seed_if_missing() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" niri || return 0

  destination="$TARGET_HOME/.config/niri/cfg/display.kdl"
  [[ -e "$destination" || -L "$destination" ]] && return 0
  log_progress "Installing Niri display config seed"
  install_user_file_if_changed "$ROOT_DIR/templates/niri/display.kdl" "$destination"
}

install_qt6ct_config() {
  local config_file temp_file color_file

  config_file="$TARGET_HOME/.config/qt6ct/qt6ct.conf"
  color_file="$TARGET_HOME/.local/share/color-schemes/noctalia.colors"
  temp_file="$(mktemp "$CACHE_DIR/qt6ct.XXXXXX")"

  cat >"$temp_file" <<EOF
[Appearance]
color_scheme_path=$color_file
custom_palette=true
standard_dialogs=default
style=Fusion
EOF
  chmod 0644 "$temp_file"
  install_user_file_if_changed "$temp_file" "$config_file"
  rm -f "$temp_file"
}

install_qt_theme_config() {
  local native_plan
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" qt6ct qt6ct-kde || return 0

  log_progress "Configuring Qt theme integration"
  install_qt6ct_config
  install_kde_qt_theme_config
}

set_ini_key_for_user() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  local temp_file

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$file")"
  run_cmd_as_user "$TARGET_USER" touch "$file"
  temp_file="$(mktemp "$CACHE_DIR/ini.XXXXXX")"
  awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN {
      in_section = 0
      section_seen = 0
      key_written = 0
    }
    $0 == "[" section "]" {
      if (in_section && !key_written) {
        print key "=" value
        key_written = 1
      }
      in_section = 1
      section_seen = 1
      print
      next
    }
    /^\[/ {
      if (in_section && !key_written) {
        print key "=" value
        key_written = 1
      }
      in_section = 0
      print
      next
    }
    in_section && $0 ~ "^" key "=" {
      print key "=" value
      key_written = 1
      next
    }
    { print }
    END {
      if (!section_seen) {
        print "[" section "]"
        print key "=" value
      } else if (in_section && !key_written) {
        print key "=" value
      }
    }
  ' "$file" >"$temp_file"
  chmod 0644 "$temp_file"
  install_user_file_if_changed "$temp_file" "$file"
  rm -f "$temp_file"
}

install_kde_config_key() {
  local group="$1"
  local key="$2"
  local value="$3"
  local config_file="$TARGET_HOME/.config/kdeglobals"

  if have_cmd kwriteconfig6; then
    run_cmd_as_user "$TARGET_USER" env HOME="$TARGET_HOME" kwriteconfig6 --file kdeglobals --group "$group" --key "$key" "$value"
    return 0
  fi
  set_ini_key_for_user "$config_file" "$group" "$key" "$value"
}

install_kde_qt_theme_config() {
  install_kde_config_key General ColorScheme Noctalia
  install_kde_config_key General Name noctalia
  install_kde_config_key KDE widgetStyle Fusion
  install_kde_config_key Icons Theme Yaru-blue
}

configure_flatpak_theme_access() {
  local native_plan flatpak_plan
  native_plan="$(package_file_for_backend "$(native_backend)")"
  flatpak_plan="$(package_file_for_backend flatpak)"
  if ! plan_has_any_backend_entry "$native_plan" flatpak &&
    ! plan_has_any_backend_entry "$flatpak_plan" org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark; then
    return 0
  fi

  have_cmd flatpak || return 0

  log_progress "Configuring Flatpak theme filesystem access"
  run_cmd_as_user "$TARGET_USER" flatpak override --user \
    --filesystem=xdg-config/gtk-3.0:ro \
    --filesystem=xdg-config/gtk-4.0:ro \
    --filesystem=xdg-config/qt6ct:ro \
    --filesystem=xdg-config/kdeglobals:ro \
    --filesystem=xdg-data/color-schemes:ro
}

configure_xdg_terminal_defaults() {
  local terminals_file="$TARGET_HOME/.config/xdg-terminals.list"

  log_progress "Configuring default terminal preference"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: write Ghostty terminal defaults to %s\n' "$terminals_file"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" sh -c '
    terminals_file="$1"
    mkdir -p "$(dirname "$terminals_file")"
    cat >"$terminals_file" <<EOF
# Terminal emulator preference order for xdg-terminal-exec
# The first found and valid terminal will be used
com.mitchellh.ghostty.desktop
Alacritty.desktop
kitty.desktop
org.gnome.Console.desktop
org.gnome.Terminal.desktop
EOF
  ' sh "$terminals_file"
}

desktop_file_installed_for_user() {
  local desktop_file="$1"
  [[ -f "$TARGET_HOME/.local/share/applications/$desktop_file" ]] && return 0
  [[ -f "/usr/local/share/applications/$desktop_file" ]] && return 0
  [[ -f "/usr/share/applications/$desktop_file" ]] && return 0
  return 1
}

package_available_for_default_app() {
  local package_name="$1"
  local native_plan flatpak_plan
  native_plan="$(package_file_for_backend "$(native_backend)")"
  flatpak_plan="$(package_file_for_backend flatpak)"

  plan_has_any_backend_entry "$native_plan" "$package_name" && return 0
  plan_has_any_backend_entry "$flatpak_plan" "$package_name" && return 0
  [[ "$DRY_RUN" -eq 1 ]] && return 1

  if declare -F fedora_package_installed >/dev/null 2>&1 && fedora_package_installed "$package_name"; then
    return 0
  fi
  if have_cmd flatpak && flatpak info "$package_name" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

default_app_condition_met() {
  local desktop_file="$1"
  local condition="$2"
  case "$condition" in
    always)
      return 0
      ;;
    package:*)
      package_available_for_default_app "${condition#package:}"
      ;;
    desktop-installed)
      [[ "$DRY_RUN" -eq 1 ]] && return 1
      desktop_file_installed_for_user "$desktop_file"
      ;;
    *)
      die "Unsupported default application condition: $condition"
      ;;
  esac
}

configure_default_applications_from_tsv() {
  local defaults_file="$ROOT_DIR/config/default-applications.tsv"
  local desktop_file condition mime_type extra
  [[ -f "$defaults_file" ]] || die "Missing default applications config: $defaults_file"

  log_progress "Configuring default applications"
  while IFS=$'\t' read -r desktop_file condition mime_type extra || [[ -n "$desktop_file" ]]; do
    [[ -n "$desktop_file" ]] || continue
    [[ "$desktop_file" == \#* ]] && continue
    [[ -z "${extra:-}" && -n "$condition" && -n "$mime_type" ]] || die "Malformed default applications row: $desktop_file"
    default_app_condition_met "$desktop_file" "$condition" || continue
    run_cmd_as_user "$TARGET_USER" xdg-mime default "$desktop_file" "$mime_type" || true
  done <"$defaults_file"
}

install_zz_launcher() {
  local launcher="$TARGET_HOME/.local/bin/zz"
  local target="$ROOT_DIR/bin/zz"
  [[ -x "$target" ]] || return 0

  log_progress "Installing zz launcher"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install zz launcher %s -> %s\n' "$target" "$launcher"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$launcher")"
  run_cmd_as_user "$TARGET_USER" ln -sfn "$target" "$launcher"
}

configure_default_applications() {
  if [[ "$(resolved_desktop_app_profile)" == "full" ]]; then
    configure_default_applications_from_tsv
  else
    log_info "Skipping full desktop default applications for desktop app profile: $(resolved_desktop_app_profile)"
  fi
  configure_xdg_terminal_defaults
}

enable_user_service() {
  local service_name="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "${ZZ_INSTALLER_DEFER_START_SERVICES:-0}" -eq 1 ]]; then
      printf 'DRY-RUN: systemctl --global enable %s\n' "$service_name"
    else
      printf 'DRY-RUN: systemctl --user enable --now %s\n' "$service_name"
    fi
    return 0
  fi

  if [[ "${ZZ_INSTALLER_DEFER_START_SERVICES:-0}" -eq 1 ]]; then
    run_cmd_as_root systemctl --global enable "$service_name"
    return $?
  fi

  if run_cmd_as_user "$TARGET_USER" systemctl --user enable --now "$service_name"; then
    return 0
  fi

  [[ "$EUID" -eq 0 ]] || return 1
  run_cmd_as_root systemctl --global enable "$service_name"
}

enable_user_services() {
  local service_name
  while IFS= read -r service_name; do
    [[ -n "$service_name" ]] || continue
    log_progress "Enabling user service: $service_name"
    enable_user_service "$service_name" || log_warn "Could not enable user service: $service_name"
  done < <(user_services_from_plan)
}

set_default_browser() {
  local desktop_file="$1"
  local -a browser_mime_types=(
    text/html
    application/xhtml+xml
    x-scheme-handler/http
    x-scheme-handler/https
  )
  local mime_type failed=0

  log_progress "Setting default browser: $desktop_file"
  for mime_type in "${browser_mime_types[@]}"; do
    run_cmd_as_user "$TARGET_USER" xdg-mime default "$desktop_file" "$mime_type" || failed=1
  done

  if run_cmd_as_user "$TARGET_USER" xdg-settings set default-web-browser "$desktop_file"; then
    return 0
  fi

  [[ "$failed" -eq 0 ]] && return 0
  log_warn "Could not set default browser to $desktop_file"
}

configure_selected_browser_default() {
  local -a browsers=()
  while IFS= read -r browser; do
    [[ -n "$browser" ]] && browsers+=("$browser")
  done < <(effective_choice_ids "browsers")

  local browser_choice=""
  if [[ -n "$PREFERRED_BROWSER" ]]; then
    browser_choice="$PREFERRED_BROWSER"
  elif [[ "${#browsers[@]}" -eq 1 ]]; then
    browser_choice="${browsers[0]}"
  fi
  if [[ -n "$browser_choice" ]]; then
    local desktop_file=""
    desktop_file="$(browser_desktop_file "$browser_choice" || true)"
    if [[ -n "$desktop_file" ]]; then
      set_default_browser "$desktop_file"
    fi
  fi
}

first_run_marker() {
  printf '%s\n' "$STATE_DIR/first-run.done"
}

first_run_desktop_file() {
  printf '%s\n' "$TARGET_HOME/.config/autostart/zz-first-run.desktop"
}

register_first_run_hook() {
  local desktop_file launcher
  desktop_file="$(first_run_desktop_file)"
  launcher="$TARGET_HOME/.local/bin/zz"

  log_progress "Registering first-run hook"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: register first-run hook -> %s\n' "$desktop_file"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$desktop_file")"
  run_cmd_as_user "$TARGET_USER" sh -c '
    desktop_file="$1"
    launcher="$2"
    cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=ZZ First Run
Exec=$launcher first-run
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  ' sh "$desktop_file" "$launcher"
}

remove_first_run_hook() {
  local desktop_file
  desktop_file="$(first_run_desktop_file)"
  [[ -e "$desktop_file" || -L "$desktop_file" ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: remove first-run hook %s\n' "$desktop_file"
    return 0
  fi
  run_cmd_as_user "$TARGET_USER" rm -f "$desktop_file"
}

planned_noctalia_app_templates() {
  local action_plan="$PLAN_DIR/actions/actions.list"
  plan_file_has_entry "$action_plan" pywalfox && printf 'pywalfox\n'
  plan_file_has_entry "$action_plan" vscode-extension:noctalia.noctaliatheme && printf 'vscode\n'
}

apply_managed_noctalia_app_themes() {
  local config_file="$TARGET_HOME/.config/noctalia/config.toml"
  local palette_file="$TARGET_HOME/.config/noctalia/palettes/catppuccin-mocha-blue.json"
  local state_home="${XDG_STATE_HOME:-$TARGET_HOME/.local/state}"
  local template_id template_config attempt applied
  local -a template_ids=()

  mapfile -t template_ids < <(planned_noctalia_app_templates)
  [[ "${#template_ids[@]}" -gt 0 ]] || return 0

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: render managed Noctalia app themes: %s\n' "${template_ids[*]}"
    return 0
  fi

  # Missing managed config is expected with --skip-dotfiles.
  [[ -f "$config_file" && -f "$palette_file" ]] || return 0

  log_progress "Rendering first-launch application themes"
  for template_id in "${template_ids[@]}"; do
    template_config="$state_home/noctalia/community-templates/$template_id/template.toml"
    applied=0
    for ((attempt = 1; attempt <= 120; attempt++)); do
      if [[ -f "$template_config" ]] && run_cmd_as_user "$TARGET_USER" \
        noctalia theme \
        --theme-json "$palette_file" \
        --default-mode dark \
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

module_80_defaults() {
  configure_default_applications
  configure_selected_browser_default
}

module_80_first_run() {
  local marker
  marker="$(first_run_marker)"
  if [[ -f "$marker" && "${ZZ_FIRST_RUN_FORCE:-0}" -ne 1 ]]; then
    log_info "First-run tasks already completed: $marker"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" systemctl --user daemon-reload || true
  enable_user_services
  run_cmd_as_user "$TARGET_USER" xdg-user-dirs-update || true
  if [[ "$(resolved_desktop_app_profile)" == "full" ]]; then
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark || true
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
  fi
  module_80_defaults
  apply_managed_noctalia_app_themes || return 1

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: mark first-run complete -> %s\n' "$marker"
    remove_first_run_hook
    return 0
  fi

  mkdir -p "$(dirname "$marker")"
  printf 'completed_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >"$marker"
  remove_first_run_hook
}

module_80_post_actions() {
  log_progress "Installing post-install launcher and desktop defaults"
  install_zz_launcher
  configure_default_applications
  log_progress "Installing desktop assets and theme seeds"
  install_bundled_wallpapers
  install_starship_config
  install_ghostty_theme_seed_if_missing
  install_niri_display_seed_if_missing
  install_niri_noctalia_seed_if_missing
  install_qt_theme_config
  configure_flatpak_theme_access
  log_progress "Enabling user services and first-run tasks"
  enable_user_services
  register_first_run_hook
  write_managed_files_report
}
