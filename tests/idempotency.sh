#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v bats >/dev/null 2>&1; then
  printf 'bats is required to run idempotency tests. On Fedora: sudo dnf install bats\n' >&2
  exit 127
fi

cd "$ROOT_DIR"
exec bats tests/package_modules.bats tests/sources.bats tests/sources_flatpak.bats tests/post_actions.bats
