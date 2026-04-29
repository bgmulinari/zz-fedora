#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-linux-setup-bootstrap.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

bootstrap_source="$(mktemp "$TEST_ROOT/bootstrap-source.XXXXXX")"
sed '$d' "$ROOT_DIR/bootstrap.sh" >"$bootstrap_source"

if ! command -v script >/dev/null 2>&1; then
  printf 'bootstrap skipped (script command unavailable)\n'
  exit 0
fi

confirm_cmd="$(printf '%q' "source \"$bootstrap_source\"; ASSUME_YES=0; DRY_RUN=0; NO_TUI=1; bootstrap_confirm && exit 1 || exit 0")"
confirm_output="$(printf 'n\n' | script -qfec "bash -lc $confirm_cmd" /dev/null 2>&1)"

grep -F 'Continue with bootstrap? [y/N]' <<<"$confirm_output" >/dev/null

printf 'bootstrap ok\n'
