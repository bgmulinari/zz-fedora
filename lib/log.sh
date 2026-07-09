#!/usr/bin/env bash
set -Eeuo pipefail

log_ts() {
  date +"%Y-%m-%d %H:%M:%S"
}

shell_quote() {
  local quoted=""
  local arg
  for arg in "$@"; do
    printf -v arg "%q" "$arg"
    if [[ -n "$quoted" ]]; then
      quoted+=" "
    fi
    quoted+="$arg"
  done
  printf '%s' "$quoted"
}

redact_arg() {
  local arg="$1"
  local lower="${arg,,}"
  case "$lower" in
    *password=*|*passwd=*|*token=*|*secret=*|*apikey=*|*api_key=*|*credential=*)
      printf '%s=REDACTED' "${arg%%=*}"
      ;;
    *password*|*passwd*|*token*|*secret*|*apikey*|*api_key*|*credential*)
      printf 'REDACTED'
      ;;
    *)
      printf '%s' "$arg"
      ;;
  esac
}

redacted_shell_quote() {
  local -a redacted=()
  local arg
  for arg in "$@"; do
    redacted+=("$(redact_arg "$arg")")
  done
  shell_quote "${redacted[@]}"
}

init_log_file() {
  [[ -n "${LOG_FILE:-}" ]] && return 0
  ensure_state_dirs
  LOG_FILE="$LOG_DIR/${COMMAND}-$(date '+%Y-%m-%d_%H-%M-%S').log"
  export LOG_FILE
  ln -sfn "$LOG_FILE" "$LOG_DIR/latest.log"
  [[ "${PLAN_FORMAT:-text}" == "json" ]] || printf 'Log file: %s\n' "$LOG_FILE"
}

log_to_file() {
  local level="$1"
  shift
  [[ -n "${LOG_FILE:-}" ]] || return 0

  printf '[%s] %s %s\n' "$(log_ts)" "$(printf '%-5s' "${level^^}")" "$*" >>"$LOG_FILE"
}

log_emit() {
  local level="$1"
  local padded_level="$2"
  shift 2

  case "${LOG_CAPTURE_MODE:-}" in
    file)
      log_to_file "$level" "$*"
      return 0
      ;;
    tee)
      printf '[%s] %s %s\n' "$(log_ts)" "$padded_level" "$*" >&2
      return 0
      ;;
  esac

  if [[ "${TUI_PROGRESS_ACTIVE:-0}" -eq 1 && "${NO_TUI:-0}" -eq 0 && -t 2 ]] && command -v gum >/dev/null 2>&1; then
    log_to_file "$level" "$*"
    return 0
  fi

  if [[ "${NO_TUI:-0}" -eq 0 && -t 2 ]] && command -v gum >/dev/null 2>&1; then
    gum log --level "$level" "$*"
  else
    printf '[%s] %s %s\n' "$(log_ts)" "$padded_level" "$*" >&2
  fi

  log_to_file "$level" "$*"
}

log_info() {
  log_emit info "INFO " "$*"
}

log_warn() {
  log_emit warn "WARN " "$*"
}

log_error() {
  log_emit error "ERROR" "$*"
}

progress_field() {
  local value="${1:-}"
  value="${value//$'\t'/ }"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  printf '%s' "$value"
}

write_install_progress() {
  [[ -n "${ZZ_INSTALL_PROGRESS_FILE:-}" ]] || return 0

  local status="$1"
  local current="$2"
  local total="$3"
  local label="$4"
  local message="${5:-}"
  local progress_dir

  progress_dir="$(dirname "$ZZ_INSTALL_PROGRESS_FILE")"
  mkdir -p "$progress_dir"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date +%s)" \
    "$(progress_field "$status")" \
    "$(progress_field "$current")" \
    "$(progress_field "$total")" \
    "$(progress_field "$label")" \
    "$(progress_field "$message")" >>"$ZZ_INSTALL_PROGRESS_FILE"
}

log_progress() {
  local message="$*"
  [[ -n "$message" ]] || return 0

  if [[ -n "${ACTIVE_STEP_LABEL:-}" ]]; then
    write_install_progress \
      running \
      "${ACTIVE_STEP_CURRENT:-0}" \
      "${ACTIVE_STEP_TOTAL:-0}" \
      "$ACTIVE_STEP_LABEL" \
      "$message"
  fi
  log_info "$message"
}

print_readiness_warnings_for_failure() {
  local readiness_status_file="$PLAN_DIR/readiness/status.tsv"
  [[ -f "$readiness_status_file" ]] || return 0

  local warning_count
  warning_count="$(awk -F'\t' '$4=="fatal" || $4=="warn"{count++} END{print count+0}' "$readiness_status_file")"
  [[ "$warning_count" -gt 0 ]] || return 0

  printf '\nReadiness warnings:\n' >&2
  awk -F'\t' '$4=="fatal" || $4=="warn" {
    detail = $5 == "" ? "" : " - " $5
    printf "  [%s] %s %s: %s%s\n", $4, $1, $2, $3, detail
  }' "$readiness_status_file" >&2
}

print_failure_summary() {
  local exit_code="${1:-1}"
  [[ "${FAILURE_SUMMARY_PRINTED:-0}" -eq 0 ]] || return 0
  FAILURE_SUMMARY_PRINTED=1

  printf '\nSetup failed.\n' >&2
  if [[ -n "${ACTIVE_STEP_ID:-}" ]]; then
    printf 'Failed step ID: %s\n' "$ACTIVE_STEP_ID" >&2
  fi
  if [[ -n "${ACTIVE_STEP_LABEL:-}" ]]; then
    printf 'Failed step: %s\n' "$ACTIVE_STEP_LABEL" >&2
  fi
  if [[ -n "${ACTIVE_STEP_STARTED_AT:-}" ]]; then
    local now duration
    now="$(date +%s)"
    duration=$((now - ACTIVE_STEP_STARTED_AT))
    printf 'Step duration: %ss\n' "$duration" >&2
  fi
  printf 'Exit code: %s\n' "$exit_code" >&2
  if [[ -n "${LAST_COMMAND_CONTEXT:-}" ]]; then
    printf 'Last command: %s\n' "$LAST_COMMAND_CONTEXT" >&2
  fi

  if [[ -n "${LOG_FILE:-}" ]]; then
    printf 'Log file: %s\n' "$LOG_FILE" >&2
    if [[ -f "$LOG_FILE" ]]; then
      printf '\nLast log lines:\n' >&2
      tail -n "${FAILURE_LOG_TAIL_LINES:-20}" "$LOG_FILE" >&2 || true
    fi
  fi

  print_readiness_warnings_for_failure
  printf '\nNext commands:\n' >&2
  printf '  zz logs --tail\n' >&2
  printf '  zz debug\n' >&2
  printf '  ./install.sh check --distro %s --dry-run\n' "${DISTRO:-auto}" >&2
}

fatal_error_handler() {
  local exit_code="${1:-1}"
  [[ "$exit_code" -eq 0 ]] && return 0
  [[ "${IN_FATAL_HANDLER:-0}" -eq 1 ]] && exit "$exit_code"
  IN_FATAL_HANDLER=1
  print_failure_summary "$exit_code"
  exit "$exit_code"
}

die() {
  log_error "$*"
  print_failure_summary 1
  exit 1
}

log_command() {
  [[ -n "${LOG_FILE:-}" ]] || return 0
  LAST_COMMAND_CONTEXT="$(redacted_shell_quote "$@")"
  log_to_file info "CMD: $LAST_COMMAND_CONTEXT"
}

run_with_log_capture() {
  local mode="$1"
  shift

  [[ -n "${LOG_FILE:-}" ]] || {
    "$@"
    return $?
  }

  case "$mode" in
    file)
      (
        export LOG_CAPTURE_MODE=file
        "$@"
      ) >>"$LOG_FILE" 2>&1
      ;;
    tee)
      (
        export LOG_CAPTURE_MODE=tee
        "$@"
      ) > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)
      ;;
    *)
      die "Unknown log capture mode: $mode"
      ;;
  esac
}
