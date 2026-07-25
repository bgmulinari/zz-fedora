#!/usr/bin/env bash
set -Eeuo pipefail

noctalia_template_apply_ack_file() {
  printf '%s/noctalia-template-apply.done\n' "$CACHE_DIR"
}

noctalia_state_home() {
  local state_home="${NOCTALIA_STATE_HOME:-${XDG_STATE_HOME:-$TARGET_HOME/.local/state}}"
  printf '%s/noctalia\n' "${state_home%/}"
}

noctalia_community_templates_ready() {
  local effective_config="$1"
  local state_home
  state_home="$(noctalia_state_home)"

  python3 - "$effective_config" "$state_home" <<'PY'
import json
import pathlib
import re
import sys
import tomllib

config_path = pathlib.Path(sys.argv[1])
state_home = pathlib.Path(sys.argv[2])

try:
    with config_path.open("rb") as config_file:
        config = tomllib.load(config_file)
except (OSError, tomllib.TOMLDecodeError):
    raise SystemExit(1)

templates = config.get("theme", {}).get("templates", {})
if not templates.get("enable_community_templates", False):
    raise SystemExit(0)

selected = templates.get("community_ids", [])
if not isinstance(selected, list) or not all(
    isinstance(template_id, str) and re.fullmatch(r"[A-Za-z0-9_.-]+", template_id)
    for template_id in selected
):
    raise SystemExit(1)
if not selected:
    raise SystemExit(0)

catalog_path = state_home / "community-templates" / "catalog.json"
try:
    catalog = json.loads(catalog_path.read_text())
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

if isinstance(catalog, dict):
    catalog = catalog.get("templates", catalog.get("entries", []))
if not isinstance(catalog, list):
    raise SystemExit(1)

catalog_by_id = {
    entry.get("name", entry.get("id")): entry
    for entry in catalog
    if isinstance(entry, dict)
}
for template_id in selected:
    entry = catalog_by_id.get(template_id)
    if not isinstance(entry, dict):
        raise SystemExit(1)
    template_dir = state_home / "community-templates" / template_id
    if not (template_dir / "template.toml").is_file():
        raise SystemExit(1)
    files = entry.get("files", [])
    if not isinstance(files, list):
        raise SystemExit(1)
    for file_entry in files:
        if not isinstance(file_entry, dict):
            raise SystemExit(1)
        relative_name = file_entry.get("name")
        if not isinstance(relative_name, str):
            raise SystemExit(1)
        relative_path = pathlib.PurePosixPath(relative_name)
        if relative_path.is_absolute() or any(part in ("", ".", "..") for part in relative_path.parts):
            raise SystemExit(1)
        if not (template_dir / relative_path).is_file():
            raise SystemExit(1)
PY
}

apply_noctalia_templates() {
  local attempt
  local ack_file config_snapshot
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: request and await Noctalia template application for the current theme\n'
    return 0
  fi

  # Noctalia owns the effective palette (including Settings UI overrides),
  # configured template set, and client applicability checks. Its
  # templates-apply IPC only queues work, so wait for the final managed user
  # template to acknowledge both the startup pass and the requested pass.
  ack_file="$(noctalia_template_apply_ack_file)"
  mkdir -p "$(dirname "$ack_file")"
  config_snapshot="$(mktemp "${TMPDIR:-/tmp}/zz-noctalia-config.XXXXXX")"
  log_progress "Waiting for Noctalia template readiness"
  for ((attempt = 1; attempt <= 120; attempt++)); do
    if run_cmd_as_user "$TARGET_USER" noctalia msg color-scheme-get >/dev/null 2>&1 &&
      [[ -f "$ack_file" ]] &&
      run_cmd_as_user "$TARGET_USER" noctalia config export full >"$config_snapshot" 2>/dev/null &&
      noctalia_community_templates_ready "$config_snapshot"; then
      break
    fi
    sleep 0.25
  done
  if [[ "$attempt" -gt 120 ]]; then
    rm -f "$config_snapshot"
    log_warn "Noctalia templates were not ready; retrying at next login"
    return 1
  fi

  rm -f "$config_snapshot" ||
    log_warn "Could not remove the Noctalia config snapshot: $config_snapshot"
  if ! rm -f "$ack_file"; then
    log_warn "Could not clear the Noctalia template acknowledgment; retrying at next login"
    return 1
  fi
  log_progress "Requesting Noctalia template application"
  if ! run_cmd_as_user "$TARGET_USER" noctalia msg templates-apply >/dev/null 2>&1; then
    log_warn "Noctalia did not accept the template-apply request; retrying at next login"
    return 1
  fi

  for ((attempt = 1; attempt <= 120; attempt++)); do
    [[ -f "$ack_file" ]] && return 0
    sleep 0.25
  done

  log_warn "Noctalia did not finish applying templates; retrying at next login"
  return 1
}

first_run_enable_session_services() {
  local failed=0
  run_cmd_as_user "$TARGET_USER" systemctl --user daemon-reload || failed=1
  enable_user_services strict || failed=1
  return "$failed"
}

first_run_update_user_directories() {
  run_cmd_as_user "$TARGET_USER" xdg-user-dirs-update || true
}

first_run_apply_desktop_interface() {
  if [[ "$(resolved_desktop_app_profile)" == "full" ]]; then
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark || true
    run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
  fi
}

first_run_session_services_fingerprint() {
  first_run_files_fingerprint "$PLAN_DIR/services/user-enable.list"
}

first_run_desktop_interface_fingerprint() {
  printf 'desktop_app_profile=%s\n' "$(resolved_desktop_app_profile)" |
    first_run_fingerprint
}

first_run_desktop_defaults_fingerprint() {
  {
    printf 'desktop_app_profile=%s\n' "$(resolved_desktop_app_profile)"
    printf 'preferred_browser=%s\n' "$PREFERRED_BROWSER"
    printf 'update_mode=%s\n' "$UPDATE_MODE"
    printf 'browser_choices\n'
    effective_choice_ids "browsers"
    first_run_files_fingerprint \
      "$ROOT_DIR/config/default-applications.tsv" \
      "$PLAN_DIR/bundles.list" \
      "$(package_file_for_backend "$(native_backend)")" \
      "$(package_file_for_backend flatpak)"
  } | first_run_fingerprint
}

mark_first_run_complete() {
  local marker
  marker="$(first_run_marker)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: mark first-run complete -> %s\n' "$marker"
    return 0
  fi
  mkdir -p "$(dirname "$marker")"
  printf 'completed_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >"$marker"
}

module_85_first_run() {
  local marker failed=0
  local session_services_fingerprint desktop_interface_fingerprint desktop_defaults_fingerprint
  marker="$(first_run_marker)"

  session_services_fingerprint="$(first_run_session_services_fingerprint)"
  desktop_interface_fingerprint="$(first_run_desktop_interface_fingerprint)"
  desktop_defaults_fingerprint="$(first_run_desktop_defaults_fingerprint)"
  if [[ -f "$marker" && "${ZZ_FIRST_RUN_FORCE:-0}" -ne 1 ]] &&
    first_run_action_completed session-services "$session_services_fingerprint" &&
    first_run_action_completed user-directories &&
    first_run_action_completed desktop-interface "$desktop_interface_fingerprint" &&
    first_run_action_completed desktop-defaults "$desktop_defaults_fingerprint" &&
    first_run_action_completed noctalia-templates; then
    log_info "First-run tasks already completed: $marker"
    # A deferred Flatpak queue can appear after first-run already completed
    # (an install re-run in a sandbox-restricted environment re-registers
    # the hook); consume it and clear the hook instead of stranding both.
    install_deferred_flatpaks || return 1
    remove_first_run_hook
    return 0
  fi

  # These actions are independent checkpoints. A failure keeps the aggregate
  # first-run hook active, but successful actions are never repeated merely
  # because another action (including deferred Flatpaks) still needs a retry.
  run_first_run_action_once_for_input \
    session-services "$session_services_fingerprint" first_run_enable_session_services || failed=1
  run_first_run_action_once user-directories first_run_update_user_directories || failed=1
  run_first_run_action_once_for_input \
    desktop-interface "$desktop_interface_fingerprint" first_run_apply_desktop_interface || failed=1
  run_first_run_action_once_for_input \
    desktop-defaults "$desktop_defaults_fingerprint" apply_desktop_defaults || failed=1
  run_first_run_action_once noctalia-templates apply_noctalia_templates || failed=1

  # The deferred list and its per-app removal are already the Flatpak action's
  # durable checkpoint, including support for a new queue after first-run.
  install_deferred_flatpaks || failed=1

  [[ "$failed" -eq 0 ]] || return 1
  mark_first_run_complete
  remove_first_run_hook
}
