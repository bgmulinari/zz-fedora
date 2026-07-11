#!/usr/bin/env bash
set -Eeuo pipefail

TEST_ROOT="$(mktemp -d /tmp/zz-fedora-platform.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_CONFIG_HOME="$TEST_ROOT/config"

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/fedora.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/fedora.sh"

fedora_file="$TEST_ROOT/fedora-os-release"
printf 'ID=fedora\n' >"$fedora_file"

fedora_release_file_is_supported "$fedora_file"

printf 'Fedora platform check ok\n'
