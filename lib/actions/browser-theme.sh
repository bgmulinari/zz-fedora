#!/usr/bin/env bash
set -Eeuo pipefail

# Zen consumes DMS CSS; Chromium variants consume a root-owned color policy.
browser_theme_policy_dir() {
  case "$1" in
    chromium|helium) printf '/etc/chromium/policies/managed\n' ;;
    chrome) printf '/etc/opt/chrome/policies/managed\n' ;;
    brave) printf '/etc/brave/policies/managed\n' ;;
    *) return 1 ;;
  esac
}

browser_theme_current_color() {
  local palette="$TARGET_HOME/.cache/DankMaterialShell/browser-theme.color"
  local wal_palette="$TARGET_HOME/.cache/wal/dank-pywalfox.json" color=""
  # Removing the last Chromium browser removes its matugen drop-in. DMS's
  # built-in palette may then be newer than the browser-specific cache.
  if [[ -f "$wal_palette" && ( ! -f "$palette" || "$wal_palette" -nt "$palette" ) ]]; then
    color="$(jq -r '.colors.color0 // empty' "$wal_palette")" || return 1
  elif [[ -f "$palette" ]]; then
    color="$(<"$palette")"
  fi
  # Fresh installs have no rendered DMS palette yet. This is the shipped
  # default's background, replaced at the first DMS render.
  [[ -n "$color" ]] || color='#1e1e2e'
  [[ "$color" =~ ^#[0-9a-fA-F]{6}$ ]] || return 1
  printf '%s\n' "${color,,}"
}

install_browser_theme() {
  local browser="$1" directory color
  log_progress "Configuring $browser to follow the DMS theme"
  if [[ "$browser" == zen ]]; then
    run_cmd_as_user "$TARGET_USER" "$SYSTEM_PYTHON" "$ROOT_DIR/lib/browser_theme.py" \
      --home "$TARGET_HOME" zen
    return
  fi
  directory="$(browser_theme_policy_dir "$browser")" || return 1
  color="$(browser_theme_current_color)" || return 1
  run_cmd_as_user "$TARGET_USER" mkdir -p "$TARGET_HOME/.cache/DankMaterialShell" || return 1
  write_user_file 0644 "$TARGET_HOME/.cache/DankMaterialShell/browser-theme.color" <<EOF || return 1
$color
EOF
  run_cmd_as_root visudo -cf "$ROOT_DIR/dotfiles/browser-theme/sudoers" || return 1
  install_file_if_changed root "$ROOT_DIR/dotfiles/browser-theme/browser-theme-policy" \
    /usr/lib/zz/browser-theme-policy 0644 || return 1
  install_file_if_changed root "$ROOT_DIR/dotfiles/browser-theme/sudoers" \
    /etc/sudoers.d/zz-browser-theme 0440 || return 1
  write_root_file 0644 "$directory/zz-theme.json" <<EOF || return 1
{"BrowserThemeColor":"$color"}
EOF
  # Live refresh needs the user's session; an offline install simply leaves
  # the policy ready for the browser's first launch.
  if [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
    run_cmd_as_user "$TARGET_USER" env XDG_CACHE_HOME="$TARGET_HOME/.cache" \
      /usr/bin/bash "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-browser-theme" || return 1
  fi
}

browser_theme_installed() {
  if [[ "$1" == zen ]]; then
    "$SYSTEM_PYTHON" "$ROOT_DIR/lib/browser_theme.py" --home "$TARGET_HOME" --check zen
    return
  fi
  local directory
  directory="$(browser_theme_policy_dir "$1")" || return 1
  [[ -f /usr/lib/zz/browser-theme-policy && -f /etc/sudoers.d/zz-browser-theme ]] || return 1
  jq -e '.BrowserThemeColor | test("^#[0-9a-f]{6}$")' "$directory/zz-theme.json" >/dev/null
}

register_action "browser-theme" install_browser_theme browser_theme_installed
