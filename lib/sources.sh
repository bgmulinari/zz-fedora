#!/usr/bin/env bash
set -Eeuo pipefail

source_plan_file_for_kind() {
  case "$1" in
    official) printf '%s/sources/official.list\n' "$PLAN_DIR" ;;
    copr) printf '%s/sources/copr.list\n' "$PLAN_DIR" ;;
    terra) printf '%s/sources/terra.list\n' "$PLAN_DIR" ;;
    rpmfusion) printf '%s/sources/rpmfusion.list\n' "$PLAN_DIR" ;;
    cisco-openh264) printf '%s/sources/cisco-openh264.list\n' "$PLAN_DIR" ;;
    vendor) printf '%s/sources/vendor.list\n' "$PLAN_DIR" ;;
    flatpak) printf '%s/sources/flatpak-remotes.list\n' "$PLAN_DIR" ;;
    *) die "Unsupported Fedora source kind: $1" ;;
  esac
}

append_plan_source() {
  local source_id="$1"
  load_source_descriptor "$source_id" || die "Unknown source: $source_id"
  local destination
  destination="$(source_plan_file_for_kind "$SOURCE_KIND")"
  append_plan_entries "$destination" "$source_id"
}

list_sources_pretty() {
  local source_id
  while IFS= read -r source_id; do
    load_source_descriptor "$source_id" || continue
    printf '%s\t%s\t%s\n' "$SOURCE_ID" "$SOURCE_KIND" "$SOURCE_LABEL"
  done < <(list_source_ids)
}
