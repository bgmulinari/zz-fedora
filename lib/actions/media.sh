#!/usr/bin/env bash
set -Eeuo pipefail

# Multimedia codec custom actions. The hardware-acceleration installer and
# verifier live in lib/hardware.sh next to the GPU detection helpers.

install_media_codecs() {
  log_progress "Replacing Fedora ffmpeg-free with RPM Fusion ffmpeg"
  run_cmd_as_root dnf swap -y ffmpeg-free ffmpeg --allowerasing || return 1
  log_progress "Installing the curated multimedia codec group"
  run_cmd_as_root dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver || return 1
  log_progress "Retaining Bluetooth aptX support as part of the multimedia group"
  run_cmd_as_root dnf -y mark group multimedia pipewire-codec-aptx || return 1
  log_progress "Installing Firefox OpenH264 integration"
  run_cmd_as_root dnf install -y mozilla-openh264 || return 1
}

verify_media_codecs() {
  rpm -q \
    ffmpeg \
    ffmpeg-libs \
    gstreamer1-plugin-libav \
    gstreamer1-plugin-openh264 \
    gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly \
    pipewire-codec-aptx \
    mozilla-openh264 >/dev/null 2>&1
}

register_action "media-codecs" install_media_codecs verify_media_codecs
register_action "media-hardware-acceleration" install_fedora_media_hardware_acceleration verify_fedora_media_hardware_acceleration
