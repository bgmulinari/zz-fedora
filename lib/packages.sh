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
      printf '%s\n' "${FLATPAK_BACKEND_PREREQ_PKGS[@]}"
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

# The deferred queue is durable runtime state consumed by first-run, so it
# lives directly under STATE_DIR: PLAN_DIR is regenerable plan output that
# plan_reset deletes on every replan, which would silently drop the queue.
flatpak_deferred_plan_file() {
  printf '%s/deferred.flatpaks\n' "$STATE_DIR"
}

flatpak_deferred_attempts_file() {
  printf '%s.attempts\n' "$(flatpak_deferred_plan_file)"
}

# Bounded first-run retries: each failed pass increments the counter, and
# once the budget is spent the remaining apps are dropped with a warning so
# a permanently failing app cannot block first-run completion forever.
FLATPAK_DEFERRED_MAX_ATTEMPTS=5

flatpak_deferred_attempts() {
  local attempts_file attempts=""
  attempts_file="$(flatpak_deferred_attempts_file)"
  [[ -r "$attempts_file" ]] && attempts="$(<"$attempts_file")"
  [[ "$attempts" =~ ^[0-9]+$ ]] || attempts=0
  printf '%s\n' "$attempts"
}

# Returns 1 while retries remain (first-run stays incomplete so the hook
# fires again next login) and 0 once the budget is spent and the queue has
# been dropped.
deferred_flatpaks_note_failed_pass() {
  local deferred_file attempts_file attempts
  deferred_file="$(flatpak_deferred_plan_file)"
  attempts_file="$(flatpak_deferred_attempts_file)"
  attempts="$(flatpak_deferred_attempts)"
  attempts=$((attempts + 1))
  if [[ "$attempts" -lt "$FLATPAK_DEFERRED_MAX_ATTEMPTS" ]]; then
    printf '%s\n' "$attempts" >"$attempts_file" 2>/dev/null ||
      log_warn "Could not record the deferred Flatpak attempt count: $attempts_file"
    return 1
  fi
  log_warn "Deferred Flatpaks still failing after $attempts first-run attempts; giving up. Install manually with: flatpak install --system flathub <app-id>"
  append_warning "Deferred Flatpaks were dropped after $attempts failed first-run attempts."
  rm -f "$deferred_file" "$attempts_file" 2>/dev/null || true
  return 0
}

# When the flatpak sandbox cannot be created in this environment (the
# Anaconda chroot), extra-data flatpaks are guaranteed to fail their
# apply_extra step. Record them on the deferred list for the first-run
# session step instead of attempting an install that cannot succeed. An
# unreadable metadata probe also defers: see flatpak_app_uses_extra_data.
defer_extra_data_flatpaks() {
  local plan_file="$1"
  local deferred_file attempts_file
  deferred_file="$(flatpak_deferred_plan_file)"
  attempts_file="$(flatpak_deferred_attempts_file)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    [[ -f "$plan_file" ]] || return 0
    flatpak_sandbox_available && return 0
    printf 'DRY-RUN: defer extra-data Flatpaks to first login (flatpak sandbox unavailable)\n'
    return 0
  fi
  if flatpak_sandbox_available; then
    # A queue left by an earlier sandbox-restricted run is superseded: this
    # run installs everything directly.
    rm -f "$deferred_file" "$attempts_file" 2>/dev/null || true
    return 0
  fi
  [[ -f "$plan_file" ]] || return 0
  local app_id probe_status
  while IFS= read -r app_id; do
    [[ -n "$app_id" ]] || continue
    probe_status=0
    flatpak_app_uses_extra_data flathub "$app_id" || probe_status=$?
    if [[ "$probe_status" -eq 1 ]]; then
      continue
    fi
    if [[ "$probe_status" -ge 2 ]]; then
      log_warn "Could not read Flatpak metadata; deferring to first login to be safe: $app_id"
    else
      log_warn "Deferring extra-data Flatpak to the first login session: $app_id"
    fi
    append_warning "Flatpak deferred to first login: $app_id"
    append_plan_entries "$deferred_file" "$app_id"
  done < <(read_plan_file "$plan_file")
  if [[ -f "$deferred_file" ]]; then
    # Root-driven installs hand the file to the state owner immediately so
    # the first-login session can consume and rewrite it.
    chown_state_path_to_owner "$deferred_file"
  fi
  return 0
}

# First-run consumes the deferred list inside the user's session, where the
# sandbox works and polkit allows an active session to install system
# flatpaks. Each verified success is dropped from the list immediately so an
# interrupted run resumes with only the remainder; a failed pass keeps the
# first-run hook registered for a bounded number of next-login retries.
install_deferred_flatpaks() {
  local deferred_file attempts_file
  deferred_file="$(flatpak_deferred_plan_file)"
  attempts_file="$(flatpak_deferred_attempts_file)"
  if [[ ! -e "$deferred_file" ]]; then
    [[ "$DRY_RUN" -eq 1 ]] || rm -f "$attempts_file" 2>/dev/null || true
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install deferred Flatpaks in-session: %s\n' "$deferred_file"
    return 0
  fi
  if [[ ! -r "$deferred_file" ]]; then
    log_warn "Deferred Flatpak list exists but is not readable: $deferred_file"
    local unreadable_status=0
    deferred_flatpaks_note_failed_pass || unreadable_status=$?
    return "$unreadable_status"
  fi
  local -a apps=()
  mapfile -t apps < <(read_plan_file "$deferred_file")
  if [[ "${#apps[@]}" -eq 0 ]]; then
    rm -f "$deferred_file" "$attempts_file" 2>/dev/null || true
    return 0
  fi
  local app_id install_status detail_log failed=0
  for app_id in "${apps[@]}"; do
    log_progress "Installing deferred Flatpak: $app_id"
    install_status=0
    if [[ -n "${LOG_DIR:-}" ]]; then
      detail_log="$LOG_DIR/flatpak-${app_id//[^A-Za-z0-9_.-]/_}-first-run-$(timestamp).log"
      run_cmd_as_user "$TARGET_USER" flatpak install -y --or-update --system flathub "$app_id" >"$detail_log" 2>&1 || install_status=$?
      if [[ "$install_status" -ne 0 ]]; then
        cat "$detail_log" >&2
      fi
    else
      run_cmd_as_user "$TARGET_USER" flatpak install -y --or-update --system flathub "$app_id" || install_status=$?
    fi
    if [[ "$install_status" -eq 0 ]] && verify_plan_entry flatpak "$app_id"; then
      # Queue bookkeeping must not turn a successful install into a failed
      # pass; a stale entry only costs an idempotent --or-update next time.
      remove_plan_entries "$deferred_file" "$app_id" ||
        log_warn "Could not update the deferred Flatpak list: $deferred_file"
      continue
    fi
    log_warn "Deferred Flatpak failed and will be retried on next login: $app_id"
    failed=1
  done
  if [[ "$failed" -ne 0 ]]; then
    local pass_status=0
    deferred_flatpaks_note_failed_pass || pass_status=$?
    return "$pass_status"
  fi
  rm -f "$deferred_file" "$attempts_file" 2>/dev/null ||
    log_warn "Could not remove the deferred Flatpak list: $deferred_file"
  return 0
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

  # is_early_base_bundle reads EARLY_BASE_BUNDLE_IDS in this shell, while
  # effective_base_bundle_ids below runs in a process-substitution subshell;
  # load here so the early/remaining split never sees half-filled arrays.
  catalog_ensure_loaded

  local bundle_id step_index step_backend _step_sources
  local -a step_items=()
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
    while IFS=$'\t' read -r step_index step_backend _step_sources; do
      [[ -n "$step_index" && "$step_backend" == "$backend" ]] || continue
      mapfile -t step_items < <(bundle_step_items "$bundle_id" "$step_index")
      append_plan_entries "$base_plan" "${step_items[@]:-}"
    done < <(bundle_steps "$bundle_id")
  done < <(effective_base_bundle_ids)
}

is_early_base_bundle() {
  array_contains "$1" "${EARLY_BASE_BUNDLE_IDS[@]:-}"
}

install_optional_packages_for_backend() {
  local backend="$1"
  local plan_file="$2"
  local base_plan="$3"
  local skip_plan="${4:-}"
  [[ -f "$plan_file" ]] || return 0

  local optional_plan package_name
  optional_plan="$(mktemp "$CACHE_DIR/optional-${backend}.XXXXXX")"
  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    if [[ -f "$base_plan" ]] && grep -Fx "$package_name" "$base_plan" >/dev/null 2>&1; then
      continue
    fi
    if [[ -n "$skip_plan" && -f "$skip_plan" ]] && grep -Fx "$package_name" "$skip_plan" >/dev/null 2>&1; then
      continue
    fi
    append_plan_entries "$optional_plan" "$package_name"
  done < <(read_plan_file "$plan_file")

  log_progress "Preparing optional $backend package transaction"
  install_from_plan_file "$backend" "$optional_plan" optional "optional packages"
  rm -f "$optional_plan"
}
