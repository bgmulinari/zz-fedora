#!/usr/bin/env bash
set -Eeuo pipefail

source_plan_files_for_distro() {
  case "$DISTRO" in
    fedora)
      printf '%s\n' \
        "$PLAN_DIR/sources/fedora-copr.list" \
        "$PLAN_DIR/sources/fedora-terra.list" \
        "$PLAN_DIR/sources/fedora-rpmfusion.list" \
        "$PLAN_DIR/sources/fedora-cisco-openh264.list" \
        "$PLAN_DIR/sources/fedora-vendor.list" \
        "$PLAN_DIR/sources/fedora-flatpak-remotes.list"
      ;;
    arch)
      printf '%s\n' \
        "$PLAN_DIR/sources/arch-multilib.list" \
        "$PLAN_DIR/sources/arch-aur.list" \
        "$PLAN_DIR/sources/arch-flatpak-remotes.list"
      ;;
  esac
}

source_required_for_install() {
  local source_id="$1"
  load_source_descriptor "$DISTRO" "$source_id" || die "Unknown source: $source_id"
  [[ "${SOURCE_REQUIRED:-0}" -eq 1 ]]
}

enable_source_best_effort() {
  local source_id="$1"
  if distro_enable_sources "$source_id"; then
    return 0
  fi
  log_warn "Optional source failed and will be skipped for now: $source_id"
  return 0
}

module_10_sources() {
  local -a source_ids=()
  local source_file source_id

  while IFS= read -r source_file; do
    [[ -f "$source_file" ]] || continue
    while IFS= read -r source_id; do
      [[ -n "$source_id" ]] || continue
      append_unique source_ids "$source_id"
    done < <(read_plan_file "$source_file")
  done < <(source_plan_files_for_distro)

  for source_id in "${source_ids[@]:-}"; do
    source_required_for_install "$source_id" || continue
    distro_enable_sources "$source_id"
  done

  for source_id in "${source_ids[@]:-}"; do
    source_required_for_install "$source_id" && continue
    enable_source_best_effort "$source_id"
  done
}
