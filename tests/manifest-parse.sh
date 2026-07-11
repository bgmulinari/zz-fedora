#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d /tmp/zz-fedora-manifest.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_CONFIG_HOME="$TEST_ROOT/config"

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

manifest="$TEST_ROOT/test.pkgs"
printf '%s\n' \
  '# comment' \
  'ghostty' \
  '' \
  'firefox   # inline comment' \
  'ghostty' \
  '  chromium  ' \
  >"$manifest"

expected=$'chromium\nfirefox\nghostty'
actual="$(manifest_entries "$manifest")"

[[ "$actual" == "$expected" ]] || {
  printf 'manifest_entries output mismatch\nExpected:\n%s\nActual:\n%s\n' "$expected" "$actual" >&2
  exit 1
}

printf 'manifest parser ok\n'
