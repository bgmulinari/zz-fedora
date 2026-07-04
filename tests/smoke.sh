#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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
bash -n lib/*.sh
bash -n distros/*.sh
bash -n modules/*.sh
bash -n tests/*.sh
bash -n tests/helpers/*.bash

bats \
  tests/manifest_catalog.bats \
  tests/starship_theme.bats \
  tests/cli_smoke.bats

if [[ "${ZZ_TEST_LINT:-0}" -eq 1 ]]; then
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S error bootstrap.sh install.sh bin/zz bin/zz.d/* lib/*.sh distros/*.sh modules/*.sh tests/*.sh tests/helpers/*.bash
  else
    printf 'ZZ_TEST_LINT=1 was set, but shellcheck is not installed.\n' >&2
    exit 127
  fi
fi

printf 'smoke ok\n'
