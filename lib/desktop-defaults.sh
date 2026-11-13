#!/usr/bin/env bash
set -Eeuo pipefail

# Desktop default-application, MIME, and browser helpers shared by
# first-run and post-action steps.

browser_desktop_file() {
  case "$1" in
    firefox) printf 'org.mozilla.firefox.desktop\n' ;;
    chromium) printf 'chromium-browser.desktop\n' ;;
    chrome) printf 'google-chrome.desktop\n' ;;
    brave) printf 'brave-browser.desktop\n' ;;
    zen) printf 'zen-browser.desktop\n' ;;
    helium) printf 'helium.desktop\n' ;;
    *) return 1 ;;
  esac
}

desktop_file_installed_for_user() {
  local desktop_file="$1"
  [[ -f "$TARGET_HOME/.local/share/applications/$desktop_file" ]] && return 0
  [[ -f "$TARGET_HOME/.local/share/flatpak/exports/share/applications/$desktop_file" ]] && return 0
  [[ -f "/usr/local/share/applications/$desktop_file" ]] && return 0
  [[ -f "/usr/share/applications/$desktop_file" ]] && return 0
  [[ -f "/var/lib/flatpak/exports/share/applications/$desktop_file" ]] && return 0
  return 1
}

package_available_for_default_app() {
  local package_name="$1"
  local native_plan flatpak_plan
  native_plan="$(package_file_for_backend "$(native_backend)")"
  flatpak_plan="$(package_file_for_backend flatpak)"

  if [[ "${UPDATE_MODE:-0}" -eq 0 ]]; then
    plan_has_any_backend_entry "$native_plan" "$package_name" && return 0
    plan_has_any_backend_entry "$flatpak_plan" "$package_name" && return 0
    [[ "$DRY_RUN" -eq 1 ]] && return 1
  fi

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

# ZZ applies a default only when its own intent for that key changes: a newly
# installed app, or a different selected browser. Every run re-evaluates the
# intents (first-run whenever its inputs change, post-actions on every
# install), so reasserting an unchanged one would undo a default the user has
# since picked elsewhere, such as DMS Settings > Default Apps. The record maps
# each key (a MIME type, or web-browser) to the desktop file last applied for
# it; `zz defaults` sets REAPPLY_DEFAULTS to apply every intent regardless.
declare -gA APPLIED_DEFAULTS=()

applied_defaults_file() {
  printf '%s\n' "$STATE_DIR/applied-defaults.tsv"
}

load_applied_defaults() {
  local file key desktop_file
  file="$(applied_defaults_file)"
  APPLIED_DEFAULTS=()
  [[ -f "$file" ]] || return 0
  while IFS=$'\t' read -r key desktop_file || [[ -n "$key" ]]; do
    if [[ -n "$key" && -n "$desktop_file" ]]; then
      APPLIED_DEFAULTS["$key"]="$desktop_file"
    fi
  done <"$file"
}

save_applied_defaults() {
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  local file key
  file="$(applied_defaults_file)"
  mkdir -p "$(dirname "$file")"
  for key in "${!APPLIED_DEFAULTS[@]}"; do
    printf '%s\t%s\n' "$key" "${APPLIED_DEFAULTS[$key]}"
  done | LC_ALL=C sort >"$file.tmp"
  mv -f "$file.tmp" "$file"
  chown_state_path_to_owner "$file"
}

# A default naming a missing desktop file is worse than none: GIO skips it,
# but xdg-open (generic mode under niri) falls through to the alphabetical
# mimeinfo.cache, where any app claiming the type wins. Only a dry-run install
# previews defaults for apps it has not installed yet.
default_app_target_present() {
  local desktop_file="$1"
  [[ "$DRY_RUN" -eq 1 && "${UPDATE_MODE:-0}" -eq 0 ]] && return 0
  desktop_file_installed_for_user "$desktop_file"
}

# Forgets an applied default whose app is gone, so installing it again
# applies it again instead of matching the stale record.
forget_applied_default() {
  unset 'APPLIED_DEFAULTS[$1]'
}

# Drops every applied default whose app is no longer installed. A choice
# removal runs no defaults pass, so without this the reinstall that follows
# would match the stale record and skip making the app the default again.
prune_applied_defaults() {
  local key
  load_applied_defaults
  for key in "${!APPLIED_DEFAULTS[@]}"; do
    desktop_file_installed_for_user "${APPLIED_DEFAULTS[$key]}" || forget_applied_default "$key"
  done
  save_applied_defaults
}

# Succeeds when the intent for key is already applied and need not be again.
applied_default_current() {
  local key="$1"
  local desktop_file="$2"
  [[ "${REAPPLY_DEFAULTS:-0}" -ne 1 ]] || return 1
  [[ "${APPLIED_DEFAULTS[$key]:-}" == "$desktop_file" ]]
}

record_applied_default() {
  local key="$1"
  local desktop_file="$2"
  APPLIED_DEFAULTS["$key"]="$desktop_file"
  save_applied_defaults
}

configure_default_applications_from_tsv() {
  local defaults_file="$ROOT_DIR/config/default-applications.tsv"
  local desktop_file condition mime_type extra skipped=0
  [[ -f "$defaults_file" ]] || die "Missing default applications config: $defaults_file"

  log_progress "Configuring default applications"
  load_applied_defaults
  while IFS=$'\t' read -r desktop_file condition mime_type extra || [[ -n "$desktop_file" ]]; do
    [[ -n "$desktop_file" ]] || continue
    [[ "$desktop_file" == \#* ]] && continue
    [[ -z "${extra:-}" && -n "$condition" && -n "$mime_type" ]] || die "Malformed default applications row: $desktop_file"
    if ! default_app_condition_met "$desktop_file" "$condition" ||
      ! default_app_target_present "$desktop_file"; then
      forget_applied_default "$mime_type"
      continue
    fi
    if applied_default_current "$mime_type" "$desktop_file"; then
      skipped=$((skipped + 1))
      continue
    fi
    if run_cmd_as_user "$TARGET_USER" xdg-mime default "$desktop_file" "$mime_type"; then
      APPLIED_DEFAULTS["$mime_type"]="$desktop_file"
    fi
  done <"$defaults_file"
  [[ "$skipped" -eq 0 ]] || log_info "Left $skipped default application(s) as they are: ZZ already applied them"
  save_applied_defaults
}

configure_xdg_terminal_defaults() {
  local terminals_file="$TARGET_HOME/.config/xdg-terminals.list"

  # DMS Settings > Default Apps reads this file as a single desktop ID (it
  # takes the whole trimmed file contents as the current value and rewrites
  # it as one line when the user picks a terminal), so keep it to exactly one
  # entry with no comments. xdg-terminal-exec falls back to any installed
  # TerminalEmulator entry on its own when this one is missing.
  log_progress "Configuring default terminal preference"
  write_user_file 0644 "$terminals_file" <<'EOF'
com.mitchellh.ghostty.desktop
EOF
}

configure_default_applications() {
  local failed=0
  if [[ "$(resolved_desktop_app_profile)" == "full" ]]; then
    configure_default_applications_from_tsv || failed=1
  else
    log_info "Skipping full desktop default applications for desktop app profile: $(resolved_desktop_app_profile)"
  fi
  configure_xdg_terminal_defaults || failed=1
  return "$failed"
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

  local settings_ok=0
  run_cmd_as_user "$TARGET_USER" xdg-settings set default-web-browser "$desktop_file" && settings_ok=1
  # Recorded only once every MIME type took, so a failed one is retried.
  if [[ "$failed" -eq 0 ]]; then
    record_applied_default web-browser "$desktop_file"
    return 0
  fi
  [[ "$settings_ok" -eq 1 ]] && return 0

  log_warn "Could not set default browser to $desktop_file"
}

# The desktop file of the browser ZZ makes the default: the preferred one, or
# the only selected one. Prints nothing when there is none to choose.
selected_browser_desktop_file() {
  local -a browsers=()
  local browser browser_choice=""
  while IFS= read -r browser; do
    [[ -n "$browser" ]] && browsers+=("$browser")
  done < <(effective_choice_ids "browsers")

  if [[ -n "$PREFERRED_BROWSER" ]]; then
    browser_choice="$PREFERRED_BROWSER"
  elif [[ "${#browsers[@]}" -eq 1 ]]; then
    browser_choice="${browsers[0]}"
  fi
  [[ -n "$browser_choice" ]] || return 0
  browser_desktop_file "$browser_choice" || true
}

configure_selected_browser_default() {
  local desktop_file
  desktop_file="$(selected_browser_desktop_file)"
  load_applied_defaults
  if [[ -z "$desktop_file" ]]; then
    forget_applied_default web-browser
    save_applied_defaults
    return 0
  fi
  if ! default_app_target_present "$desktop_file"; then
    log_info "Preserving browser defaults because the selected browser is not installed: $desktop_file"
    forget_applied_default web-browser
    save_applied_defaults
    return 0
  fi
  if applied_default_current web-browser "$desktop_file"; then
    log_info "Leaving the default browser as it is: ZZ already set $desktop_file"
    return 0
  fi
  set_default_browser "$desktop_file"
}

apply_desktop_defaults() {
  local failed=0
  configure_default_applications || failed=1
  configure_selected_browser_default || failed=1
  return "$failed"
}
