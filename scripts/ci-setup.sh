#!/usr/bin/env bash
set -Eeuo pipefail

# Prepare a fresh Fedora container for the CI test run:
# - install the test dependencies listed in scripts/ci-packages.txt
# - create an unprivileged runner user that owns the checkout
# - make the checkout a usable Git work tree for that user
#
# Run as root from any directory inside a fedora:44 container, locally or in CI:
#   bash scripts/ci-setup.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_USER="${ZZ_CI_USER:-zzci}"

mapfile -t packages < <(grep -Ev '^[[:space:]]*(#|$)' "$ROOT_DIR/scripts/ci-packages.txt")
if [[ "${#packages[@]}" -eq 0 ]]; then
  printf 'scripts/ci-packages.txt lists no packages.\n' >&2
  exit 1
fi
dnf install -y "${packages[@]}"

if ! id -u "$CI_USER" >/dev/null 2>&1; then
  useradd --create-home "$CI_USER"
fi
chown -R "$CI_USER:$CI_USER" "$ROOT_DIR"

ci_run() {
  runuser -u "$CI_USER" -- env HOME="/home/$CI_USER" USER="$CI_USER" "$@"
}

ci_run git config --global --add safe.directory "$ROOT_DIR"
# Container jobs can receive the checked-out files without the host-side Git metadata.
if ! ci_run git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ci_run git -C "$ROOT_DIR" init -q
  ci_run git -C "$ROOT_DIR" add --intent-to-add .
fi
ci_run git -C "$ROOT_DIR" rev-parse --is-inside-work-tree
