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

# DMS 1.6 keeps plugin enablement and per-plugin settings apart from
# settings.json, keyed by plugin id. Each shipped plugin's component seeds
# it through an ordinary managed-config row; this path only feeds the doctor.
dms_plugin_settings_file() {
  printf '%s/plugin_settings.json\n' "$(dms_config_dir)"
}

dms_colors_cache_file() {
  printf '%s/dms-colors.json\n' "$(dms_cache_dir)"
}

dms_theme_file() {
  printf '%s/themes/catppuccin/theme.json\n' "$(dms_config_dir)"
}

dms_default_wallpaper() {
  printf '%s/.local/share/backgrounds/Alpenglow.jpg\n' "$TARGET_HOME"
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

# DMS 1.6 embeds the shell payload in the dms binary and materializes it under
# XDG_RUNTIME_DIR. Ask the CLI for the path it actually resolved rather than
# relying on the pre-1.6 /usr/share/quickshell/dms package layout. The payload's
# scripts/ directory carries the upstream gtk.sh/qt.sh appliers the Settings UI
# buttons invoke, and Common/settings carries the specs used by the seed diff.
dms_shell_dir() {
  local doctor_json shell_dir

  command -v dms >/dev/null 2>&1 || return 1
  if declare -F run_cmd_as_user >/dev/null 2>&1 && [[ -n "${TARGET_USER:-}" ]]; then
    doctor_json="$(run_cmd_as_user "$TARGET_USER" dms doctor --json 2>/dev/null)" || return 1
  else
    doctor_json="$(dms doctor --json 2>/dev/null)" || return 1
  fi

  shell_dir="$(jq -er '
    first(
      .results[]
      | select(
          .category == "Installation"
          and .name == "DMS Configuration"
          and .status == "ok"
          and (.details | type == "string" and length > 0)
        )
      | .details
    )
  ' <<<"$doctor_json")" || return 1
  [[ -f "$shell_dir/shell.qml" ]] || return 1
  printf '%s\n' "$shell_dir"
}

# Portable seed values live in templates/dms/{settings,session}-seed.json so
# scripts/dms-seed-diff.sh can promote a live DMS change into them as a plain
# JSON edit. Keys absent from a seed fall back to the DMS defaults.
#
# Keys that render to absolute paths under $TARGET_HOME stay out of those
# files and are overlaid below, so the helpers remain the source for them.
#
# Niri gaps live in cfg/layout.kdl, not here; niriLayoutGapsOverride = -2 is
# what makes DMS defer to that file. Border width has no such off mode, so it
# is DMS-owned and only niriLayoutBorderSize can change it.
dms_settings_seed_file() {
  printf '%s/templates/dms/settings-seed.json\n' "$ROOT_DIR"
}

dms_session_seed_file() {
  printf '%s/templates/dms/session-seed.json\n' "$ROOT_DIR"
}

# Widget ids of shipped plugins whose component is not in the plan. The bar
# seed names every shipped widget so the default layout stays one file, but
# a plugin left out of the install must not leave its id behind: DMS lists
# an unresolved widget id as an unavailable entry in the bar editor. Without
# a plan (tests, ad hoc emitters) nothing is stripped.
dms_unplanned_plugin_widget_ids() {
  local components_file="${PLAN_DIR:-}/config/components.list"
  [[ -n "${PLAN_DIR:-}" && -f "$components_file" ]] || return 0
  local component path mode _conflict source _required _description
  while IFS=$'\t' read -r component path mode _conflict source _required _description; do
    # Managed-config paths are written with a literal ~/ prefix.
    # shellcheck disable=SC2088
    [[ "$mode" == "product-link" && "$path" == "~/.config/DankMaterialShell/plugins/"* ]] || continue
    [[ -f "$ROOT_DIR/$source/plugin.json" ]] || continue
    grep -Fxq -- "$component" "$components_file" && continue
    jq -r '.id // empty' "$ROOT_DIR/$source/plugin.json"
  done <"$(managed_config_policy_file)"
}

dms_settings_seed_json() {
  local dropped
  dropped="$(dms_unplanned_plugin_widget_ids | jq -R . | jq -sc .)"
  jq \
    --arg themeFile "$(dms_theme_file)" \
    --arg iconTheme "$(dms_icon_theme)" \
    --argjson dropped "$dropped" \
    'def keep: map(select(((if type == "object" then .id else . end) as $w | $dropped | index($w)) == null));
    . + {
      customThemeFile: $themeFile,
      iconThemeDark: $iconTheme,
      iconThemeLight: $iconTheme
    }
    | if ($dropped | length) > 0 then
        .barConfigs = ((.barConfigs // []) | map(
          .leftWidgets = ((.leftWidgets // []) | keep)
          | .centerWidgets = ((.centerWidgets // []) | keep)
          | .rightWidgets = ((.rightWidgets // []) | keep)))
      else . end' "$(dms_settings_seed_file)"
}

dms_session_seed_json() {
  jq --arg wallpaper "$(dms_default_wallpaper)" \
    '. + {wallpaperPath: $wallpaper}' "$(dms_session_seed_file)"
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
