#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_COMMAND="wizard"
DEFAULT_DISTRO="auto"
DEFAULT_TARGET_USER="${SUDO_USER:-$USER}"
DEFAULT_SYSTEM_SERVICES=(
  NetworkManager
  firewalld
  bluetooth
  chronyd
  power-profiles-daemon
)

BASE_BUNDLE_IDS_fedora=(
  base-bootstrap
  base-desktop-niri
  base-noctalia
  base-ghostty
  base-desktop-core
  base-portals-kde
  base-system-services
  base-kde-apps
  base-kde-file-integration
  base-wayland-tools
  base-fonts-theme-kde
  browser-firefox
)

BASE_BUNDLE_IDS_arch=(
  base-bootstrap
  base-desktop-core
  base-noctalia
  base-portals-kde
  base-system-services
  base-kde-apps
  base-kde-file-integration
  base-wayland-tools
  base-fonts-theme-kde
  browser-firefox
)

SUPPORTED_DISTROS=(
  fedora
  arch
)
