#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v bats >/dev/null 2>&1; then
  printf 'bats is required to run hardening tests. On Fedora: sudo dnf install bats\n' >&2
  exit 127
fi

cd "$ROOT_DIR"
exec bats tests/doctor_hardening.bats tests/sources.bats tests/sources_flatpak.bats
