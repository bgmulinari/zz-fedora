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

list_tagged_bats_suites() {
  local tag="$1"
  local tests_dir="$2"
  local suite
  local matched=0

  for suite in "$tests_dir"/*.bats; do
    [[ -f "$suite" ]] || continue
    if grep -qE "^# zz-test-tags:.*\\b${tag}\\b" "$suite"; then
      printf '%s\n' "$suite"
      matched=1
    fi
  done

  if [[ "$matched" -eq 0 ]]; then
    printf 'No bats suites tagged "%s" found under %s. Tag suites with a "# zz-test-tags: %s" line.\n' "$tag" "$tests_dir" "$tag" >&2
    return 1
  fi
}

# Shell files covered by syntax checks and the ShellCheck lint gate.
# Callers must run from the repository root.
shell_lint_targets() {
  printf '%s\n' bootstrap.sh install.sh bin/zz bin/zz.d/* scripts/*.sh iso/scripts/*.sh iso/lib/*.sh lib/*.sh lib/actions/*.sh modules/*.sh tests/*.sh tests/helpers/*.bash
}

run_bash_syntax_checks() {
  local target
  while IFS= read -r target; do
    bash -n "$target"
  done < <(shell_lint_targets)
}

# Lint at warning severity so warning-level findings fail the gate; anything
# reported must be fixed or carry a justified inline "# shellcheck disable".
run_shellcheck_lint() {
  local -a targets=()
  mapfile -t targets < <(shell_lint_targets)
  shellcheck -S warning "${targets[@]}"
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
