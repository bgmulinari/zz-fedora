#!/usr/bin/env bash
set -Eeuo pipefail

# Desktop asset and theme seed installs applied after packages and config:
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

# DMS keeps its settings in an app-writable settings.json and its
# wallpaper in an app-writable session.json; keys absent from either fall
# back to the shell defaults. Seeding partial files before the first login
# selects the vendored Catppuccin registry theme and the managed default
# wallpaper without claiming ownership of files the Settings UI rewrites.
# The dms-colors.json placeholder keeps the greeter cache symlink from
# dangling until the shell generates the real palette.
# The seeds complement the managed config, so --skip-user-config keeps
# DMS's own defaults instead. Shipped plugins are the one thing the seeds
# keep topping up: a plugin ZZ starts shipping after the install is
# enabled and placed in the bar on the next apply, once.
install_dms_state_seeds_if_missing() {
  local native_plan
  [[ "$SKIP_USER_CONFIG" -eq 1 ]] && return 0
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" dms || return 0

  dms_seed_state_files_if_missing
  dms_apply_plugin_defaults
}

starship_theming_available_for_plan() {
  local native_plan="$1"

  plan_has_any_backend_entry "$native_plan" starship && return 0

  return 1
}

install_starship_fallback_palette_if_needed() {
  local config_file="$1"
  [[ -f "$config_file" || -L "$config_file" ]] || return 0
  grep -Eq '^[[:space:]]*palette[[:space:]]*=[[:space:]]*"zz"' "$config_file" || return 0
  grep -Eq '^[[:space:]]*\[palettes\.zz\]' "$config_file" && return 0

  local palette_file
  palette_file="$(mktemp "$CACHE_DIR/starship-palette.XXXXXX")"

  awk '
    /^# >>> ZZ STARSHIP PALETTE >>>$/ { copy = 1 }
    copy { print }
    /^# <<< ZZ STARSHIP PALETTE <<<$/{ copy = 0 }
  ' "$ROOT_DIR/templates/starship.toml" >"$palette_file"
  chmod 0644 "$palette_file"

  if [[ ! -s "$palette_file" ]]; then
    rm -f "$palette_file"
    log_warn "Could not find fallback ZZ Starship palette in template"
    return 0
  fi

  backup_user_file_if_needed "$config_file"
  run_cmd_as_user "$TARGET_USER" sh -c 'printf "\n" >> "$1"; cat "$2" >> "$1"' sh "$config_file" "$palette_file"
  rm -f "$palette_file"
  [[ "$DRY_RUN" -eq 1 ]] || log_info "Added fallback ZZ Starship palette to $config_file"
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
  destination="$(dms_ghostty_theme_file)"

  plan_has_any_backend_entry "$native_plan" ghostty || return 0
  [[ -e "$destination" || -L "$destination" ]] && return 0
  log_progress "Installing Ghostty theme seed"
  install_file_if_changed user "$ROOT_DIR/templates/ghostty/dankcolors" "$destination"
}

install_niri_dms_colors_seed_if_missing() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" niri || return 0

  destination="$TARGET_HOME/.config/niri/dms/colors.kdl"
  [[ -e "$destination" || -L "$destination" ]] && return 0
  log_progress "Installing Niri DMS colors seed"
  install_file_if_changed user "$ROOT_DIR/templates/niri/dms-colors.kdl" "$destination"
}

# The keybind defaults are seeded rather than linked from the product tree
# because DMS rewrites this file whenever a bind is changed in
# Settings -> Keybinds, and it is the only niri fragment its UI reads.
install_niri_dms_binds_seed_if_missing() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend)")"
  plan_has_any_backend_entry "$native_plan" niri || return 0

  destination="$TARGET_HOME/.config/niri/dms/binds.kdl"
  [[ -e "$destination" || -L "$destination" ]] && return 0
  log_progress "Installing Niri DMS keybinds seed"
  install_file_if_changed user "$ROOT_DIR/templates/niri/dms-binds.kdl" "$destination"
}

install_qt6ct_config() {
  local config_file color_file

  config_file="$TARGET_HOME/.config/qt6ct/qt6ct.conf"
  color_file="$(dms_qt_color_scheme_file)"

  write_user_file 0644 "$config_file" <<EOF
[Appearance]
color_scheme_path=$color_file
custom_palette=true
icon_theme=$(dms_icon_theme)
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
  install_kde_config_key General ColorScheme DankMatugen
  install_kde_config_key General Name DankMatugen
  install_kde_config_key KDE widgetStyle Fusion
  install_kde_config_key Icons Theme "$(dms_icon_theme)"
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
