#!/usr/bin/env bash
set -Eeuo pipefail

# Shared path helpers and seed emitters for the managed DMS
# (DankMaterialShell) configuration. The state seeds, greeter staging, and
# doctor checks derive paths and theme facts from this single source so
# they cannot drift from each other.

dms_config_dir() {
  printf '%s/.config/DankMaterialShell\n' "$TARGET_HOME"
}

dms_state_dir() {
  printf '%s/.local/state/DankMaterialShell\n' "$TARGET_HOME"
}

dms_cache_dir() {
  printf '%s/.cache/DankMaterialShell\n' "$TARGET_HOME"
}

dms_settings_file() {
  printf '%s/settings.json\n' "$(dms_config_dir)"
}

dms_session_file() {
  printf '%s/session.json\n' "$(dms_state_dir)"
}

dms_colors_cache_file() {
  printf '%s/dms-colors.json\n' "$(dms_cache_dir)"
}

dms_theme_file() {
  printf '%s/themes/catppuccin/theme.json\n' "$(dms_config_dir)"
}

dms_default_wallpaper() {
  printf '%s/.local/share/backgrounds/CraterBlue.jpg\n' "$TARGET_HOME"
}

# Matugen template outputs the install consumes; DMS overwrites the seeded
# fallbacks at these exact paths.
dms_ghostty_theme_file() {
  printf '%s/.config/ghostty/themes/dankcolors\n' "$TARGET_HOME"
}

dms_qt_color_scheme_file() {
  printf '%s/.local/share/color-schemes/DankMatugen.colors\n' "$TARGET_HOME"
}

dms_icon_theme() {
  printf 'Yaru-blue\n'
}

# Partial settings seed: keys absent here fall back to the DMS defaults.
# Selects the vendored Catppuccin registry theme with the blue accent in
# both modes and aligns fonts and icon theme with the managed desktop.
dms_settings_seed_json() {
  jq -n --arg themeFile "$(dms_theme_file)" --arg iconTheme "$(dms_icon_theme)" '{
    currentThemeCategory: "registry",
    currentThemeName: "custom",
    customThemeFile: $themeFile,
    registryThemeVariants: {
      catppuccin: {
        dark: {flavor: "mocha", accent: "blue"},
        light: {flavor: "latte", accent: "blue"}
      }
    },
    monoFontFamily: "JetBrainsMono Nerd Font",
    iconThemeDark: $iconTheme,
    iconThemeLight: $iconTheme
  }'
}

# Partial session seed: pins the managed default wallpaper and dark mode.
dms_session_seed_json() {
  jq -n --arg wallpaper "$(dms_default_wallpaper)" '{
    wallpaperPath: $wallpaper,
    isLightMode: false
  }'
}

# Seed the DMS state files when absent: the partial settings and session
# seeds plus a '{}' colors placeholder that keeps the greeter cache
# symlink from dangling until the shell generates the real palette. Both
# the post-actions seeding and the greeter staging write through this
# single function, so whichever runs first lays down the real seeds and
# never a placeholder that would block them.
dms_seed_state_files_if_missing() {
  local destination

  destination="$(dms_settings_file)"
  if [[ ! -e "$destination" && ! -L "$destination" ]]; then
    log_progress "Seeding DMS settings"
    dms_settings_seed_json | write_user_file 0644 "$destination"
  fi

  destination="$(dms_session_file)"
  if [[ ! -e "$destination" && ! -L "$destination" ]]; then
    log_progress "Seeding DMS session state"
    dms_session_seed_json | write_user_file 0644 "$destination"
  fi

  destination="$(dms_colors_cache_file)"
  if [[ ! -e "$destination" && ! -L "$destination" ]]; then
    printf '{}\n' | write_user_file 0644 "$destination"
  fi
}
