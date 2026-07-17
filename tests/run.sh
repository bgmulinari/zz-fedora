#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=helpers/runner.bash
source "$ROOT_DIR/tests/helpers/runner.bash"

if [[ "$#" -ne 1 || -z "$1" ]]; then
  printf 'Usage: tests/run.sh <tag>\n' >&2
  printf 'Runs every tests/*.bats suite carrying a "# zz-test-tags: <tag>" line.\n' >&2
  exit 2
fi
tag="$1"

if ! command -v bats >/dev/null 2>&1; then
  printf 'bats is required to run tests. On Fedora: sudo dnf install bats\n' >&2
  exit 127
fi

mapfile -t suites < <(list_tagged_bats_suites "$tag" tests)
if [[ "${#suites[@]}" -eq 0 ]]; then
  exit 1
fi

run_bats_suites "${suites[@]}"
