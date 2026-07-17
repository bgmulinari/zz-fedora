#!/usr/bin/env bash
set -Eeuo pipefail

# Noctalia Greeter (greetd) custom action.

NOCTALIA_GREETER_FEDORA_COPR_REPO="copr:copr.fedorainfracloud.org:lionheartp:Hyprland"
NOCTALIA_GREETER_PACKAGE="noctalia-greeter"
NOCTALIA_GREETER_USER="greeter"
NOCTALIA_GREETER_STATE_DIR="/var/lib/noctalia-greeter"
NOCTALIA_GREETER_SESSION_BIN="/usr/bin/noctalia-greeter-session"
NOCTALIA_GREETD_CONFIG="/etc/greetd/config.toml"

noctalia_greeter_action_skipped() {
  local skip_file="$PLAN_DIR/system-skips.tsv"
  [[ -f "$skip_file" ]] || return 1
  awk -F'\t' '$1 == "action" && $2 == "noctalia-greeter" { found = 1 } END { exit !found }' "$skip_file"
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
command = "$NOCTALIA_GREETER_SESSION_BIN"
user = "$NOCTALIA_GREETER_USER"
EOF
}

install_noctalia_greetd_config() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: write %s for %s\n' "$NOCTALIA_GREETD_CONFIG" "$NOCTALIA_GREETER_SESSION_BIN"
    return 0
  fi

  log_progress "Writing Noctalia Greeter greetd configuration"
  local config_tmp backup_path
  config_tmp="$(mktemp "$CACHE_DIR/greetd-config.XXXXXX")"
  noctalia_greetd_config_content >"$config_tmp"

  run_cmd_as_root mkdir -p "$(dirname "$NOCTALIA_GREETD_CONFIG")"
  if [[ -f "$NOCTALIA_GREETD_CONFIG" ]] && cmp -s "$config_tmp" "$NOCTALIA_GREETD_CONFIG"; then
    rm -f "$config_tmp"
    return 0
  fi
  if [[ -f "$NOCTALIA_GREETD_CONFIG" ]]; then
    backup_path="${NOCTALIA_GREETD_CONFIG}.bak.noctalia.$(date +%Y%m%d%H%M%S)"
    run_cmd_as_root cp -a "$NOCTALIA_GREETD_CONFIG" "$backup_path"
  fi

  run_cmd_as_root install -m 0644 "$config_tmp" "$NOCTALIA_GREETD_CONFIG"
  rm -f "$config_tmp"
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
  local pam_module pam_line pam_tmp backup_path last_session

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

  backup_path="${pam_file}.bak.noctalia.$(date +%Y%m%d%H%M%S)"
  run_cmd_as_root cp "$pam_file" "$backup_path"
  run_cmd_as_root install -m 0644 "$pam_tmp" "$pam_file"
  rm -f "$pam_tmp"
}

ensure_noctalia_greeter_user() {
  log_progress "Ensuring Noctalia Greeter system user exists"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd_as_root useradd -r -s /usr/bin/nologin -d "$NOCTALIA_GREETER_STATE_DIR" "$NOCTALIA_GREETER_USER"
    return 0
  fi

  id -u "$NOCTALIA_GREETER_USER" >/dev/null 2>&1 && return 0
  run_cmd_as_root useradd -r -s /usr/bin/nologin -d "$NOCTALIA_GREETER_STATE_DIR" "$NOCTALIA_GREETER_USER"
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
    log_info "Existing display manager detected ($existing_display_manager); skipping Noctalia Greeter package and service setup."
    record_system_skip action noctalia-greeter "existing display manager: $existing_display_manager"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install greetd and Noctalia Greeter package %s from %s\n' "$NOCTALIA_GREETER_PACKAGE" "$NOCTALIA_GREETER_FEDORA_COPR_REPO"
    ensure_noctalia_greeter_user
    install_noctalia_greetd_config
    configure_noctalia_greetd_pam
    prepare_noctalia_greeter_paths
    printf 'DRY-RUN: initialize %s/greeter.toml with noctalia-greeter-apply-appearance --setup-system\n' "$NOCTALIA_GREETER_STATE_DIR"
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
  prepare_noctalia_greeter_paths
  log_progress "Initializing Noctalia Greeter appearance"
  run_cmd_as_root env "GREETER_USER=$NOCTALIA_GREETER_USER" noctalia-greeter-apply-appearance --setup-system || return 1

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
    && grep -F "noctalia-greeter-session" "$NOCTALIA_GREETD_CONFIG" >/dev/null 2>&1
}

register_action "noctalia-greeter" install_noctalia_greeter verify_noctalia_greeter
