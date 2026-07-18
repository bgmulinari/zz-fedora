#!/usr/bin/env bash
set -Eeuo pipefail

native_backend() {
  printf 'dnf\n'
}

package_file_for_backend() {
  case "$1" in
    dnf) printf '%s/packages/dnf.pkgs\n' "$PLAN_DIR" ;;
    flatpak) printf '%s/flatpak/apps.flatpaks\n' "$PLAN_DIR" ;;
    action) printf '%s/actions/actions.list\n' "$PLAN_DIR" ;;
    *) die "Unsupported plan package backend: $1" ;;
  esac
}

prereq_file_for_backend() {
  case "$1" in
    dnf) printf '%s/prereqs/dnf.pkgs\n' "$PLAN_DIR" ;;
    flatpak) printf '%s/prereqs/flatpak.flatpaks\n' "$PLAN_DIR" ;;
    action) printf '%s/prereqs/actions.list\n' "$PLAN_DIR" ;;
    *) die "Unsupported prereq backend: $1" ;;
  esac
}

backend_prerequisite_backend() {
  case "$1" in
    dnf|action) return 1 ;;
    flatpak) native_backend ;;
    *) die "Unsupported backend: $1" ;;
  esac
}

backend_prerequisite_items() {
  case "$1" in
    dnf|action) return 0 ;;
    flatpak)
      manifest_entries "$ROOT_DIR/packages/official/flatpak.pkgs"
      ;;
    *)
      die "Unsupported backend: $1"
      ;;
  esac
}

append_plan_entries() {
  local destination="$1"
  shift
  local destination_dir="."
  [[ "$destination" == */* ]] && destination_dir="${destination%/*}"
  [[ -d "$destination_dir" ]] || mkdir -p "$destination_dir"
  [[ -e "$destination" ]] || : >"$destination"

  local -A seen=()
  local existing
  while IFS= read -r existing; do
    [[ -n "$existing" ]] || continue
    seen["$existing"]=1
  done <"$destination"

  local item
  local changed=0
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    [[ -n "${seen[$item]:-}" ]] && continue
    printf '%s\n' "$item" >>"$destination"
    seen["$item"]=1
    changed=1
  done
  if [[ "$changed" -ne 0 && "${DEFER_PLAN_SORT:-0}" -ne 1 ]]; then
    sort -u "$destination" -o "$destination"
  fi
}

read_plan_file() {
  local plan_file="$1"
  [[ -f "$plan_file" ]] || return 0
  read_clean_lines "$plan_file" | sort -u
}

plan_has_any_backend_entry() {
  local plan_file="$1"
  shift
  local entry
  for entry in "$@"; do
    [[ -f "$plan_file" ]] || continue
    if grep -Fx "$entry" "$plan_file" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

remove_plan_entries() {
  local plan_file="$1"
  shift
  [[ -f "$plan_file" ]] || return 0
  [[ "$#" -gt 0 ]] || return 0

  local filtered
  filtered="$(mktemp "$CACHE_DIR/plan-filter.XXXXXX")"
  local entry
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    array_contains "$entry" "$@" && continue
    printf '%s\n' "$entry" >>"$filtered"
  done < <(read_plan_file "$plan_file")
  mv -f "$filtered" "$plan_file"
}

record_system_skip() {
  local backend="$1"
  local item="$2"
  local reason="$3"
  local skip_file="$PLAN_DIR/system-skips.tsv"
  mkdir -p "$(dirname "$skip_file")"
  touch "$skip_file"
  grep -Fx "$backend	$item	$reason" "$skip_file" >/dev/null 2>&1 && return 0
  printf '%s\t%s\t%s\n' "$backend" "$item" "$reason" >>"$skip_file"
}

install_pinned_git_checkout() {
  local label="$1"
  local repository="$2"
  local commit="$3"
  local destination="$4"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install %s at commit %s -> %s\n' "$label" "$commit" "$destination"
    return 0
  fi

  if [[ -e "$destination" && ! -d "$destination/.git" ]]; then
    die "$label destination exists but is not a Git checkout: $destination"
  fi
  if [[ ! -d "$destination/.git" ]]; then
    run_cmd_as_user "$TARGET_USER" git clone --filter=blob:none --no-checkout "$repository" "$destination"
  fi
  run_cmd_as_user "$TARGET_USER" git -C "$destination" fetch --depth=1 origin "$commit"
  run_cmd_as_user "$TARGET_USER" git -C "$destination" checkout --detach "$commit"

  local installed_commit
  # The checkout belongs to the target user. Running this verification as root
  # triggers Git's dubious-ownership protection on fresh installs even though
  # the user-owned checkout is valid.
  installed_commit="$(run_cmd_as_user "$TARGET_USER" git -C "$destination" rev-parse HEAD 2>/dev/null || true)"
  [[ "$installed_commit" == "$commit" ]] || die "$label checkout verification failed: expected $commit, got ${installed_commit:-missing}"
}

install_from_plan_file() {
  local backend="$1"
  local plan_file="$2"
  local mode="${3:-required}"
  local label="${4:-packages}"
  [[ -f "$plan_file" ]] || return 0
  mapfile -t packages < <(read_plan_file "$plan_file")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  printf '%s %s: %s\n' "$backend" "$label" "${#packages[@]}"
  log_progress "Installing ${#packages[@]} $backend $label"
  if package_install_idempotent "$backend" "${packages[@]}"; then
    if [[ "$mode" == "required" ]]; then
      log_progress "Verifying required $backend $label"
      verify_plan_entries "$backend" "$plan_file" "$label" required || return 1
      return 0
    fi
    if verify_plan_entries "$backend" "$plan_file" "$label" optional; then
      return 0
    fi
    log_warn "Optional $backend package transaction completed but verification failed; retrying packages individually."
  elif [[ "$mode" != "optional" ]]; then
    log_error "Required $backend $label transaction failed. Check the package manager output above."
    return 1
  else
    log_warn "Optional $backend package transaction failed; retrying packages individually."
  fi

  local package_name
  local failed=0
  for package_name in "${packages[@]}"; do
    log_progress "Installing optional $backend package: $package_name"
    if package_install_idempotent "$backend" "$package_name" \
      && verify_plan_entry "$backend" "$package_name"; then
      continue
    fi
    log_warn "Optional $backend package failed and will be skipped for now: $package_name"
    append_warning "Optional $backend package failed and was skipped: $package_name"
    failed=1
  done
  [[ "$failed" -eq 0 ]] || log_warn "Continuing after optional $backend package failures."
  return 0
}

verify_plan_entry() {
  local backend="$1"
  local entry="$2"
  [[ "$DRY_RUN" -eq 0 ]] || return 0
  [[ "${VERIFY_INSTALLS:-1}" -eq 1 ]] || return 0

  case "$backend" in
    dnf)
      fedora_package_installed "$entry"
      ;;
    flatpak)
      flatpak info --system "$entry" >/dev/null 2>&1 || flatpak info "$entry" >/dev/null 2>&1
      ;;
    *)
      die "Unsupported package verification backend: $backend"
      ;;
  esac
}

verify_plan_entries() {
  local backend="$1"
  local plan_file="$2"
  local label="$3"
  local mode="$4"
  [[ "$DRY_RUN" -eq 0 ]] || return 0
  [[ "${VERIFY_INSTALLS:-1}" -eq 1 ]] || return 0
  [[ -f "$plan_file" ]] || return 0

  local entry missing=0
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    verify_plan_entry "$backend" "$entry" && continue
    if [[ "$mode" == "required" ]]; then
      log_error "Required $label missing after install: $entry"
    else
      log_warn "Optional $label missing after install: $entry"
    fi
    missing=1
  done < <(read_plan_file "$plan_file")

  [[ "$missing" -eq 0 ]]
}

build_base_package_plan_for_backend() {
  local backend="$1"
  local base_plan="$2"
  local filter="${3:-all}"

  local bundle_id
  local -a bundle_items=()
  while IFS= read -r bundle_id; do
    [[ -n "$bundle_id" ]] || continue
    case "$filter" in
      all)
        ;;
      early)
        is_early_base_bundle "$bundle_id" || continue
        ;;
      remaining)
        is_early_base_bundle "$bundle_id" && continue
        ;;
      *)
        die "Unsupported base bundle filter: $filter"
        ;;
    esac
    load_bundle_descriptor "$bundle_id" || die "Unknown base bundle: $bundle_id"
    [[ "$BUNDLE_INSTALLER" == "$backend" ]] || continue
    mapfile -t bundle_items < <(bundle_manifest_entries)
    append_plan_entries "$base_plan" "${bundle_items[@]:-}"
  done < <(effective_base_bundle_ids)
}

is_early_base_bundle() {
  array_contains "$1" "${EARLY_BASE_BUNDLE_IDS[@]:-}"
}

install_optional_packages_for_backend() {
  local backend="$1"
  local plan_file="$2"
  local base_plan="$3"
  [[ -f "$plan_file" ]] || return 0

  local optional_plan package_name
  optional_plan="$(mktemp "$CACHE_DIR/optional-${backend}.XXXXXX")"
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    if [[ -f "$base_plan" ]] && grep -Fx "$package_name" "$base_plan" >/dev/null 2>&1; then
      continue
    fi
    append_plan_entries "$optional_plan" "$package_name"
  done < <(read_plan_file "$plan_file")

  log_progress "Preparing optional $backend package transaction"
  install_from_plan_file "$backend" "$optional_plan" optional "optional packages"
  rm -f "$optional_plan"
}
