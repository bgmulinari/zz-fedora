#!/usr/bin/env bash
set -Eeuo pipefail

# Desktop asset and theme seed installs applied after packages and dotfiles:
# wallpapers, Starship prompt, Ghostty/Niri seeds, and Qt/KDE theme config.

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
    install_file_if_changed user "$source_file" "$destination"
  done

  source_file="$ROOT_DIR/assets/wallpapers/PROVENANCE.md"
  destination="$TARGET_HOME/.local/share/backgrounds/PROVENANCE.md"
  if [[ -f "$source_file" && ! -e "$destination" && ! -L "$destination" ]]; then
    install_file_if_changed user "$source_file" "$destination"
  fi
}

# Noctalia serves its bundled wallpaper and offers the first-run setup
# wizard until ~/.local/state/noctalia/.setup-complete exists. The install
# already is the setup, so seed the marker before the first login; without
# it, closing the wizard persists the bundled wallpaper into settings.toml,
# which permanently overrides the managed wallpaper.default.
#
# The settings.toml seed pins the sidecar schema version and carries the
# managed default wallpaper. Without the version, the shell's first
# in-session settings write creates the sidecar unversioned and the
# follow-up reload migrates it from version 0; the migration-persist path
# re-derives wallpaper state from the sidecar alone, so the sidecar must
# also name the wallpaper itself to survive that path — including future
# upstream version bumps past the pinned value.
# Both seeds complement the managed config, so --skip-dotfiles keeps
# Noctalia's own first-run experience instead.
install_noctalia_state_seeds_if_missing() {
  local native_plan destination wallpaper_path
  [[ "$SKIP_DOTFILES" -eq 1 ]] && return 0
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" noctalia || return 0

  destination="$TARGET_HOME/.local/state/noctalia/settings.toml"
  if [[ ! -e "$destination" && ! -L "$destination" ]]; then
    log_progress "Seeding Noctalia settings sidecar"
    wallpaper_path="$(noctalia_managed_default_wallpaper)"
    {
      printf 'config_version = 2\n'
      if [[ -n "$wallpaper_path" ]]; then
        printf '\n[wallpaper.default]\npath = "%s"\n' "$wallpaper_path"
      fi
    } | write_user_file 0644 "$destination"
  fi

  destination="$TARGET_HOME/.local/state/noctalia/.setup-complete"
  if [[ ! -e "$destination" && ! -L "$destination" ]]; then
    log_progress "Marking Noctalia first-run setup complete"
    write_user_file 0644 "$destination" </dev/null
  fi
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

  local palette_file
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

  backup_user_file_if_needed "$config_file"
  run_cmd_as_user "$TARGET_USER" sh -c 'printf "\n" >> "$1"; cat "$2" >> "$1"' sh "$config_file" "$palette_file"
  rm -f "$palette_file"
  [[ "$DRY_RUN" -eq 1 ]] || log_info "Added fallback Noctalia Starship palette to $config_file"
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
  install_file_if_changed user "$ROOT_DIR/templates/starship.toml" "$destination"
}

install_ghostty_theme_seed_if_missing() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend)")"
  destination="$TARGET_HOME/.config/ghostty/themes/noctalia"

  plan_has_any_backend_entry "$native_plan" ghostty || return 0
  [[ -e "$destination" || -L "$destination" ]] && return 0
  log_progress "Installing Ghostty Noctalia theme seed"
  install_file_if_changed user "$ROOT_DIR/templates/ghostty/noctalia" "$destination"
}

install_niri_noctalia_seed_if_missing() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" niri || return 0

  destination="$TARGET_HOME/.config/niri/noctalia.kdl"
  [[ -e "$destination" || -L "$destination" ]] && return 0
  log_progress "Installing Niri Noctalia config seed"
  install_file_if_changed user "$ROOT_DIR/templates/niri/noctalia.kdl" "$destination"
}

install_niri_display_seed_if_missing() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" niri || return 0

  destination="$TARGET_HOME/.config/niri/cfg/display.kdl"
  [[ -e "$destination" || -L "$destination" ]] && return 0
  log_progress "Installing Niri display config seed"
  install_file_if_changed user "$ROOT_DIR/templates/niri/display.kdl" "$destination"
}

install_qt6ct_config() {
  local config_file color_file

  config_file="$TARGET_HOME/.config/qt6ct/qt6ct.conf"
  color_file="$TARGET_HOME/.local/share/color-schemes/noctalia.colors"

  write_user_file 0644 "$config_file" <<EOF
[Appearance]
color_scheme_path=$color_file
custom_palette=true
standard_dialogs=default
style=Fusion
EOF
}

install_qt_theme_config() {
  local native_plan
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" qt6ct qt6ct-kde || return 0

  log_progress "Configuring Qt theme integration"
  install_qt6ct_config
  install_kde_qt_theme_config
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
