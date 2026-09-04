#!/usr/bin/env bash
set -Eeuo pipefail

# Pywalfox native messaging host and Firefox extension policy action.
#
# DMS themes Firefox through Pywalfox: its matugen template renders
# ~/.cache/wal/dank-pywalfox.json and its post-hook runs `pywalfox update`
# whenever the theme changes. Fedora does not package the Pywalfox native
# host, so it is installed per-user with pip; the ~/.cache/wal/colors.json
# symlink is the upstream-documented bridge between the DMS template
# output and the palette file Pywalfox reads.

FIREFOX_THEME_EXTENSION_ID="pywalfox@frewacom.org"
FIREFOX_THEME_EXTENSION_URL="https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"

firefox_theme_native_manifest() {
  printf '%s\n' "$TARGET_HOME/.mozilla/native-messaging-hosts/pywalfox.json"
}

firefox_theme_wal_colors_link() {
  printf '%s\n' "$TARGET_HOME/.cache/wal/colors.json"
}

firefox_theme_wal_colors_target() {
  printf '%s\n' "$TARGET_HOME/.cache/wal/dank-pywalfox.json"
}

firefox_theme_policies_file() {
  printf '%s\n' "${ZZ_FIREFOX_POLICIES_FILE:-/etc/firefox/policies/policies.json}"
}

# Root is needed only where the destination is not already writable, so
# ZZ_FIREFOX_POLICIES_FILE stays a path override instead of also selecting the
# privilege the policy is installed with.
firefox_theme_policies_writable() {
  local target="$1" dir
  dir="$(dirname "$target")"
  while [[ ! -e "$dir" && "$dir" != "/" && "$dir" != "." ]]; do
    dir="$(dirname "$dir")"
  done
  [[ -w "$dir" ]] || return 1
  [[ ! -e "$target" || -w "$target" ]]
}

# Pywalfox rewrites its own manifest from whichever install is running, so
# accept any executable Pywalfox host instead of pinning one resolved path.
firefox_theme_manifest_host_owned() {
  local host="$1"
  case "${host##*/}" in
    pywalfox|pywalfox.py|pywalfox-daemon|main.py) [[ -e "$host" ]] ;;
    *) return 1 ;;
  esac
}

install_firefox_theme_policy() {
  local policies_file temp_file
  policies_file="$(firefox_theme_policies_file)"
  temp_file="$(mktemp "$CACHE_DIR/firefox-policies.XXXXXX")"

  if [[ -f "$policies_file" ]]; then
    if ! jq \
      --arg extension_id "$FIREFOX_THEME_EXTENSION_ID" \
      --arg extension_url "$FIREFOX_THEME_EXTENSION_URL" \
      '.policies = ((.policies // {}) + {
        ExtensionSettings: ((.policies.ExtensionSettings // {}) + {
          ($extension_id): {
            installation_mode: "normal_installed",
            install_url: $extension_url
          }
        })
      })' \
      "$policies_file" >"$temp_file"; then
      rm -f "$temp_file"
      return 1
    fi
  else
    jq -n \
      --arg extension_id "$FIREFOX_THEME_EXTENSION_ID" \
      --arg extension_url "$FIREFOX_THEME_EXTENSION_URL" \
      '{
        policies: {
          ExtensionSettings: {
            ($extension_id): {
              installation_mode: "normal_installed",
              install_url: $extension_url
            }
          }
        }
      }' >"$temp_file"
  fi

  if firefox_theme_policies_writable "$policies_file"; then
    run_cmd mkdir -p "$(dirname "$policies_file")"
    run_cmd install -m 0644 "$temp_file" "$policies_file"
  else
    run_cmd_as_root mkdir -p "$(dirname "$policies_file")"
    run_cmd_as_root install -m 0644 "$temp_file" "$policies_file"
  fi
  rm -f "$temp_file"
}

# The colors.json symlink may dangle until DMS renders its Pywalfox
# template; the DMS post-hook checks for the file before updating, so a
# dangling link simply defers theming to the first render. A pre-existing
# regular file is a standalone-pywal palette the user owns: back it up
# before the link replaces it.
install_firefox_theme_wal_link() {
  local link
  link="$(firefox_theme_wal_colors_link)"
  run_cmd_as_user "$TARGET_USER" mkdir -p "$TARGET_HOME/.cache/wal"
  if [[ -e "$link" && ! -L "$link" ]]; then
    backup_user_file_if_needed "$link"
  fi
  run_cmd_as_user "$TARGET_USER" ln -sfn "$(firefox_theme_wal_colors_target)" "$link"
}

install_firefox_theme() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install the Pywalfox native host with pip and register %s\n' "$(firefox_theme_native_manifest)"
    printf 'DRY-RUN: link %s -> %s\n' "$(firefox_theme_wal_colors_link)" "$(firefox_theme_wal_colors_target)"
    install_firefox_theme_policy
    return 0
  fi

  log_progress "Installing the Pywalfox native host"
  run_cmd_as_user "$TARGET_USER" env HOME="$TARGET_HOME" "$SYSTEM_PYTHON" -m pip install --user --quiet pywalfox || return 1
  # pip --user installs the entry point to ~/.local/bin, which is not on
  # the action runner's PATH, so name the executable explicitly instead of
  # letting the pywalfox installer search for it.
  run_cmd_as_user "$TARGET_USER" env HOME="$TARGET_HOME" "$SYSTEM_PYTHON" -m pywalfox install \
    --executable "$TARGET_HOME/.local/bin/pywalfox" || return 1
  install_firefox_theme_wal_link
  install_firefox_theme_policy
}

firefox_theme_installed() {
  local manifest manifest_host policies_file
  manifest="$(firefox_theme_native_manifest)"
  policies_file="$(firefox_theme_policies_file)"

  [[ -f "$manifest" && -f "$policies_file" ]] || return 1
  jq -e \
    --arg extension_id "$FIREFOX_THEME_EXTENSION_ID" \
    '(((.allowed_extensions // []) | index($extension_id))) != null' \
    "$manifest" >/dev/null 2>&1 || return 1
  manifest_host="$(jq -r '.path // empty' "$manifest" 2>/dev/null)"
  firefox_theme_manifest_host_owned "$manifest_host" || return 1
  [[ -L "$(firefox_theme_wal_colors_link)" ]] || return 1
  jq -e \
    --arg extension_id "$FIREFOX_THEME_EXTENSION_ID" \
    --arg extension_url "$FIREFOX_THEME_EXTENSION_URL" \
    '(.policies.ExtensionSettings[$extension_id].installation_mode == "normal_installed")
      and (.policies.ExtensionSettings[$extension_id].install_url == $extension_url)' \
    "$policies_file" >/dev/null 2>&1
}

register_action "firefox-theme" install_firefox_theme firefox_theme_installed
