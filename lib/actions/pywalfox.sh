#!/usr/bin/env bash
set -Eeuo pipefail

# Pywalfox native messaging host and Firefox extension policy action.

PYWALFOX_EXTENSION_ID="pywalfox@frewacom.org"
PYWALFOX_EXTENSION_URL="https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"

pywalfox_bin() {
  printf '%s\n' "$TARGET_HOME/.local/bin/pywalfox"
}

pywalfox_native_manifest() {
  printf '%s\n' "$TARGET_HOME/.mozilla/native-messaging-hosts/pywalfox.json"
}

firefox_policies_file() {
  printf '%s\n' "${FIREFOX_POLICIES_FILE:-/etc/firefox/policies/policies.json}"
}

install_firefox_pywalfox_policy() {
  local policies_file temp_file
  policies_file="$(firefox_policies_file)"
  temp_file="$(mktemp "$CACHE_DIR/firefox-policies.XXXXXX")"

  if [[ -f "$policies_file" ]]; then
    if ! jq \
      --arg extension_id "$PYWALFOX_EXTENSION_ID" \
      --arg extension_url "$PYWALFOX_EXTENSION_URL" \
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
      --arg extension_id "$PYWALFOX_EXTENSION_ID" \
      --arg extension_url "$PYWALFOX_EXTENSION_URL" \
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

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Firefox Pywalfox extension policy -> %s\n' "$policies_file"
    rm -f "$temp_file"
    return 0
  fi

  if [[ -n "${FIREFOX_POLICIES_FILE:-}" ]]; then
    run_cmd mkdir -p "$(dirname "$policies_file")"
    run_cmd install -m 0644 "$temp_file" "$policies_file"
  else
    run_cmd_as_root mkdir -p "$(dirname "$policies_file")"
    run_cmd_as_root install -m 0644 "$temp_file" "$policies_file"
  fi
  rm -f "$temp_file"
}

install_pywalfox() {
  local executable
  executable="$(pywalfox_bin)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install or upgrade Pywalfox with pipx for %s\n' "$TARGET_USER"
    printf 'DRY-RUN: register Pywalfox native messaging host -> %s\n' "$(pywalfox_native_manifest)"
    install_firefox_pywalfox_policy
    return 0
  fi

  log_progress "Installing Pywalfox native messaging host"
  run_user_login_shell "pipx upgrade pywalfox || pipx install --force pywalfox" || return 1
  [[ -x "$executable" ]] || {
    log_warn "Pywalfox installation did not create $executable."
    return 1
  }
  run_cmd_as_user "$TARGET_USER" "$executable" install --executable "$executable" || return 1
  install_firefox_pywalfox_policy
}

pywalfox_installed() {
  local executable manifest policies_file
  executable="$(pywalfox_bin)"
  manifest="$(pywalfox_native_manifest)"
  policies_file="$(firefox_policies_file)"

  [[ -x "$executable" && -f "$manifest" && -f "$policies_file" ]] || return 1
  jq -e \
    --arg executable "$executable" \
    --arg extension_id "$PYWALFOX_EXTENSION_ID" \
    '(.path == $executable)
      and ((((.allowed_extensions // []) | index($extension_id))) != null)' \
    "$manifest" >/dev/null 2>&1 || return 1
  jq -e \
    --arg extension_id "$PYWALFOX_EXTENSION_ID" \
    --arg extension_url "$PYWALFOX_EXTENSION_URL" \
    '(.policies.ExtensionSettings[$extension_id].installation_mode == "normal_installed")
      and (.policies.ExtensionSettings[$extension_id].install_url == $extension_url)' \
    "$policies_file" >/dev/null 2>&1
}

register_action "pywalfox" install_pywalfox pywalfox_installed
