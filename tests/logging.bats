#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  COMMAND="logging-test"
  DRY_RUN=0
  NO_TUI=1
}

emit_output() {
  printf 'stdout from step\n'
  printf 'stderr from step\n' >&2
  log_info "structured log from step"
}

wait_for_file_line() {
  local file="$1"
  local needle="$2"
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    grep -F -- "$needle" "$file" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  assert_file_contains "$file" "$needle"
}

@test "tee capture mirrors step output to the terminal and the log file" {
  init_log_file

  tee_output="$(run_with_log_capture tee emit_output 2>&1)"

  assert_contains "$tee_output" "stdout from step"
  assert_contains "$tee_output" "stderr from step"
  wait_for_file_line "$LOG_FILE" "stdout from step"
  wait_for_file_line "$LOG_FILE" "stderr from step"
}

@test "run_cmd logs the quoted command line and its captured output" {
  init_log_file

  emit_command_output() {
    run_cmd printf 'command output\n'
  }
  run_with_log_capture file emit_command_output

  assert_file_contains "$LOG_FILE" 'CMD: printf command\ output'
  assert_file_contains "$LOG_FILE" "command output"
}

@test "install progress rows are appended as sanitized TSV" {
  export ZZ_INSTALL_PROGRESS_FILE="$TEST_ROOT/install-progress.tsv"

  write_install_progress running 2 9 "Base Setup" $'Install\tbase\rpackages'
  assert_file_contains "$ZZ_INSTALL_PROGRESS_FILE" $'running\t2\t9\tBase Setup\tInstall base packages'

  ACTIVE_STEP_LABEL="Base Setup"
  ACTIVE_STEP_CURRENT=4
  ACTIVE_STEP_TOTAL=9
  log_progress "Resolving package dependencies" >/dev/null 2>&1
  assert_file_contains "$ZZ_INSTALL_PROGRESS_FILE" $'running\t4\t9\tBase Setup\tResolving package dependencies'
}

@test "failure summary names the failed step, exit code, and next commands" {
  init_log_file
  ACTIVE_STEP_LABEL="Exploding Step"
  FAILURE_SUMMARY_PRINTED=0

  failure_output="$(print_failure_summary 7 2>&1)"

  assert_contains "$failure_output" "Setup failed."
  assert_contains "$failure_output" "Failed step: Exploding Step"
  assert_contains "$failure_output" "Exit code: 7"
  assert_contains "$failure_output" "zz logs --tail"
  assert_contains "$failure_output" "zz debug"
}

@test "command preview prints the command before running it with --yes" {
  COMMAND_PREVIEW=1
  ASSUME_YES=1

  preview_output="$(run_cmd printf 'preview command\n' 2>&1)"

  assert_contains "$preview_output" 'Command: printf preview\ command'
  assert_contains "$preview_output" "preview command"
}

@test "log files default under the state directory when LOG_DIR is unset" {
  default_log_output="$(
    env -u LOG_DIR -u LOG_FILE \
      XDG_STATE_HOME="$TEST_ROOT/default-state" \
      XDG_CACHE_HOME="$TEST_ROOT/default-cache" \
      XDG_CONFIG_HOME="$TEST_ROOT/default-config" \
      bash -c 'source "$1/lib/common.sh"; COMMAND=default-log-test; init_log_file; printf "%s\n" "$LOG_FILE"' _ "$ROOT_DIR"
  )"

  assert_contains "$default_log_output" "$TEST_ROOT/default-state/zz-fedora/logs/default-log-test-"
}
