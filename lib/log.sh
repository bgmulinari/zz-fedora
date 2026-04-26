#!/usr/bin/env bash
set -Eeuo pipefail

log_ts() {
  date +"%Y-%m-%d %H:%M:%S"
}

init_log_file() {
  [[ -n "${LOG_FILE:-}" ]] && return 0
  ensure_state_dirs
  LOG_FILE="$LOG_DIR/${COMMAND}-$(date '+%Y-%m-%d_%H-%M-%S').log"
  export LOG_FILE
}

log_to_file() {
  local level="$1"
  shift
  [[ -n "${LOG_FILE:-}" ]] || return 0

  if command -v gum >/dev/null 2>&1; then
    gum log --level "$level" --time datetime --file "$LOG_FILE" "$*"
    return 0
  fi

  printf '[%s] %s %s\n' "$(log_ts)" "$(printf '%-5s' "${level^^}")" "$*" >>"$LOG_FILE"
}

log_emit() {
  local level="$1"
  local padded_level="$2"
  shift 2

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

die() {
  log_error "$*"
  exit 1
}
