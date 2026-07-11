#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_COMMAND="wizard"
DEFAULT_TARGET_USER="${SUDO_USER:-$USER}"
DEFAULT_DESKTOP_APP_PROFILE="auto"
DEFAULT_SYSTEM_SERVICES=(
  NetworkManager
  firewalld
  bluetooth
  chronyd
  tuned-ppd
  cups
  avahi-daemon
)

EARLY_BASE_BUNDLE_IDS=(
  base-bootstrap
  base-system-services
)

BASE_BUNDLE_IDS=(
  base-bootstrap
  base-source-rpmfusion-free
  base-source-rpmfusion-nonfree
  base-source-flathub
  base-source-cisco-openh264
  base-login-manager
  base-desktop-niri
  base-noctalia
  base-ghostty
  base-ms-fonts
  base-jetbrains-mono-nerd-font
  base-desktop-core
  base-gtk-portals
  base-system-services
  base-desktop-controls
  base-desktop-apps
  base-file-integration
  base-file-integration-gtk
  base-wayland-tools
  base-gtk-look
  base-qt-look
  base-nodejs
  shell-zsh
  shell-starship
  shell-zoxide
  shell-fastfetch
  shell-gh
  shell-btop
  shell-fd
  shell-fzf
  shell-bat
  shell-yazi
)

DEFAULT_BUNDLE_IDS=(
)

MINIMAL_DESKTOP_SKIP_BUNDLE_IDS=(
  base-source-rpmfusion-free
  base-source-rpmfusion-nonfree
  base-source-flathub
  base-source-cisco-openh264
  base-gtk-portals
  base-desktop-controls
  base-desktop-apps
  base-file-integration-gtk
  base-gtk-look
  base-qt-look
)
