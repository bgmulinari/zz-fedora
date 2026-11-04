#!/usr/bin/env bash
set -Eeuo pipefail

# T3 Code follows DMS through its published-theme API: the matugen drop-in
# keeps ~/.t3/userdata/themes/dms.json current, and `t3 theme set` selects it.
# The app writes its own `t3` launcher only at first launch, so the action runs
# the bundled CLI the same way that launcher does.

T3CODE_APP="/usr/bin/t3code"
T3CODE_CLI="/usr/lib64/t3code/resources/app.asar/apps/server/dist/bin.mjs"

t3code_home() {
  printf '%s\n' "$TARGET_HOME/.t3"
}

t3code_cli() {
  run_cmd_as_user "$TARGET_USER" env HOME="$TARGET_HOME" ELECTRON_RUN_AS_NODE=1 \
    "$T3CODE_APP" "$T3CODE_CLI" "$@" --base-dir "$(t3code_home)"
}

# DMS renders its templates only when the shell starts or the theme changes, so
# a choice added to a running desktop fills the template from the palette DMS
# last generated. Before the first render that file is an empty placeholder,
# which fails here and leaves the caller with the static fallback.
t3code_theme_from_dms_palette() {
  jq -Rrs --slurpfile dms "$(dms_colors_cache_file)" '
    $dms[0].mode as $mode
    | gsub("\\{\\{mode\\}\\}"; $mode)
    | gsub("\\{\\{colors\\.(?<role>[a-z_]+)\\.default\\.hex\\}\\}";
        $dms[0].colors[$mode][.role] // error("missing color role"))
  ' "$ROOT_DIR/dotfiles/dms/.config/matugen/templates/t3code-theme.json" 2>/dev/null
}

install_t3code_theme() {
  # The drop-in that keeps the palette current is user configuration, and a
  # theme nothing updates would be worse than T3 Code's own default.
  [[ "$SKIP_USER_CONFIG" -eq 1 ]] && return 0

  local theme
  log_progress "Configuring T3 Code to follow the DMS theme"
  theme="$(t3code_theme_from_dms_palette)" || theme="$(<"$ROOT_DIR/templates/t3code/dms.json")"
  write_user_file 0644 "$(dms_cache_dir)/t3code-theme.json" <<<"$theme" || return 1
  # Actions run before the managed links exist, so call the helper at its source.
  run_cmd_as_user "$TARGET_USER" env HOME="$TARGET_HOME" XDG_CACHE_HOME="$TARGET_HOME/.cache" \
    /usr/bin/bash "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-t3code-theme" || return 1

  # Every `theme set` makes clients switch again, even to the same id, so a
  # repeated run must not undo a theme chosen in the app since the last one.
  # Ask the CLI: settings.json may hold comments only T3 Code's parser accepts.
  if [[ "$DRY_RUN" -eq 0 ]]; then
    local status
    status="$(t3code_cli theme show)" || return 1
    [[ "$status" == *"Environment theme: not set."* ]] || return 0
  fi
  t3code_cli theme set dms
}

t3code_theme_installed() {
  [[ "$SKIP_USER_CONFIG" -eq 1 ]] && return 0
  jq -e '.appearance and .canvas and .accent' \
    "$(t3code_home)/userdata/themes/dms.json" >/dev/null 2>&1
}

register_action "t3code-theme" install_t3code_theme t3code_theme_installed
