#!/usr/bin/env bash
set -Eeuo pipefail

# Desktop default-application, MIME, and browser helpers shared by
# first-run and post-action steps.

browser_desktop_file() {
  case "$1" in
    firefox) printf 'firefox.desktop\n' ;;
    chromium) printf 'chromium.desktop\n' ;;
    chrome) printf 'google-chrome.desktop\n' ;;
    brave) printf 'brave-browser.desktop\n' ;;
    zen-copr) printf 'zen.desktop\n' ;;
    helium|helium-copr) printf 'helium.desktop\n' ;;
    *) return 1 ;;
  esac
}

desktop_file_installed_for_user() {
  local desktop_file="$1"
  [[ -f "$TARGET_HOME/.local/share/applications/$desktop_file" ]] && return 0
  [[ -f "/usr/local/share/applications/$desktop_file" ]] && return 0
  [[ -f "/usr/share/applications/$desktop_file" ]] && return 0
  return 1
}

package_available_for_default_app() {
  local package_name="$1"
  local native_plan flatpak_plan
  native_plan="$(package_file_for_backend "$(native_backend)")"
  flatpak_plan="$(package_file_for_backend flatpak)"

  plan_has_any_backend_entry "$native_plan" "$package_name" && return 0
  plan_has_any_backend_entry "$flatpak_plan" "$package_name" && return 0
  [[ "$DRY_RUN" -eq 1 ]] && return 1

  if declare -F fedora_package_installed >/dev/null 2>&1 && fedora_package_installed "$package_name"; then
    return 0
  fi
  if have_cmd flatpak && flatpak info "$package_name" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

default_app_condition_met() {
  local desktop_file="$1"
  local condition="$2"
  case "$condition" in
    always)
      return 0
      ;;
    package:*)
      package_available_for_default_app "${condition#package:}"
      ;;
    desktop-installed)
      [[ "$DRY_RUN" -eq 1 ]] && return 1
      desktop_file_installed_for_user "$desktop_file"
      ;;
    *)
      die "Unsupported default application condition: $condition"
      ;;
  esac
}

configure_default_applications_from_tsv() {
  local defaults_file="$ROOT_DIR/config/default-applications.tsv"
  local desktop_file condition mime_type extra
  [[ -f "$defaults_file" ]] || die "Missing default applications config: $defaults_file"

  log_progress "Configuring default applications"
  while IFS=$'\t' read -r desktop_file condition mime_type extra || [[ -n "$desktop_file" ]]; do
    [[ -n "$desktop_file" ]] || continue
    [[ "$desktop_file" == \#* ]] && continue
    [[ -z "${extra:-}" && -n "$condition" && -n "$mime_type" ]] || die "Malformed default applications row: $desktop_file"
    default_app_condition_met "$desktop_file" "$condition" || continue
    run_cmd_as_user "$TARGET_USER" xdg-mime default "$desktop_file" "$mime_type" || true
  done <"$defaults_file"
}

configure_xdg_terminal_defaults() {
  local terminals_file="$TARGET_HOME/.config/xdg-terminals.list"
  local temp_file

  log_progress "Configuring default terminal preference"
  temp_file="$(mktemp "$CACHE_DIR/xdg-terminals.XXXXXX")"
  cat >"$temp_file" <<'EOF'
# Terminal emulator preference order for xdg-terminal-exec
# The first found and valid terminal will be used
com.mitchellh.ghostty.desktop
Alacritty.desktop
kitty.desktop
org.gnome.Console.desktop
org.gnome.Terminal.desktop
EOF
  chmod 0644 "$temp_file"
  install_file_if_changed user "$temp_file" "$terminals_file"
  rm -f "$temp_file"
}

configure_default_applications() {
  if [[ "$(resolved_desktop_app_profile)" == "full" ]]; then
    configure_default_applications_from_tsv
  else
    log_info "Skipping full desktop default applications for desktop app profile: $(resolved_desktop_app_profile)"
  fi
  configure_xdg_terminal_defaults
}

set_default_browser() {
  local desktop_file="$1"
  local -a browser_mime_types=(
    text/html
    application/xhtml+xml
    x-scheme-handler/http
    x-scheme-handler/https
  )
  local mime_type failed=0

  log_progress "Setting default browser: $desktop_file"
  for mime_type in "${browser_mime_types[@]}"; do
    run_cmd_as_user "$TARGET_USER" xdg-mime default "$desktop_file" "$mime_type" || failed=1
  done

  if run_cmd_as_user "$TARGET_USER" xdg-settings set default-web-browser "$desktop_file"; then
    return 0
  fi

  [[ "$failed" -eq 0 ]] && return 0
  log_warn "Could not set default browser to $desktop_file"
}

configure_selected_browser_default() {
  local -a browsers=()
  while IFS= read -r browser; do
    [[ -n "$browser" ]] && browsers+=("$browser")
  done < <(effective_choice_ids "browsers")

  local browser_choice=""
  if [[ -n "$PREFERRED_BROWSER" ]]; then
    browser_choice="$PREFERRED_BROWSER"
  elif [[ "${#browsers[@]}" -eq 1 ]]; then
    browser_choice="${browsers[0]}"
  fi
  if [[ -n "$browser_choice" ]]; then
    local desktop_file=""
    desktop_file="$(browser_desktop_file "$browser_choice" || true)"
    if [[ -n "$desktop_file" ]]; then
      set_default_browser "$desktop_file"
    fi
  fi
}

apply_desktop_defaults() {
  configure_default_applications
  configure_selected_browser_default
}
