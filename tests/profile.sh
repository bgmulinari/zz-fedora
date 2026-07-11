#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v bats >/dev/null 2>&1; then
  printf 'bats is required to profile tests. On Fedora: sudo dnf install bats\n' >&2
  exit 127
fi

threshold_seconds="${ZZ_TEST_PROFILE_THRESHOLD:-15}"
timings_file="$(mktemp /tmp/zz-fedora-profile.XXXXXX)"
trap 'rm -f "$timings_file"' EXIT

status=0
while IFS= read -r suite; do
  start_ns="$(date +%s%N)"
  bats "$suite"
  end_ns="$(date +%s%N)"
  elapsed="$(awk -v elapsed_ns="$((end_ns - start_ns))" 'BEGIN {printf "%.3f", elapsed_ns / 1000000000}')"
  printf '%s\t%s\n' "$elapsed" "$suite" >>"$timings_file"
  awk -v elapsed="$elapsed" -v threshold="$threshold_seconds" 'BEGIN {exit elapsed > threshold ? 0 : 1}' && status=1
done < <(find tests -maxdepth 1 -type f -name '*.bats' | sort)

printf 'Suite timings (slowest first):\n'
sort -nr "$timings_file"

if [[ "$status" -ne 0 ]]; then
  printf 'One or more suites exceeded %ss.\n' "$threshold_seconds" >&2
fi
exit "$status"
