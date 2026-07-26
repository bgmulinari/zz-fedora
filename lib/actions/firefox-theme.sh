#!/usr/bin/env bash
set -Eeuo pipefail

# Noctalia native messaging host and Firefox extension policy action.

FIREFOX_THEME_EXTENSION_ID="pywalfox@frewacom.org"
FIREFOX_THEME_EXTENSION_URL="https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"

firefox_theme_noctalia_bin() {
  command -v noctalia
}

firefox_theme_native_manifest() {
  printf '%s\n' "$TARGET_HOME/.mozilla/native-messaging-hosts/pywalfox.json"
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

# Noctalia claims any manifest whose host program is named after it and leaves
# every other host alone, rewriting its own in place from whichever binary is
# running. Mirror that ownership test instead of pinning one resolved path, so a
# manifest written by the running shell still verifies while a foreign host is
# still replaced.
firefox_theme_manifest_host_owned() {
  local host="$1"
  case "${host##*/}" in
    noctalia|noctalia-pywalfox) [[ -x "$host" ]] ;;
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

install_firefox_theme() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: register Noctalia Firefox theme host -> %s\n' "$(firefox_theme_native_manifest)"
    install_firefox_theme_policy
    return 0
  fi

  local executable
  if ! executable="$(firefox_theme_noctalia_bin)"; then
    log_warn "Noctalia is not installed; cannot register the Firefox theme host."
    return 1
  fi
  log_progress "Registering Noctalia Firefox theme host"
  run_cmd_as_user "$TARGET_USER" env HOME="$TARGET_HOME" "$executable" firefox-theme install || return 1
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
  jq -e \
    --arg extension_id "$FIREFOX_THEME_EXTENSION_ID" \
    --arg extension_url "$FIREFOX_THEME_EXTENSION_URL" \
    '(.policies.ExtensionSettings[$extension_id].installation_mode == "normal_installed")
      and (.policies.ExtensionSettings[$extension_id].install_url == $extension_url)' \
    "$policies_file" >/dev/null 2>&1
}

register_action "firefox-theme" install_firefox_theme firefox_theme_installed
