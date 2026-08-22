#!/usr/bin/env bash
set -Eeuo pipefail

# DMS Greeter (greetd) custom action.
#
# The dms-greeter RPM owns the heavy lifting: its scriptlets create the
# greeter user, set SELinux contexts, ensure /etc/pam.d/greetd, write or
# repair /etc/greetd/config.toml, and set graphical.target. This action
# installs the package from the pinned COPR, re-asserts the greetd session
# config, grants the greeter user read access to the target user's DMS
# theme state (upstream `dms-greeter enable`/`sync` run as the invoking
# user, so they cannot be used from the root install path), and enables
# greetd as the fallback graphical login.

DMS_GREETER_COPR_PROJECT="avengemedia/danklinux"
DMS_GREETER_PACKAGE="dms-greeter"
DMS_GREETER_USER="greeter"
DMS_GREETER_CACHE_DIR="/var/cache/dms-greeter"
DMS_GREETD_CONFIG="/etc/greetd/config.toml"

dms_greeter_action_skipped() {
  local skip_file="$PLAN_DIR/system-skips.tsv"
  [[ -f "$skip_file" ]] || return 1
  awk -F'\t' '$1 == "action" && $2 == "dms-greeter" { found = 1 } END { exit !found }' "$skip_file"
}

# The user-facing theme sync is best-effort: when the target user's config
# is off-limits (--skip-user-config), the greeter keeps its own defaults
# rather than failing the install. Skips are recorded so verification
# accepts the absent access grants and symlinks.
dms_greeter_user_sync_skipped() {
  local skip_file="$PLAN_DIR/system-skips.tsv"
  [[ -f "$skip_file" ]] || return 1
  awk -F'\t' '$1 == "action" && $2 == "dms-greeter-user-sync" { found = 1 } END { exit !found }' "$skip_file"
}

dms_greeter_skip_user_sync() {
  record_system_skip action dms-greeter-user-sync "$1"
}

dms_greeter_copr_repo() {
  fedora_copr_repo_id "$DMS_GREETER_COPR_PROJECT"
}

install_dms_greeter_package() {
  log_progress "Installing or syncing DMS Greeter"
  if rpm -q "$DMS_GREETER_PACKAGE" >/dev/null 2>&1; then
    run_cmd_as_root dnf distro-sync -y --allowerasing --from-repo "$(dms_greeter_copr_repo)" "$DMS_GREETER_PACKAGE"
  else
    run_cmd_as_root dnf install -y --allowerasing --from-repo "$(dms_greeter_copr_repo)" "$DMS_GREETER_PACKAGE"
  fi
}

dms_greetd_config_content() {
  cat <<EOF
[terminal]
vt = 1

[default_session]
command = "/usr/bin/dms-greeter --command niri"
user = "$DMS_GREETER_USER"
EOF
}

# The RPM scriptlets create or repair the greetd config; rewrite it only
# when it still does not name dms-greeter (for example a preserved foreign
# config the scriptlet declined to touch).
ensure_dms_greetd_config() {
  if [[ "$DRY_RUN" -eq 0 && -f "$DMS_GREETD_CONFIG" ]] &&
    grep -F "dms-greeter" "$DMS_GREETD_CONFIG" >/dev/null 2>&1; then
    return 0
  fi
  log_progress "Writing DMS Greeter greetd configuration"
  dms_greetd_config_content | write_root_file 0644 "$DMS_GREETD_CONFIG"
}

# The recursive grant is only needed once: the default ACLs make files
# created afterwards inherit it, so an already-granted directory (its own
# ACL carries the greeter group entry) skips the recursive walk on re-runs
# instead of re-walking wallpaper and cache trees.
dms_greeter_dir_needs_recursive_grant() {
  local dir="$1"
  command -v getfacl >/dev/null 2>&1 || return 0
  ! getfacl --absolute-names -p "$dir" 2>/dev/null |
    grep -Eq "^group:$DMS_GREETER_USER:r"
}

# Mirror upstream grantGreeterReadAccess for the target user: traversal
# ACLs on the home path, recursive plus default ACLs on the DMS state
# dirs, and read access to the managed wallpapers.
prepare_dms_greeter_access() {
  local entry="g:$DMS_GREETER_USER:rX" dir
  local -a traversal_dirs=("$TARGET_HOME" "$TARGET_HOME/.config" "$TARGET_HOME/.local"
    "$TARGET_HOME/.local/state" "$TARGET_HOME/.local/share" "$TARGET_HOME/.cache")
  local -a state_dirs=("$(dms_config_dir)" "$(dms_state_dir)" "$(dms_cache_dir)"
    "$TARGET_HOME/.local/share/backgrounds")
  local -a recursive_dirs=()

  log_progress "Granting the greeter user access to DMS theme state"
  run_cmd_as_root usermod -aG "$DMS_GREETER_USER" "$TARGET_USER"

  run_cmd_as_user "$TARGET_USER" mkdir -p "${traversal_dirs[@]}" "${state_dirs[@]}"
  run_cmd_as_root setfacl -m "$entry" "${traversal_dirs[@]}"

  for dir in "${state_dirs[@]}"; do
    dms_greeter_dir_needs_recursive_grant "$dir" && recursive_dirs+=("$dir")
  done
  [[ "${#recursive_dirs[@]}" -eq 0 ]] ||
    run_cmd_as_root setfacl -R -m "$entry" "${recursive_dirs[@]}"
  run_cmd_as_root setfacl -d -m "$entry" "${state_dirs[@]}"
}

# The RPM tmpfiles entry guarantees only the cache root; the per-user
# slots directory needs setgid group write so `dms-greeter sync --profile`
# works without privileges at first login.
prepare_dms_greeter_cache() {
  local dir
  for dir in "$DMS_GREETER_CACHE_DIR" "$DMS_GREETER_CACHE_DIR/users"; do
    run_cmd_as_root mkdir -p "$dir"
    run_cmd_as_root chown "$DMS_GREETER_USER:$DMS_GREETER_USER" "$dir"
    run_cmd_as_root chmod 2770 "$dir"
  done
}

# Root-side equivalent of `dms-greeter sync` file plumbing: point the
# greeter cache at the target user's live DMS settings, session, and
# generated colors so the greeter matches the session theme from the
# first boot. The shared seeder creates any missing state file with its
# real seed content (this action runs before the post-actions seeding, so
# a bare placeholder here would block the theme seeds forever).
stage_dms_greeter_theme_sync() {
  dms_seed_state_files_if_missing

  log_progress "Linking the greeter cache to the target user's DMS state"
  run_cmd_as_root ln -sfn "$(dms_settings_file)" "$DMS_GREETER_CACHE_DIR/settings.json"
  run_cmd_as_root ln -sfn "$(dms_session_file)" "$DMS_GREETER_CACHE_DIR/session.json"
  run_cmd_as_root ln -sfn "$(dms_colors_cache_file)" "$DMS_GREETER_CACHE_DIR/colors.json"
}

dms_greeter_has_managed_greetd_state() {
  local display_manager="$1"
  [[ "$display_manager" == "greetd.service" ]] &&
    [[ -f "$DMS_GREETD_CONFIG" ]] &&
    grep -F "dms-greeter" "$DMS_GREETD_CONFIG" >/dev/null 2>&1
}

install_dms_greeter() {
  local existing_display_manager=""
  existing_display_manager="$(detect_enabled_display_manager || true)"
  if [[ -n "$existing_display_manager" ]] &&
    ! dms_greeter_has_managed_greetd_state "$existing_display_manager"; then
    log_info "Existing display manager detected ($existing_display_manager); skipping DMS Greeter package and service setup."
    record_system_skip action dms-greeter "existing display manager: $existing_display_manager"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install DMS Greeter package %s from %s\n' "$DMS_GREETER_PACKAGE" "$(dms_greeter_copr_repo)"
    ensure_dms_greetd_config
    if [[ "$SKIP_USER_CONFIG" -eq 1 ]]; then
      printf 'DRY-RUN: skip greeter user-state access and theme sync (user config skipped)\n'
    else
      prepare_dms_greeter_access
      prepare_dms_greeter_cache
      printf 'DRY-RUN: link the greeter cache to the target user DMS state\n'
    fi
    run_cmd_as_root systemctl set-default graphical.target
    run_cmd_as_root systemctl enable --force greetd.service
    return 0
  fi

  log_progress "Installing DMS Greeter"
  install_dms_greeter_package || return 1
  command -v dms-greeter >/dev/null 2>&1 || die "DMS Greeter package installed, but dms-greeter is not on PATH."

  run_cmd_as_root systemctl daemon-reload || return 1
  fedora_service_exists greetd || die "DMS Greeter requires greetd.service, but it is unavailable after package installation."

  ensure_dms_greetd_config

  if [[ "$SKIP_USER_CONFIG" -eq 1 ]]; then
    log_info "Skipping DMS Greeter user-state access and theme sync: user config is skipped, keeping the greeter defaults."
    dms_greeter_skip_user_sync "user config skipped"
  else
    prepare_dms_greeter_access
    prepare_dms_greeter_cache
    stage_dms_greeter_theme_sync
  fi

  log_progress "Enabling graphical login through greetd"
  run_cmd_as_root systemctl set-default graphical.target || return 1
  run_cmd_as_root systemctl enable --force greetd.service || return 1
  printf 'DMS Greeter is enabled through greetd. Reboot to start the graphical login.\n'
}

verify_dms_greeter() {
  dms_greeter_action_skipped && return 0
  rpm -q "$DMS_GREETER_PACKAGE" >/dev/null 2>&1 &&
    command -v dms-greeter >/dev/null 2>&1 &&
    systemctl is-enabled greetd >/dev/null 2>&1 &&
    grep -F "dms-greeter" "$DMS_GREETD_CONFIG" >/dev/null 2>&1 &&
    {
      dms_greeter_user_sync_skipped || {
        id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$DMS_GREETER_USER" &&
          [[ -L "$DMS_GREETER_CACHE_DIR/settings.json" ]] &&
          [[ -L "$DMS_GREETER_CACHE_DIR/session.json" ]] &&
          [[ -L "$DMS_GREETER_CACHE_DIR/colors.json" ]]
      }
    }
}

register_action "dms-greeter" install_dms_greeter verify_dms_greeter
