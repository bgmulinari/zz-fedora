#!/usr/bin/env bash
set -Eeuo pipefail

# ArtCraft Launcher RPM custom action, always from the latest upstream release.

ARTCRAFT_LAUNCHER_RELEASES_URL="https://github.com/storytold/craft-launcher/releases"

artcraft_launcher_installed() {
  rpm -q artcraft-launcher >/dev/null 2>&1 && [[ -x /usr/bin/artcraft-launcher ]]
}

# The releases/latest redirect names the current tag without spending GitHub
# API quota. A repository with no release redirects elsewhere and fails the
# tag check.
artcraft_launcher_latest_tag() {
  local url tag
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$ARTCRAFT_LAUNCHER_RELEASES_URL/latest")" || return 1
  tag="${url##*/}"
  [[ "$tag" =~ ^v[0-9][0-9A-Za-z.-]*$ ]] || return 1
  printf '%s\n' "$tag"
}

install_artcraft_launcher_release() {
  local staging="$1" tag asset base_url downloaded_rpm checksums expected_checksum rpm_identity

  if ! tag="$(artcraft_launcher_latest_tag)"; then
    log_warn "Could not determine the latest ArtCraft Launcher release."
    return 1
  fi
  asset="artcraft-launcher-${tag#v}-linux-x86_64.rpm"
  base_url="$ARTCRAFT_LAUNCHER_RELEASES_URL/download/$tag"
  downloaded_rpm="$staging/$asset"
  checksums="$staging/SHA256SUMS.txt"

  run_cmd curl -fsSL "$base_url/$asset" -o "$downloaded_rpm" || return 1
  run_cmd curl -fsSL "$base_url/SHA256SUMS.txt" -o "$checksums" || return 1

  expected_checksum="$(awk -v asset="$asset" '$2 == asset { print $1; exit }' "$checksums")"
  if [[ ! "$expected_checksum" =~ ^[A-Fa-f0-9]{64}$ ]] \
    || ! printf '%s  %s\n' "$expected_checksum" "$downloaded_rpm" | sha256sum -c --status -; then
    log_warn "ArtCraft Launcher download failed SHA-256 verification against the $tag release."
    return 1
  fi

  rpm_identity="$(rpm -qp --qf $'%{NAME}\t%{ARCH}\n' "$downloaded_rpm" 2>/dev/null || true)"
  if [[ "$rpm_identity" != $'artcraft-launcher\tx86_64' ]]; then
    log_warn "ArtCraft Launcher download did not contain the expected artcraft-launcher.x86_64 RPM."
    return 1
  fi

  run_cmd_as_root dnf install -y "$downloaded_rpm"
}

install_artcraft_launcher() {
  if artcraft_launcher_installed; then
    log_info "ArtCraft Launcher RPM is already installed"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install the latest ArtCraft Launcher RPM from %s\n' "$ARTCRAFT_LAUNCHER_RELEASES_URL"
    return 0
  fi

  log_progress "Installing the latest ArtCraft Launcher RPM"
  local staging status=0
  # Root installs this RPM, so it is downloaded to and verified in a
  # directory only root can write.
  ensure_root_staging_dir
  staging="$(mktemp -d "$ROOT_STAGING_DIR/artcraft-launcher.XXXXXX")"
  install_artcraft_launcher_release "$staging" || status=$?
  rm -rf "$staging"
  return "$status"
}

register_action "artcraft-launcher" install_artcraft_launcher artcraft_launcher_installed
