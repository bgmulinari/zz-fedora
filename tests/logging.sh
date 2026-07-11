#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-fedora-logging.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export LOG_DIR="$TEST_ROOT/logs"

# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=../lib/idempotency.sh
source "$ROOT_DIR/lib/idempotency.sh"

COMMAND="logging-test"
DRY_RUN=0
NO_TUI=1
init_log_file
[[ -L "$LOG_DIR/latest.log" ]]
[[ "$(readlink -f "$LOG_DIR/latest.log")" == "$LOG_FILE" ]]

emit_output() {
  printf 'stdout from step\n'
  printf 'stderr from step\n' >&2
  log_info "structured log from step"
}

run_with_log_capture file emit_output
grep -F 'stdout from step' "$LOG_FILE" >/dev/null
grep -F 'stderr from step' "$LOG_FILE" >/dev/null
grep -F 'structured log from step' "$LOG_FILE" >/dev/null

tee_output="$(run_with_log_capture tee emit_output 2>&1)"
grep -F 'stdout from step' <<<"$tee_output" >/dev/null
grep -F 'stderr from step' <<<"$tee_output" >/dev/null
grep -F 'stdout from step' "$LOG_FILE" >/dev/null
grep -F 'stderr from step' "$LOG_FILE" >/dev/null

emit_command_output() {
  run_cmd printf 'command output\n'
}

run_with_log_capture file emit_command_output
grep -F 'CMD: printf command\ output' "$LOG_FILE" >/dev/null
grep -F 'command output' "$LOG_FILE" >/dev/null

run_cmd true --password=hunter2 api-token >/dev/null 2>&1
grep -F 'CMD: true --password=REDACTED REDACTED' "$LOG_FILE" >/dev/null
! grep -F 'hunter2' "$LOG_FILE" >/dev/null

export ZZ_INSTALL_PROGRESS_FILE="$TEST_ROOT/install-progress.tsv"
write_install_progress running 2 9 "Base Setup" $'Install\tbase\rpackages'
grep -F $'running\t2\t9\tBase Setup\tInstall base packages' "$ZZ_INSTALL_PROGRESS_FILE" >/dev/null
ACTIVE_STEP_LABEL="Base Setup"
ACTIVE_STEP_CURRENT=4
ACTIVE_STEP_TOTAL=9
log_progress "Resolving package dependencies" >/dev/null 2>&1
grep -F $'running\t4\t9\tBase Setup\tResolving package dependencies' "$ZZ_INSTALL_PROGRESS_FILE" >/dev/null
ACTIVE_STEP_LABEL=""
ACTIVE_STEP_CURRENT=0
ACTIVE_STEP_TOTAL=0

ACTIVE_STEP_LABEL="Exploding Step"
failure_output="$(print_failure_summary 7 2>&1)"
grep -F 'Setup failed.' <<<"$failure_output" >/dev/null
grep -F 'Failed step: Exploding Step' <<<"$failure_output" >/dev/null
grep -F 'Exit code: 7' <<<"$failure_output" >/dev/null
grep -F 'zz logs --tail' <<<"$failure_output" >/dev/null
grep -F 'zz debug' <<<"$failure_output" >/dev/null
FAILURE_SUMMARY_PRINTED=0
ACTIVE_STEP_LABEL=""

DRY_RUN=1
dry_run_output="$(run_cmd touch "$TEST_ROOT/should-not-exist")"
grep -F 'DRY-RUN: touch' <<<"$dry_run_output" >/dev/null
[[ ! -e "$TEST_ROOT/should-not-exist" ]]

DRY_RUN=0
COMMAND_PREVIEW=1
ASSUME_YES=1
preview_output="$(run_cmd printf 'preview command\n' 2>&1)"
grep -F 'Command: printf preview\ command' <<<"$preview_output" >/dev/null
grep -F 'preview command' <<<"$preview_output" >/dev/null
COMMAND_PREVIEW=0
ASSUME_YES=0

default_log_output="$(
  unset LOG_DIR
  unset LOG_FILE
  XDG_STATE_HOME="$TEST_ROOT/default-state" \
  XDG_CACHE_HOME="$TEST_ROOT/default-cache" \
  XDG_CONFIG_HOME="$TEST_ROOT/default-config" \
  bash -c 'source "'"$ROOT_DIR"'/lib/common.sh"; COMMAND=default-log-test; init_log_file; printf "%s\n" "$LOG_FILE"'
)"
grep -F "$TEST_ROOT/default-state/zz-fedora/logs/default-log-test-" <<<"$default_log_output" >/dev/null

printf 'logging ok\n'
