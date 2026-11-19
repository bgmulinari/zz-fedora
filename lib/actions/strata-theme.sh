#!/usr/bin/env bash
set -Eeuo pipefail

# Strata follows DMS through a custom theme file: the matugen drop-in keeps
# ~/.config/strata/themes/dms.toml current and Strata rereads it in every open
# window. A Strata that starts without a valid theme of the selected id swaps
# in its fallback and saves that choice, so the selection is written only
# after the theme has been published, and only for a Strata with no settings
# yet: an existing settings.toml already holds the user's theme.
#
# The glass look is Strata's user stylesheet, the one restyling hook it reads.
# That file is the user's, so ZZ writes it only when it is missing, as a stub
# importing the product rules; the rules then update with the checkout.

strata_theme_file() {
  printf '%s/.config/strata/themes/dms.toml\n' "$TARGET_HOME"
}

strata_settings_file() {
  printf '%s/.config/strata/settings.toml\n' "$TARGET_HOME"
}

strata_style_file() {
  printf '%s/.config/strata/style.css\n' "$TARGET_HOME"
}

strata_style_stub() {
  printf '%s\n' \
    '/* Written by ZZ when Strata had no stylesheet; yours from now on. The import' \
    "   draws Strata as translucent glass over niri's blur. Delete it for opaque" \
    '   windows, and put your own rules below it. */' \
    "@import url(\"file://$ROOT_DIR/dotfiles/strata/glass.css\");"
}

# Missing means neither a file nor a dangling link the user left in place.
strata_user_file_missing() {
  [[ ! -e "$1" && ! -L "$1" ]]
}

install_strata_theme() {
  # The drop-in that keeps the palette current is user configuration, and a
  # theme nothing updates would be worse than Strata's own default.
  [[ "$SKIP_USER_CONFIG" -eq 1 ]] && return 0

  local theme
  log_progress "Configuring Strata to follow the DMS theme"
  theme="$(dms_render_palette_template "$ROOT_DIR/dotfiles/dms/.config/matugen/templates/strata-theme.toml")" ||
    theme="$(<"$ROOT_DIR/templates/strata/dms.toml")"
  write_user_file 0644 "$(dms_cache_dir)/strata-theme.toml" <<<"$theme" || return 1
  # Actions run before the managed links exist, so call the helper at its source.
  run_cmd_as_user "$TARGET_USER" env HOME="$TARGET_HOME" \
    XDG_CACHE_HOME="$TARGET_HOME/.cache" XDG_CONFIG_HOME="$TARGET_HOME/.config" \
    /usr/bin/bash "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-strata-theme" || return 1

  if strata_user_file_missing "$(strata_style_file)"; then
    strata_style_stub | write_user_file 0644 "$(strata_style_file)" || return 1
  fi

  strata_user_file_missing "$(strata_settings_file)" || return 0
  if [[ "$DRY_RUN" -eq 0 ]]; then
    strata_theme_installed || return 1
  fi
  write_user_file 0600 "$(strata_settings_file)" <"$ROOT_DIR/templates/strata/settings.toml"
}

strata_theme_installed() {
  [[ "$SKIP_USER_CONFIG" -eq 1 ]] && return 0
  local theme_file
  theme_file="$(strata_theme_file)"
  grep -Eq '^background = "#[0-9a-fA-F]{6}"$' "$theme_file" 2>/dev/null &&
    ! grep -Fq '{{' "$theme_file"
}

register_action "strata-theme" install_strata_theme strata_theme_installed
