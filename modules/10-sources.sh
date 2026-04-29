#!/usr/bin/env bash
set -Eeuo pipefail

module_10_sources() {
  local source_file
  case "$DISTRO" in
    fedora)
      for source_file in \
        "$PLAN_DIR/sources/fedora-copr.list" \
        "$PLAN_DIR/sources/fedora-terra.list" \
        "$PLAN_DIR/sources/fedora-rpmfusion.list" \
        "$PLAN_DIR/sources/fedora-cisco-openh264.list" \
        "$PLAN_DIR/sources/fedora-vendor.list" \
        "$PLAN_DIR/sources/fedora-flatpak-remotes.list"
      do
        [[ -f "$source_file" ]] || continue
        while IFS= read -r source_id; do
          [[ -n "$source_id" ]] || continue
          distro_enable_sources "$source_id"
        done < <(read_plan_file "$source_file")
      done
      ;;
    arch)
      for source_file in \
        "$PLAN_DIR/sources/arch-multilib.list" \
        "$PLAN_DIR/sources/arch-aur.list" \
        "$PLAN_DIR/sources/arch-flatpak-remotes.list"
      do
        [[ -f "$source_file" ]] || continue
        while IFS= read -r source_id; do
          [[ -n "$source_id" ]] || continue
          distro_enable_sources "$source_id"
        done < <(read_plan_file "$source_file")
      done
      ;;
  esac
}
