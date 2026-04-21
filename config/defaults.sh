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

BASE_PACKAGE_MANIFESTS_fedora=(
  packages/fedora/official/bootstrap.pkgs
  packages/fedora/copr/yalter-niri/desktop-core.pkgs
  packages/fedora/terra/noctalia.pkgs
  packages/fedora/terra/ghostty.pkgs
  packages/fedora/official/desktop-core.pkgs
  packages/fedora/official/portals-kde.pkgs
  packages/fedora/official/system-services.pkgs
  packages/fedora/official/kde-apps.pkgs
  packages/fedora/official/kde-file-integration.pkgs
  packages/fedora/official/wayland-tools.pkgs
  packages/fedora/official/fonts-theme-kde.pkgs
  packages/fedora/official/browsers/firefox.pkgs
)

BASE_PACKAGE_MANIFESTS_arch=(
  packages/arch/official/bootstrap.pkgs
  packages/arch/official/desktop-core.pkgs
  packages/arch/aur/desktop-core.pkgs
  packages/arch/official/portals-kde.pkgs
  packages/arch/official/system-services.pkgs
  packages/arch/official/kde-apps.pkgs
  packages/arch/official/kde-file-integration.pkgs
  packages/arch/official/wayland-tools.pkgs
  packages/arch/official/fonts-theme-kde.pkgs
  packages/arch/official/browsers/firefox.pkgs
)

SUPPORTED_DISTROS=(
  fedora
  arch
)
