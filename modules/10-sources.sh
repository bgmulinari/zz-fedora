#!/usr/bin/env bash
set -Eeuo pipefail

source_plan_files() {
  printf '%s\n' \
    "$PLAN_DIR/sources/copr.list" \
    "$PLAN_DIR/sources/terra.list" \
    "$PLAN_DIR/sources/rpmfusion.list" \
    "$PLAN_DIR/sources/cisco-openh264.list" \
    "$PLAN_DIR/sources/vendor.list" \
    "$PLAN_DIR/sources/flatpak-remotes.list" \
    "$PLAN_DIR/sources/artifacts.list"
}

source_required_for_install() {
  local source_id="$1"
  load_source_descriptor "$source_id" || die "Unknown source: $source_id"
  [[ "${SOURCE_REQUIRED:-0}" -eq 1 ]]
}

enable_source_best_effort() {
  local source_id="$1"
  log_progress "Enabling optional software source: $source_id"
  if fedora_enable_sources "$source_id"; then
    return 0
  fi
  log_warn "Optional source failed and will be skipped for now: $source_id"
  append_warning "Optional source failed and was skipped: $source_id"
  return 0
}

module_10_sources() {
  local -a source_ids=()
  local source_file source_id

  log_progress "Collecting planned software sources"
  while IFS= read -r source_file; do
    [[ -f "$source_file" ]] || continue
    while IFS= read -r source_id; do
      [[ -n "$source_id" ]] || continue
      append_unique source_ids "$source_id"
    done < <(read_plan_file "$source_file")
  done < <(source_plan_files)

  for source_id in "${source_ids[@]:-}"; do
    source_required_for_install "$source_id" || continue
    log_progress "Enabling required software source: $source_id"
    fedora_enable_sources "$source_id" || return 1
  done

  if [[ "$UPDATE_MODE" -eq 1 ]]; then
    log_info "Skipping optional software sources in update mode"
    return 0
  fi

  for source_id in "${source_ids[@]:-}"; do
    source_required_for_install "$source_id" && continue
    enable_source_best_effort "$source_id"
  done
}
