#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-linux-setup-bootstrap.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

bootstrap_source="$(mktemp "$TEST_ROOT/bootstrap-source.XXXXXX")"
sed '$d' "$ROOT_DIR/bootstrap.sh" >"$bootstrap_source"

if command -v script >/dev/null 2>&1; then
  confirm_cmd="$(printf '%q' "source \"$bootstrap_source\"; ASSUME_YES=0; DRY_RUN=0; NO_TUI=1; bootstrap_confirm && exit 1 || exit 0")"
  confirm_output="$(printf 'n\n' | script -qfec "bash -lc $confirm_cmd" /dev/null 2>&1)"

  grep -F 'Continue with bootstrap? [y/N]' <<<"$confirm_output" >/dev/null
else
  printf 'bootstrap confirmation skipped (script command unavailable)\n'
fi

git -c init.defaultBranch=main init --bare "$TEST_ROOT/origin.git" >/dev/null
git -c init.defaultBranch=main init "$TEST_ROOT/source" >/dev/null
git -C "$TEST_ROOT/source" config user.email test@example.invalid
git -C "$TEST_ROOT/source" config user.name "Test User"
printf 'old\n' >"$TEST_ROOT/source/version.txt"
git -C "$TEST_ROOT/source" add version.txt
git -C "$TEST_ROOT/source" commit -m old >/dev/null
git -C "$TEST_ROOT/source" remote add origin "$TEST_ROOT/origin.git"
git -C "$TEST_ROOT/source" push -u origin main >/dev/null 2>&1

git clone "$TEST_ROOT/origin.git" "$TEST_ROOT/install" >/dev/null 2>&1
old_commit="$(git -C "$TEST_ROOT/install" rev-parse HEAD)"
printf 'new\n' >"$TEST_ROOT/source/version.txt"
git -C "$TEST_ROOT/source" commit -am new >/dev/null
git -C "$TEST_ROOT/source" push >/dev/null 2>&1
new_commit="$(git -C "$TEST_ROOT/source" rev-parse HEAD)"

source "$bootstrap_source"

REPO_URL="$TEST_ROOT/origin.git"
INSTALL_DIR="$TEST_ROOT/install"
REF=""
clone_or_update_repo

[[ "$(git -C "$TEST_ROOT/install" rev-parse HEAD)" == "$new_commit" ]]
[[ "$(cat "$TEST_ROOT/install/version.txt")" == "new" ]]
[[ "$(git -C "$TEST_ROOT/install" rev-parse HEAD)" != "$old_commit" ]]

git -C "$TEST_ROOT/source" switch -c desktop >/dev/null
printf 'desktop old\n' >"$TEST_ROOT/source/version.txt"
git -C "$TEST_ROOT/source" commit -am "desktop old" >/dev/null
git -C "$TEST_ROOT/source" push -u origin desktop >/dev/null 2>&1
git -C "$TEST_ROOT/install" fetch origin desktop >/dev/null 2>&1
git -C "$TEST_ROOT/install" switch -c desktop origin/desktop >/dev/null
desktop_old_commit="$(git -C "$TEST_ROOT/install" rev-parse HEAD)"
printf 'desktop new\n' >"$TEST_ROOT/source/version.txt"
git -C "$TEST_ROOT/source" commit -am "desktop new" >/dev/null
git -C "$TEST_ROOT/source" push >/dev/null 2>&1
desktop_new_commit="$(git -C "$TEST_ROOT/source" rev-parse HEAD)"

REF=""
clone_or_update_repo
[[ "$(git -C "$TEST_ROOT/install" branch --show-current)" == "desktop" ]]
[[ "$(git -C "$TEST_ROOT/install" rev-parse HEAD)" == "$desktop_new_commit" ]]
[[ "$(cat "$TEST_ROOT/install/version.txt")" == "desktop new" ]]
[[ "$(git -C "$TEST_ROOT/install" rev-parse HEAD)" != "$desktop_old_commit" ]]

REF="main"
clone_or_update_repo
[[ "$(git -C "$TEST_ROOT/install" branch --show-current)" == "main" ]]
[[ "$(git -C "$TEST_ROOT/install" rev-parse HEAD)" == "$new_commit" ]]

printf 'dirty\n' >"$TEST_ROOT/install/local.txt"
dirty_output="$(clone_or_update_repo 2>&1)" && {
  printf 'dirty clone update should fail\n' >&2
  exit 1
} || true
grep -F 'has uncommitted changes' <<<"$dirty_output" >/dev/null

printf 'bootstrap ok\n'
