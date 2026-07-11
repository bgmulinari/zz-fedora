#!/usr/bin/env bash

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

setup_test_env() {
  local current_user
  current_user="${USER:-}"
  [[ -n "$current_user" ]] || current_user="$(id -un)"
  TEST_ROOT="${BATS_TEST_TMPDIR:-$(mktemp -d /tmp/zz-fedora-bats.XXXXXX)}"
  export XDG_STATE_HOME="$TEST_ROOT/state"
  export XDG_CACHE_HOME="$TEST_ROOT/cache"
  export XDG_CONFIG_HOME="$TEST_ROOT/config"
  export LOG_DIR="$TEST_ROOT/logs"
  export TARGET_HOME="$TEST_ROOT/home"
  export TARGET_USER="${TARGET_USER:-$current_user}"
  export FLATPAK_REMOTE_WAIT_SECONDS=0
  export FLATPAK_REMOTE_RETRY_SECONDS=0
  export VERIFY_INSTALLS=0
  export DESKTOP_APP_PROFILE=full
  mkdir -p "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$LOG_DIR" "$TARGET_HOME"
}

source_core() {
  # shellcheck source=../../lib/common.sh
  source "$ROOT_DIR/lib/common.sh"
  # shellcheck source=../../lib/idempotency.sh
  source "$ROOT_DIR/lib/idempotency.sh"
  # shellcheck source=../../lib/cli.sh
  source "$ROOT_DIR/lib/cli.sh"
  # shellcheck source=../../lib/packages.sh
  source "$ROOT_DIR/lib/packages.sh"
  # shellcheck source=../../lib/sources.sh
  source "$ROOT_DIR/lib/sources.sh"
  # shellcheck source=../../lib/systemd.sh
  source "$ROOT_DIR/lib/systemd.sh"
  # shellcheck source=../../lib/stow.sh
  source "$ROOT_DIR/lib/stow.sh"
  # shellcheck source=../../lib/files.sh
  source "$ROOT_DIR/lib/files.sh"
  # shellcheck source=../../lib/tui.sh
  source "$ROOT_DIR/lib/tui.sh"
  # shellcheck source=../../lib/planner.sh
  source "$ROOT_DIR/lib/planner.sh"
  # shellcheck source=../../lib/readiness.sh
  source "$ROOT_DIR/lib/readiness.sh"
  # shellcheck source=../../lib/fedora.sh
  source "$ROOT_DIR/lib/fedora.sh"
}

source_modules() {
  local module_file
  for module_file in "$ROOT_DIR"/modules/*.sh; do
    # shellcheck disable=SC1090
    source "$module_file"
  done
}

source_bootstrap_functions() {
  local bootstrap_source="$TEST_ROOT/bootstrap-source.sh"
  sed '$d' "$ROOT_DIR/bootstrap.sh" >"$bootstrap_source"
  # shellcheck disable=SC1090
  source "$bootstrap_source"
}

reset_test_selections() {
  CATEGORY_OVERRIDES=()
  CATEGORY_ADDITIONS=()
  CATEGORY_OVERRIDE_PRESENT=()
  local category
  for category in ai browsers dev dotnet gaming media office; do
    set_category_override "$category" ""
  done
}

run_without_bats_debug_trap() {
  local saved_debug_trap
  saved_debug_trap="$(trap -p DEBUG)"
  trap - DEBUG
  "$@"
  local command_status=$?
  if [[ -n "$saved_debug_trap" ]]; then
    eval "$saved_debug_trap"
  fi
  return "$command_status"
}

capture_without_bats_debug_trap() {
  local output_name="$1"
  local status_name="$2"
  shift 2
  local -n output_ref="$output_name"
  local -n status_ref="$status_name"
  local saved_debug_trap captured command_status had_errexit=0

  saved_debug_trap="$(trap -p DEBUG)"
  [[ "$-" == *e* ]] && had_errexit=1
  trap - DEBUG
  set +e
  captured="$("$@" 2>&1)"
  command_status=$?
  if [[ "$had_errexit" -eq 1 ]]; then
    set -e
  else
    set +e
  fi
  if [[ -n "$saved_debug_trap" ]]; then
    eval "$saved_debug_trap"
  fi
  output_ref="$captured"
  status_ref="$command_status"
}

build_test_plan() {
  COMMAND="${COMMAND:-install}"
  TARGET_HOME="${TARGET_HOME:-$TEST_ROOT/home}"
  TARGET_USER="${TARGET_USER:-${DEFAULT_TARGET_USER:-$(id -un)}}"
  DRY_RUN=1
  if [[ "${ZZ_TEST_CONFLICT_PREVIEW:-0}" -ne 1 ]] && declare -F stow_write_conflict_preview >/dev/null 2>&1; then
    stow_write_conflict_preview() { :; }
  fi

  local cache_key cache_root cache_dir cache_tmp
  cache_key="plan"
  cache_key+="__desktop_app_profile=$(resolved_desktop_app_profile)"
  local selection
  for selection in "$@"; do
    cache_key+="__${selection//[^A-Za-z0-9_.=-]/_}"
  done
  local cache_namespace="${BATS_TEST_FILENAME:-standalone}"
  cache_namespace="${cache_namespace##*/}"
  cache_namespace="${cache_namespace//[^A-Za-z0-9_.-]/_}"
  cache_root="${BATS_RUN_TMPDIR:-${BATS_TMPDIR:-/tmp}/zz-fedora-plan-cache-${BATS_ROOT_PID:-$PPID}}/$cache_namespace"
  if [[ "${ZZ_TEST_CONFLICT_PREVIEW:-0}" -ne 1 && -n "$cache_root" ]]; then
    cache_dir="$cache_root/$cache_key"
    if [[ -f "$cache_dir/.complete" ]]; then
      reset_test_selections
      for selection in "$@"; do
        parse_select_arg "$selection"
      done
      rm -rf "$PLAN_DIR"
      mkdir -p "$PLAN_DIR"
      cp -a "$cache_dir/." "$PLAN_DIR/"
      rm -f "$PLAN_DIR/.complete"
      return 0
    fi
  fi

  reset_test_selections
  for selection in "$@"; do
    parse_select_arg "$selection"
  done
  run_without_bats_debug_trap build_plan_from_selections

  if [[ "${ZZ_TEST_CONFLICT_PREVIEW:-0}" -ne 1 && -n "${cache_root:-}" ]]; then
    cache_dir="$cache_root/$cache_key"
    cache_tmp="$cache_root/.tmp-$cache_key-$$"
    rm -rf "$cache_tmp"
    mkdir -p "$cache_tmp"
    cp -a "$PLAN_DIR/." "$cache_tmp/"
    : >"$cache_tmp/.complete"
    mkdir -p "$cache_root"
    rm -rf "$cache_dir"
    mv "$cache_tmp" "$cache_dir"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  grep -F -- "$needle" <<<"$haystack" >/dev/null || {
    printf 'expected output to contain: %s\n' "$needle" >&2
    return 1
  }
}

refute_contains() {
  local haystack="$1"
  local needle="$2"
  ! grep -F -- "$needle" <<<"$haystack" >/dev/null || {
    printf 'expected output not to contain: %s\n' "$needle" >&2
    return 1
  }
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -F -- "$needle" "$file" >/dev/null || {
    printf 'expected %s to contain: %s\n' "$file" "$needle" >&2
    return 1
  }
}

refute_file_contains() {
  local file="$1"
  local needle="$2"
  ! grep -F -- "$needle" "$file" >/dev/null || {
    printf 'expected %s not to contain: %s\n' "$file" "$needle" >&2
    return 1
  }
}

assert_file_line() {
  local file="$1"
  local line="$2"
  grep -Fx -- "$line" "$file" >/dev/null || {
    printf 'expected %s to contain line: %s\n' "$file" "$line" >&2
    return 1
  }
}

refute_file_line() {
  local file="$1"
  local line="$2"
  ! grep -Fx -- "$line" "$file" >/dev/null || {
    printf 'expected %s not to contain line: %s\n' "$file" "$line" >&2
    return 1
  }
}

assert_plan_has() {
  assert_file_line "$1" "$2"
}

refute_plan_has() {
  refute_file_line "$1" "$2"
}

assert_tsv_row() {
  local file="$1"
  local row="$2"
  grep -Fx -- "$row" "$file" >/dev/null || {
    printf 'expected TSV row in %s:\n%s\n' "$file" "$row" >&2
    return 1
  }
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  [[ "$expected" == "$actual" ]] || {
    printf 'expected: %s\nactual:   %s\n' "$expected" "$actual" >&2
    return 1
  }
}

assert_unique_file() {
  local file="$1"
  assert_equal "$(sort -u "$file" | wc -l | tr -d ' ')" "$(wc -l <"$file" | tr -d ' ')"
}

assert_base_manifests_in_plan() {
  local bundle_id plan_file base_item

  for bundle_id in "${BASE_BUNDLE_IDS[@]}"; do
    assert_plan_has "$PLAN_DIR/bundles.list" "$bundle_id"
    load_bundle_descriptor "$bundle_id"
    plan_file="$(package_file_for_backend "$BUNDLE_INSTALLER")"
    while IFS= read -r base_item; do
      [[ -n "$base_item" ]] || continue
      assert_plan_has "$plan_file" "$base_item"
    done < <(manifest_entries "$ROOT_DIR/$BUNDLE_ITEMS_FILE")
  done
}
