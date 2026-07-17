#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=helpers/runner.bash
source "$ROOT_DIR/tests/helpers/runner.bash"

require_bats() {
  if ! command -v bats >/dev/null 2>&1; then
    printf 'bats is required to run tests. On Fedora: sudo dnf install bats\n' >&2
    exit 127
  fi
}

require_bats

bash -n bootstrap.sh
bash -n install.sh
bash -n bin/zz
bash -n bin/zz.d/*
bash -n scripts/*.sh
bash -n scripts/lib/*.sh
bash -n lib/*.sh
bash -n modules/*.sh
bash -n tests/*.sh
bash -n tests/helpers/*.bash

# Smoke suites are selected by tag: any tests/*.bats file carrying a
# "# zz-test-tags: smoke" line is part of the pre-PR smoke gate.
mapfile -t smoke_suites < <(list_tagged_bats_suites smoke tests)
if [[ "${#smoke_suites[@]}" -eq 0 ]]; then
  printf 'Smoke gate found no suites tagged "smoke" under tests/. Refusing to pass an empty gate.\n' >&2
  exit 1
fi

run_bats_suites "${smoke_suites[@]}"

if [[ "${ZZ_TEST_LINT:-0}" -eq 1 ]]; then
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S error bootstrap.sh install.sh bin/zz bin/zz.d/* scripts/*.sh scripts/lib/*.sh lib/*.sh modules/*.sh tests/*.sh tests/helpers/*.bash
  else
    printf 'ZZ_TEST_LINT=1 was set, but shellcheck is not installed.\n' >&2
    exit 127
  fi
fi

printf 'smoke ok\n'
