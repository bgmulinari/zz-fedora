#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=helpers/runner.bash
source "$ROOT_DIR/tests/helpers/runner.bash"

if ! command -v bats >/dev/null 2>&1; then
  printf 'bats is required to run tests. On Fedora: sudo dnf install bats\n' >&2
  exit 127
fi

show_timings=0
if [[ "${1:-}" == "--timings" ]]; then
  show_timings=1
  shift
fi

run_bash_syntax_checks

mapfile -t suites < <(find tests -maxdepth 1 -type f -name '*.bats' | sort)

if [[ "$show_timings" -eq 1 ]]; then
  timings_file="$(mktemp /tmp/zz-fedora-full-timings.XXXXXX)"
  trap 'rm -f "$timings_file"' EXIT
  for suite in "${suites[@]}"; do
    start_ns="$(date +%s%N)"
    bats "$suite"
    end_ns="$(date +%s%N)"
    awk -v suite="$suite" -v elapsed_ns="$((end_ns - start_ns))" 'BEGIN {printf "%.3f\t%s\n", elapsed_ns / 1000000000, suite}' >>"$timings_file"
  done
  printf '\nSuite timings (slowest first):\n'
  sort -nr "$timings_file"
else
  run_bats_suites "${suites[@]}"
fi

if command -v shellcheck >/dev/null 2>&1; then
  run_shellcheck_lint
elif [[ "${ZZ_TEST_LINT:-0}" -eq 1 ]]; then
  printf 'ZZ_TEST_LINT=1 was set, but shellcheck is not installed.\n' >&2
  exit 127
fi

printf 'full ok\n'
