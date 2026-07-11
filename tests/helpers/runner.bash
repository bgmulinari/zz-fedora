#!/usr/bin/env bash
set -Eeuo pipefail

bats_parallel_jobs() {
  if [[ -n "${ZZ_TEST_JOBS:-}" ]]; then
    [[ "$ZZ_TEST_JOBS" =~ ^[1-9][0-9]*$ ]] || {
      printf 'ZZ_TEST_JOBS must be a positive integer.\n' >&2
      return 2
    }
    printf '%s\n' "$ZZ_TEST_JOBS"
    return 0
  fi

  if ! command -v parallel >/dev/null 2>&1 && ! command -v rush >/dev/null 2>&1; then
    printf '1\n'
    return 0
  fi

  local processors
  processors="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')"
  [[ "$processors" =~ ^[1-9][0-9]*$ ]] || processors=2
  ((processors > 4)) && processors=4
  printf '%s\n' "$processors"
}

run_bats_suites() {
  local jobs
  jobs="$(bats_parallel_jobs)" || return
  if [[ "$jobs" -gt 1 ]]; then
    bats --jobs "$jobs" --no-parallelize-within-files "$@"
  else
    bats "$@"
  fi
}
