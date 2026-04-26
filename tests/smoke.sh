#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n bootstrap.sh
bash -n install.sh
bash -n lib/*.sh
bash -n distros/*.sh
bash -n modules/*.sh

tests/manifest-parse.sh
tests/bundles.sh
tests/bootstrap.sh
tests/distro-detect.sh
tests/planner.sh
tests/idempotency.sh

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck bootstrap.sh install.sh lib/*.sh distros/*.sh modules/*.sh tests/*.sh
fi

printf 'smoke ok\n'
