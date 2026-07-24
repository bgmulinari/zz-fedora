#!/usr/bin/env bash
set -Eeuo pipefail

# Noctalia Greeter (greetd) custom action.

NOCTALIA_GREETER_FEDORA_COPR_REPO="copr:copr.fedorainfracloud.org:lionheartp:Hyprland"
NOCTALIA_GREETER_PACKAGE="noctalia-greeter"
NOCTALIA_GREETER_USER="greeter"
NOCTALIA_GREETER_STATE_DIR="/var/lib/noctalia-greeter"
NOCTALIA_GREETER_SELINUX_TYPE="xdm_var_lib_t"
NOCTALIA_GREETER_SESSION_BIN="/usr/bin/noctalia-greeter-session"
NOCTALIA_GREETD_CONFIG="/etc/greetd/config.toml"

noctalia_greeter_action_skipped() {
  local skip_file="$PLAN_DIR/system-skips.tsv"
  [[ -f "$skip_file" ]] || return 1
  awk -F'\t' '$1 == "action" && $2 == "noctalia-greeter" { found = 1 } END { exit !found }' "$skip_file"
}

# The appearance seed is best-effort: when the managed config cannot be
# rendered into a greeter appearance (non-custom theme source, missing
# palette or wallpaper, --skip-user-config), the greeter keeps its own
# defaults rather than failing the whole install. Skips are recorded so
# verification accepts the absent manifest.
noctalia_greeter_appearance_seed_skipped() {
  local skip_file="$PLAN_DIR/system-skips.tsv"
  [[ -f "$skip_file" ]] || return 1
  awk -F'\t' '$1 == "action" && $2 == "noctalia-greeter-appearance" { found = 1 } END { exit !found }' "$skip_file"
}

noctalia_greeter_skip_appearance_seed() {
  record_system_skip action noctalia-greeter-appearance "$1"
}

# Render the greeter appearance manifest from a Noctalia palette JSON.
# The greeter requires all sixteen snake_case palette keys; jq fails the
# render when the palette is missing any of them.
noctalia_greeter_appearance_manifest() {
  local mode="$1" palette_file="$2" installed_wallpaper="$3"
  jq -n \
    --arg mode "$mode" \
    --arg wallpaper_path "$NOCTALIA_GREETER_STATE_DIR/$installed_wallpaper" \
    --slurpfile palette_doc "$palette_file" '
    ($palette_doc[0][$mode]) as $p
    | {
        version: 1,
        theme_mode: $mode,
        palette: {
          primary: $p.mPrimary,
          on_primary: $p.mOnPrimary,
          secondary: $p.mSecondary,
          on_secondary: $p.mOnSecondary,
          tertiary: $p.mTertiary,
          on_tertiary: $p.mOnTertiary,
          error: $p.mError,
          on_error: $p.mOnError,
          surface: $p.mSurface,
          on_surface: $p.mOnSurface,
          surface_variant: $p.mSurfaceVariant,
          on_surface_variant: $p.mOnSurfaceVariant,
          outline: $p.mOutline,
          shadow: $p.mShadow,
          hover: $p.mHover,
          on_hover: $p.mOnHover
        },
        wallpaper: { path: $wallpaper_path, fill_mode: "crop" },
        corner_radius_scale: 1.0
      }
    | if ([.palette[]] | any(. == null)) then
        error("palette \($mode) is missing required keys")
      else . end
  '
}

# Seed /var/lib/noctalia-greeter with the managed theme and default
# wallpaper so a fresh install boots into a greeter that already matches
# the Noctalia session; apply-appearance also flips greeter.toml to the
# Synced scheme. A later in-session sync simply overwrites this seed.
seed_noctalia_greeter_appearance() {
  local theme_source mode palette_name palette_file wallpaper_path
  local wallpaper_file asset_candidate expanded_path wallpaper_name
  local extension staging installed_name failure=""

  if [[ "$SKIP_USER_CONFIG" -eq 1 ]]; then
    log_info "Skipping Noctalia Greeter appearance seed: user config is skipped, keeping the greeter defaults."
    noctalia_greeter_skip_appearance_seed "user config skipped"
    return 0
  fi

  theme_source="$(noctalia_managed_theme_source)"
  if [[ "$theme_source" != "custom" ]]; then
    log_info "Skipping Noctalia Greeter appearance seed: managed theme source is '${theme_source:-unset}', not a seedable custom palette."
    noctalia_greeter_skip_appearance_seed "theme source ${theme_source:-unset} is not custom"
    return 0
  fi

  palette_name="$(noctalia_managed_custom_palette_name)"
  if [[ -z "$palette_name" ]]; then
    log_warn "Skipping Noctalia Greeter appearance seed: managed config declares theme source custom but no theme.custom_palette."
    noctalia_greeter_skip_appearance_seed "no custom_palette declared"
    return 0
  fi

  palette_file="$(noctalia_managed_palettes_dir)/$palette_name.json"
  if [[ ! -f "$palette_file" ]]; then
    log_warn "Skipping Noctalia Greeter appearance seed: managed palette not found: $palette_file"
    noctalia_greeter_skip_appearance_seed "palette file missing: $palette_name"
    return 0
  fi

  mode="$(noctalia_managed_theme_mode)"
  if ! jq -e --arg mode "$mode" 'has($mode)' "$palette_file" >/dev/null 2>&1; then
    log_warn "Skipping Noctalia Greeter appearance seed: palette $palette_name defines no '$mode' palette."
    noctalia_greeter_skip_appearance_seed "palette $palette_name lacks mode $mode"
    return 0
  fi

  wallpaper_path="$(noctalia_managed_default_wallpaper)"
  if [[ -z "$wallpaper_path" ]]; then
    log_warn "Skipping Noctalia Greeter appearance seed: managed config declares no wallpaper.default.path."
    noctalia_greeter_skip_appearance_seed "no default wallpaper declared"
    return 0
  fi

  # Prefer the bundled asset (the deployed copy does not exist yet at base
  # action time), then fall back to the configured path itself.
  asset_candidate="$ROOT_DIR/assets/wallpapers/$(basename "$wallpaper_path")"
  expanded_path="${wallpaper_path/#~\//$TARGET_HOME/}"
  if [[ -f "$asset_candidate" ]]; then
    wallpaper_file="$asset_candidate"
  elif [[ -f "$expanded_path" ]]; then
    wallpaper_file="$expanded_path"
  else
    log_warn "Skipping Noctalia Greeter appearance seed: managed default wallpaper not found as a bundled asset ($asset_candidate) or on disk ($expanded_path)."
    noctalia_greeter_skip_appearance_seed "wallpaper not found: $wallpaper_path"
    return 0
  fi

  log_progress "Seeding Noctalia Greeter appearance"
  wallpaper_name="$(basename "$wallpaper_file")"
  extension="${wallpaper_name##*.}"
  if [[ "$extension" == "$wallpaper_name" ]]; then
    installed_name="wallpaper"
  else
    installed_name="wallpaper.$extension"
  fi
  staging="$(mktemp -d "$CACHE_DIR/noctalia-greeter-appearance.XXXXXX")" ||
    die "Could not create a Noctalia Greeter staging directory under $CACHE_DIR"
  if ! cp -- "$wallpaper_file" "$staging/$installed_name"; then
    failure="Could not stage the greeter wallpaper from $wallpaper_file"
  elif ! noctalia_greeter_appearance_manifest "$mode" "$palette_file" "$installed_name" >"$staging/appearance.json"; then
    failure="Could not render the Noctalia Greeter appearance manifest from $palette_file"
  elif ! run_cmd_as_root env "GREETER_USER=$NOCTALIA_GREETER_USER" noctalia-greeter-apply-appearance "$staging"; then
    failure="Could not apply the staged Noctalia Greeter appearance"
  fi
  rm -rf "$staging"
  [[ -z "$failure" ]] || die "$failure"
}

install_noctalia_greeter_package() {
  log_progress "Installing greetd for Noctalia Greeter"
  package_install_idempotent "$(native_backend)" greetd || return 1

  log_progress "Installing or syncing Noctalia Greeter"
  if rpm -q "$NOCTALIA_GREETER_PACKAGE" >/dev/null 2>&1; then
    run_cmd_as_root dnf distro-sync -y --allowerasing --from-repo "$NOCTALIA_GREETER_FEDORA_COPR_REPO" "$NOCTALIA_GREETER_PACKAGE"
  else
    run_cmd_as_root dnf install -y --allowerasing --from-repo "$NOCTALIA_GREETER_FEDORA_COPR_REPO" "$NOCTALIA_GREETER_PACKAGE"
  fi
}

noctalia_greetd_config_content() {
  cat <<EOF
[terminal]
vt = 1

[default_session]
command = "/usr/bin/env WLR_NO_HARDWARE_CURSORS=1 $NOCTALIA_GREETER_SESSION_BIN"
user = "$NOCTALIA_GREETER_USER"
EOF
}

install_noctalia_greetd_config() {
  log_progress "Writing Noctalia Greeter greetd configuration"
  noctalia_greetd_config_content | write_root_file 0644 "$NOCTALIA_GREETD_CONFIG"
}

find_noctalia_greeter_pam_runtime_module() {
  local module dir
  for module in pam_systemd.so pam_elogind.so; do
    for dir in /usr/lib/security /usr/lib64/security /lib/security /lib64/security; do
      if [[ -f "$dir/$module" ]]; then
        printf '%s\n' "$module"
        return 0
      fi
    done
  done
  return 1
}

configure_noctalia_greetd_pam() {
  local pam_file="/etc/pam.d/greetd"
  local pam_module pam_line pam_tmp last_session

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: ensure %s has a pam_systemd.so or pam_elogind.so session line\n' "$pam_file"
    return 0
  fi

  log_progress "Configuring greetd PAM session support"
  [[ -f "$pam_file" ]] || {
    log_warn "$pam_file was not found after installing greetd; skipping Noctalia Greeter PAM session patch."
    return 0
  }

  pam_module="$(find_noctalia_greeter_pam_runtime_module || true)"
  [[ -n "$pam_module" ]] || {
    log_warn "No pam_systemd.so or pam_elogind.so found; leaving $pam_file unchanged."
    return 0
  }

  grep -q -F "$pam_module" "$pam_file" && return 0

  pam_line="session    required     $pam_module"
  pam_tmp="$(mktemp "$CACHE_DIR/greetd-pam.XXXXXX")"
  if grep -q -E '^[[:space:]]*session[[:space:]]+' "$pam_file"; then
    last_session="$(grep -n -E '^[[:space:]]*session[[:space:]]+' "$pam_file" | tail -n 1 | awk -F: '{print $1}')"
    awk -v line="$pam_line" -v last="$last_session" '{ print $0; if (NR == last) print line }' "$pam_file" >"$pam_tmp"
  else
    cp "$pam_file" "$pam_tmp"
    printf '\n%s\n' "$pam_line" >>"$pam_tmp"
  fi

  backup_file_if_needed "$pam_file"
  run_cmd_as_root install -m 0644 "$pam_tmp" "$pam_file"
  rm -f "$pam_tmp"
}

ensure_noctalia_greeter_user() {
  log_progress "Ensuring Noctalia Greeter system user exists"
  id -u "$NOCTALIA_GREETER_USER" >/dev/null 2>&1 && return 0
  run_cmd_as_root useradd -r -s /usr/bin/nologin -d "$NOCTALIA_GREETER_STATE_DIR" "$NOCTALIA_GREETER_USER"
}

ensure_noctalia_greeter_selinux_fcontext() {
  local fcontext_rule existing_type
  fcontext_rule="$NOCTALIA_GREETER_STATE_DIR(/.*)?"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: ensure SELinux fcontext %s for %s\n' "$NOCTALIA_GREETER_SELINUX_TYPE" "$fcontext_rule"
    return 0
  fi

  command -v selinuxenabled >/dev/null 2>&1 || die "Noctalia Greeter SELinux setup requires selinuxenabled."
  if ! selinuxenabled; then
    log_info "SELinux is disabled; skipping the Noctalia Greeter fcontext rule."
    return 0
  fi

  command -v semanage >/dev/null 2>&1 || die "Noctalia Greeter SELinux setup requires semanage."
  if ! existing_type="$(
    run_cmd_as_root env LC_ALL=C semanage fcontext -l -C |
      awk -v rule="$fcontext_rule" '$1 == rule && $2 == "all" && $3 == "files" { split($NF, context, ":"); print context[3]; exit }'
  )"; then
    die "Could not inspect local SELinux fcontext rules."
  fi

  if [[ -z "$existing_type" ]]; then
    run_cmd_as_root semanage fcontext -a -t "$NOCTALIA_GREETER_SELINUX_TYPE" "$fcontext_rule"
  elif [[ "$existing_type" != "$NOCTALIA_GREETER_SELINUX_TYPE" ]]; then
    run_cmd_as_root semanage fcontext -m -t "$NOCTALIA_GREETER_SELINUX_TYPE" "$fcontext_rule"
  fi
}

restore_noctalia_greeter_selinux_context() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: restore SELinux contexts under %s\n' "$NOCTALIA_GREETER_STATE_DIR"
    return 0
  fi

  command -v selinuxenabled >/dev/null 2>&1 || die "Noctalia Greeter SELinux setup requires selinuxenabled."
  selinuxenabled || return 0
  command -v restorecon >/dev/null 2>&1 || die "Noctalia Greeter SELinux setup requires restorecon."
  run_cmd_as_root restorecon -RF "$NOCTALIA_GREETER_STATE_DIR"
}

verify_noctalia_greeter_selinux_context() {
  local path expected_context

  command -v selinuxenabled >/dev/null 2>&1 || return 1
  selinuxenabled || return 0
  command -v matchpathcon >/dev/null 2>&1 || return 1

  for path in "$NOCTALIA_GREETER_STATE_DIR" "$NOCTALIA_GREETER_STATE_DIR/greeter.toml"; do
    expected_context="$(matchpathcon -n "$path" 2>/dev/null)" || return 1
    [[ "$expected_context" == *":$NOCTALIA_GREETER_SELINUX_TYPE:"* ]] || return 1
    matchpathcon -V "$path" >/dev/null 2>&1 || return 1
  done
}

noctalia_greeter_has_managed_greetd_state() {
  local display_manager="$1"
  [[ "$display_manager" == "greetd.service" ]] \
    && [[ -f "$NOCTALIA_GREETD_CONFIG" ]] \
    && grep -F "$NOCTALIA_GREETER_SESSION_BIN" "$NOCTALIA_GREETD_CONFIG" >/dev/null 2>&1 \
    && [[ -f "$NOCTALIA_GREETER_STATE_DIR/greeter.toml" ]]
}

prepare_noctalia_greeter_paths() {
  log_progress "Preparing Noctalia Greeter state and log paths"
  run_cmd_as_root mkdir -p "$NOCTALIA_GREETER_STATE_DIR"
  run_cmd_as_root chmod 0755 "$NOCTALIA_GREETER_STATE_DIR"
  run_cmd_as_root chown "$NOCTALIA_GREETER_USER:" "$NOCTALIA_GREETER_STATE_DIR"
  run_cmd_as_root touch \
    /var/log/noctalia-greeter.log \
    "$NOCTALIA_GREETER_STATE_DIR/greeter.log" \
    /tmp/noctalia-greeter.log
  run_cmd_as_root chown "$NOCTALIA_GREETER_USER:" \
    /var/log/noctalia-greeter.log \
    "$NOCTALIA_GREETER_STATE_DIR/greeter.log" \
    /tmp/noctalia-greeter.log
  run_cmd_as_root chmod 0664 \
    /var/log/noctalia-greeter.log \
    "$NOCTALIA_GREETER_STATE_DIR/greeter.log" \
    /tmp/noctalia-greeter.log
}

install_noctalia_greeter() {
  local existing_display_manager=""
  existing_display_manager="$(detect_enabled_display_manager || true)"
  if [[ -n "$existing_display_manager" ]]; then
    if noctalia_greeter_has_managed_greetd_state "$existing_display_manager"; then
      log_progress "Reconciling Noctalia Greeter SELinux state"
      ensure_noctalia_greeter_selinux_fcontext || return 1
      restore_noctalia_greeter_selinux_context || return 1
      verify_noctalia_greeter_selinux_context || die "Noctalia Greeter state does not have the required SELinux context."
    fi
    log_info "Existing display manager detected ($existing_display_manager); skipping Noctalia Greeter package and service setup."
    record_system_skip action noctalia-greeter "existing display manager: $existing_display_manager"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install greetd and Noctalia Greeter package %s from %s\n' "$NOCTALIA_GREETER_PACKAGE" "$NOCTALIA_GREETER_FEDORA_COPR_REPO"
    ensure_noctalia_greeter_user
    install_noctalia_greetd_config
    configure_noctalia_greetd_pam
    ensure_noctalia_greeter_selinux_fcontext
    prepare_noctalia_greeter_paths
    printf 'DRY-RUN: initialize %s/greeter.toml with noctalia-greeter-apply-appearance --setup-system\n' "$NOCTALIA_GREETER_STATE_DIR"
    printf 'DRY-RUN: seed Noctalia Greeter appearance from the managed Noctalia theme and default wallpaper\n'
    restore_noctalia_greeter_selinux_context
    run_cmd_as_root systemctl daemon-reload
    run_cmd_as_root systemctl set-default graphical.target
    run_cmd_as_root systemctl enable --force greetd.service
    return 0
  fi

  log_progress "Installing Noctalia Greeter"
  install_noctalia_greeter_package || return 1

  command -v noctalia-greeter >/dev/null 2>&1 || die "Noctalia Greeter package installed, but noctalia-greeter is not on PATH."
  command -v noctalia-greeter-session >/dev/null 2>&1 || die "Noctalia Greeter package installed, but noctalia-greeter-session is not on PATH."
  command -v noctalia-greeter-compositor >/dev/null 2>&1 || die "Noctalia Greeter package installed, but noctalia-greeter-compositor is not on PATH."
  command -v noctalia-greeter-apply-appearance >/dev/null 2>&1 || die "Noctalia Greeter package installed, but noctalia-greeter-apply-appearance is not on PATH."

  run_cmd_as_root systemctl daemon-reload || return 1
  if ! fedora_service_exists greetd; then
    log_warn "greetd.service was not detected after Noctalia Greeter install; retrying direct greetd package install."
    package_install_idempotent "$(native_backend)" greetd || return 1
    run_cmd_as_root systemctl daemon-reload || return 1
  fi
  fedora_service_exists greetd || die "Noctalia Greeter requires greetd.service, but it is still unavailable after package installation."

  ensure_noctalia_greeter_user
  install_noctalia_greetd_config
  configure_noctalia_greetd_pam
  ensure_noctalia_greeter_selinux_fcontext
  prepare_noctalia_greeter_paths
  log_progress "Initializing Noctalia Greeter appearance"
  run_cmd_as_root env "GREETER_USER=$NOCTALIA_GREETER_USER" noctalia-greeter-apply-appearance --setup-system || return 1
  seed_noctalia_greeter_appearance || return 1
  restore_noctalia_greeter_selinux_context || return 1

  log_progress "Enabling graphical login through greetd"
  run_cmd_as_root systemctl set-default graphical.target || return 1
  run_cmd_as_root systemctl enable --force greetd.service || return 1
  printf 'Noctalia Greeter is enabled through greetd. Reboot to start the graphical login.\n'
}

verify_noctalia_greeter() {
  noctalia_greeter_action_skipped && return 0
  rpm -q "$NOCTALIA_GREETER_PACKAGE" >/dev/null 2>&1 \
    && command -v noctalia-greeter >/dev/null 2>&1 \
    && command -v noctalia-greeter-session >/dev/null 2>&1 \
    && systemctl is-enabled greetd >/dev/null 2>&1 \
    && grep -F "noctalia-greeter-session" "$NOCTALIA_GREETD_CONFIG" >/dev/null 2>&1 \
    && grep -F "WLR_NO_HARDWARE_CURSORS=1" "$NOCTALIA_GREETD_CONFIG" >/dev/null 2>&1 \
    && verify_noctalia_greeter_selinux_context \
    && { [[ -s "$NOCTALIA_GREETER_STATE_DIR/appearance.json" ]] || noctalia_greeter_appearance_seed_skipped; }
}

register_action "noctalia-greeter" install_noctalia_greeter verify_noctalia_greeter
