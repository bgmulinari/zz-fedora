#!/usr/bin/env bash
set -Eeuo pipefail

source_plan_file_for_kind() {
  local distro="$1"
  local kind="$2"
  case "$distro" in
    fedora)
      case "$kind" in
        official) printf '%s/sources/fedora-official.list\n' "$PLAN_DIR" ;;
        copr) printf '%s/sources/fedora-copr.list\n' "$PLAN_DIR" ;;
        terra) printf '%s/sources/fedora-terra.list\n' "$PLAN_DIR" ;;
        rpmfusion) printf '%s/sources/fedora-rpmfusion.list\n' "$PLAN_DIR" ;;
        cisco-openh264) printf '%s/sources/fedora-cisco-openh264.list\n' "$PLAN_DIR" ;;
        vendor) printf '%s/sources/fedora-vendor.list\n' "$PLAN_DIR" ;;
        flatpak) printf '%s/sources/fedora-flatpak-remotes.list\n' "$PLAN_DIR" ;;
        *) die "Unsupported Fedora source kind: $kind" ;;
      esac
      ;;
    arch)
      case "$kind" in
        aur) printf '%s/sources/arch-aur.list\n' "$PLAN_DIR" ;;
        flatpak) printf '%s/sources/arch-flatpak-remotes.list\n' "$PLAN_DIR" ;;
        multilib) printf '%s/sources/arch-multilib.list\n' "$PLAN_DIR" ;;
        official) printf '%s/sources/arch-official.list\n' "$PLAN_DIR" ;;
        *) die "Unsupported Arch source kind: $kind" ;;
      esac
      ;;
    *)
      die "Unsupported distro for source plan: $distro"
      ;;
  esac
}

append_plan_source() {
  local source_id="$1"
  load_source_descriptor "$DISTRO" "$source_id" || die "Unknown source: $source_id"
  local destination
  destination="$(source_plan_file_for_kind "$DISTRO" "$SOURCE_KIND")"
  append_plan_entries "$destination" "$source_id"
}

list_sources_pretty() {
  local distro="$1"
  local source_id
  while IFS= read -r source_id; do
    load_source_descriptor "$distro" "$source_id" || continue
    printf '%s\t%s\t%s\n' "$SOURCE_ID" "$SOURCE_KIND" "$SOURCE_LABEL"
  done < <(list_source_ids "$distro")
}
