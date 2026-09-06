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
# settings.json, keyed by plugin id. The base dms component seeds it once,
# rendered from the plugin seed template with the ids of every shipped
# plugin whose component is in the plan.
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

# Ids of shipped plugins whose component is not in the plan. The bar seed
# names every shipped widget and the plugin seed enables every shipped
# plugin so each default stays one file, but a plugin left out of the
# install must not leave its id behind: DMS lists an unresolved widget id
# as an unavailable entry in the bar editor, and a deselected choice must
# not be seeded as enabled. Without a plan (tests, ad hoc emitters) nothing
# is stripped.
dms_unplanned_plugin_ids() {
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
  dropped="$(dms_unplanned_plugin_ids | jq -R . | jq -sc .)"
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

dms_plugin_settings_seed_file() {
  printf '%s/templates/dms/plugin-settings-seed.json\n' "$ROOT_DIR"
}

# The plugin seed template enables every shipped plugin; the ids whose
# component the plan left out are dropped so a deselected choice seeds
# nothing for itself.
dms_plugin_settings_seed_json() {
  local dropped
  dropped="$(dms_unplanned_plugin_ids | jq -R . | jq -sc .)"
  jq --argjson dropped "$dropped" \
    'with_entries(select((.key as $id | $dropped | index($id)) == null))' \
    "$(dms_plugin_settings_seed_file)"
}

# Shipped plugin ids whose component the plan carries: the keys of the
# rendered plugin seed, in seed order.
dms_planned_plugin_ids() {
  dms_plugin_settings_seed_json | jq -r 'keys_unsorted[]'
}

# The plugin ids a managed-config component links into the DMS plugins
# directory (none for a component without a plugin).
dms_component_plugin_ids() {
  local wanted="$1" component path mode _conflict source _required _description
  while IFS=$'\t' read -r component path mode _conflict source _required _description; do
    [[ "$component" == "$wanted" ]] || continue
    # shellcheck disable=SC2088
    [[ "$mode" == "product-link" && "$path" == "~/.config/DankMaterialShell/plugins/"* ]] || continue
    [[ -f "$ROOT_DIR/$source/plugin.json" ]] || continue
    jq -r '.id // empty' "$ROOT_DIR/$source/plugin.json"
  done <"$(managed_config_policy_file)"
}

# Shipped plugin ids the live plugin_settings.json does not mention at all.
dms_missing_plugin_ids() {
  jq -r --slurpfile seed <(dms_plugin_settings_seed_json) \
    '. as $live | $seed[0] | keys[] as $id | select(($live | has($id)) | not) | $id' \
    "$(dms_plugin_settings_file)"
}

# Widgets ZZ has placed in this user's bar, one id per line. A placement
# happens once per plugin: a widget the user removes afterwards stays gone.
dms_placed_widgets_file() {
  printf '%s/dms-placed-widgets\n' "$STATE_DIR"
}

dms_widget_placed() {
  grep -Fxq -- "$1" "$(dms_placed_widgets_file)" 2>/dev/null
}

dms_mark_widget_placed() {
  local id="$1" marker
  marker="$(dms_placed_widgets_file)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: record placed DMS widget %s -> %s\n' "$id" "$marker"
    return 0
  fi
  mkdir -p "$(dirname "$marker")"
  printf '%s\n' "$id" >>"$marker"
}

# A plugin shipped after the seeds ran: add the ids the live file lacks as
# enabled and keep every key the user has set, disabled ones included.
dms_enable_missing_plugins() {
  local destination
  destination="$(dms_plugin_settings_file)"
  jq --slurpfile seed <(dms_plugin_settings_seed_json) \
    '. as $live | ($seed[0] | with_entries(.key as $id | select(($live | has($id)) | not))) + $live' \
    "$destination" | write_user_file 0644 "$destination"
}

# Insert each shipped bar widget the plan carries into the live bar the way
# the seed places it: before the first seed neighbor that follows it and is
# still in that section, else after the last preceding neighbor, else at
# the end. Entries may be plain ids or objects carrying an id; the bar is
# the one the seed describes ("default", else the first).
dms_bar_has_widget() {
  local settings="$1" id="$2"
  jq -e --arg id "$id" \
    '[.barConfigs // [] | .[] | (.leftWidgets // []) + (.centerWidgets // []) + (.rightWidgets // []) | .[] | if type == "object" then .id else . end] | index($id) != null' \
    "$settings" >/dev/null
}

dms_place_planned_widgets() {
  local settings seed id section seed_list
  settings="$(dms_settings_file)"
  [[ -f "$settings" ]] || return 0
  seed="$(dms_settings_seed_file)"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    dms_widget_placed "$id" && continue
    section="$(jq -r --arg id "$id" \
      '.barConfigs[0] | to_entries[] | select(.key | endswith("Widgets")) | select(.value | index($id) != null) | .key' "$seed")"
    # A plugin without a bar surface has nothing to place.
    [[ -n "$section" ]] || continue
    if dms_bar_has_widget "$settings" "$id"; then
      dms_mark_widget_placed "$id"
      continue
    fi
    log_progress "Placing the $id widget in the DMS bar"
    seed_list="$(jq -c --arg section "$section" '.barConfigs[0][$section]' "$seed")"
    jq --arg id "$id" --arg section "$section" --argjson seedList "$seed_list" '
      def wid: if type == "object" then .id else . end;
      def insert_at($list; $entry):
        ($list | map(wid)) as $ids
        | ($seedList | index($id)) as $at
        | ([$seedList[$at + 1:][] | . as $n | ($ids | index($n)) | select(. != null)] | first) as $before
        | ([$seedList[:$at][] | . as $n | ($ids | index($n)) | select(. != null)] | last) as $after
        | if $before != null then $list[:$before] + [$entry] + $list[$before:]
          elif $after != null then $list[:$after + 1] + [$entry] + $list[$after + 1:]
          else $list + [$entry] end;
      if ((.barConfigs // []) | length) == 0 then . else
        ((.barConfigs | map(.id) | index("default")) // 0) as $bar
        | .barConfigs[$bar][$section] = insert_at(.barConfigs[$bar][$section] // []; $id)
      end' "$settings" | write_user_file 0644 "$settings"
    # A file without a bar (DMS writes none while the bar is at its own
    # defaults) is left for a later apply rather than recorded as done.
    if [[ "$DRY_RUN" -eq 1 ]] || dms_bar_has_widget "$settings" "$id"; then
      dms_mark_widget_placed "$id"
    else
      log_info "The DMS bar is at its defaults; $id is placed once the shell writes one"
    fi
  done < <(dms_planned_plugin_ids)
}

dms_shell_answers() {
  run_cmd_as_user "$TARGET_USER" dms ipc call wallpaper get >/dev/null 2>&1
}

# When the target user's shell is up, load the plugins it just gained now
# rather than at the next login. The file already carries the flag, which
# is the default itself and needs no session; this is the live refresh a
# `zz update zz` or `zz app install` from the desktop expects, best effort:
# no session, no complaint.
dms_enable_plugins_in_session() {
  local id attempt
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  dms_shell_answers || return 0
  run_cmd_as_user "$TARGET_USER" dms ipc call plugin-scan scan >/dev/null 2>&1 || true
  for id in "$@"; do
    # The scan is debounced; give a directory linked moments ago a few
    # tries before leaving it to the next login.
    for ((attempt = 1; attempt <= 10; attempt++)); do
      run_cmd_as_user "$TARGET_USER" dms ipc call plugins enable "$id" 2>/dev/null | grep -q SUCCESS && break
      sleep 0.5
    done
    [[ "$attempt" -le 10 ]] || log_info "The DMS shell did not load $id; it loads at the next login"
  done
}

# Shipped plugins are on by default on every install, not only fresh ones:
# seed the enablement file when it is absent, else enable the ids it lacks,
# put their widgets in the bar once, and ask a running shell to load them.
# Seeding here rather than with the other state files keeps a first seed on
# a running desktop (a plugin choice added to an install that predates the
# file) from skipping that load.
dms_apply_plugin_defaults() {
  local -a missing=()
  local destination
  destination="$(dms_plugin_settings_file)"
  if [[ -e "$destination" || -L "$destination" ]]; then
    mapfile -t missing < <(dms_missing_plugin_ids)
    if [[ "${#missing[@]}" -gt 0 ]]; then
      log_progress "Enabling newly shipped DMS plugins"
      dms_enable_missing_plugins
    fi
  else
    log_progress "Seeding DMS plugin enablement"
    mapfile -t missing < <(dms_planned_plugin_ids)
    dms_plugin_settings_seed_json | write_user_file 0644 "$destination"
  fi
  dms_place_planned_widgets
  [[ "${#missing[@]}" -eq 0 ]] || dms_enable_plugins_in_session "${missing[@]}"
  return 0
}

# Undo a plugin's defaults before its directory goes: unload it from a
# running shell, drop its enablement key so a later re-add seeds it again,
# take its widget out of the bar, and forget the placement. The user's
# other settings stay as they are.
dms_forget_plugin() {
  local id="$1" plugins settings marker
  plugins="$(dms_plugin_settings_file)"
  settings="$(dms_settings_file)"
  marker="$(dms_placed_widgets_file)"
  if [[ "$DRY_RUN" -eq 0 ]] && dms_shell_answers; then
    run_cmd_as_user "$TARGET_USER" dms ipc call plugins disable "$id" >/dev/null 2>&1 || true
  fi
  if [[ -f "$plugins" ]] && jq -e --arg id "$id" 'has($id)' "$plugins" >/dev/null 2>&1; then
    log_progress "Forgetting the DMS plugin $id"
    jq --arg id "$id" 'del(.[$id])' "$plugins" | write_user_file 0644 "$plugins"
  fi
  if [[ -f "$settings" ]] && dms_bar_has_widget "$settings" "$id"; then
    log_progress "Removing the $id widget from the DMS bar"
    jq --arg id "$id" '
      def wid: if type == "object" then .id else . end;
      .barConfigs = ((.barConfigs // []) | map(
        .leftWidgets = ((.leftWidgets // []) | map(select(wid != $id)))
        | .centerWidgets = ((.centerWidgets // []) | map(select(wid != $id)))
        | .rightWidgets = ((.rightWidgets // []) | map(select(wid != $id)))))' \
      "$settings" | write_user_file 0644 "$settings"
  fi
  if dms_widget_placed "$id"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'DRY-RUN: forget placed DMS widget %s -> %s\n' "$id" "$marker"
    else
      grep -Fxv -- "$id" "$marker" >"$marker.next" || true
      mv "$marker.next" "$marker"
    fi
  fi
}

# Seed the DMS state files when absent: the partial settings and session
# seeds plus a '{}' colors placeholder that keeps the greeter cache
# symlink from dangling until the shell generates the real palette. Both
# the post-actions seeding and the greeter staging write through this
# single function, so whichever runs first lays down the real seeds and
# never a placeholder that would block them. Plugin enablement is
# dms_apply_plugin_defaults' file.
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
