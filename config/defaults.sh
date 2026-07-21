#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_COMMAND="wizard"
DEFAULT_TARGET_USER="${SUDO_USER:-${USER:-}}"
if [[ -z "$DEFAULT_TARGET_USER" ]]; then
  DEFAULT_TARGET_USER="$(id -un)"
fi
DEFAULT_DESKTOP_APP_PROFILE="auto"
MINIMUM_FEDORA_RELEASE=44
SUPPORTED_ARCHITECTURES=(
  x86_64
)
DEFAULT_SYSTEM_SERVICES=(
  NetworkManager
  firewalld
  bluetooth
  chronyd
  tuned-ppd
  cups
  avahi-daemon
)

# Base-install membership (EARLY_BASE_BUNDLE_IDS, BASE_BUNDLE_IDS, and
# MINIMAL_DESKTOP_SKIP_BUNDLE_IDS) is derived from unit [base] metadata by
# the compiled catalog (lib/catalog.py), not hand-maintained here.
DEFAULT_BUNDLE_IDS=(
)

# Native packages the flatpak backend needs before any flatpak work runs.
# This is installer machinery, not catalog data, so it lives here.
FLATPAK_BACKEND_PREREQ_PKGS=(
  flatpak
)
