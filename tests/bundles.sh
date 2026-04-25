#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-linux-setup-bundles.XXXXXX)"
trap 'rm -rf "$TEST_ROOT" "$ROOT_DIR/bundles/fedora/__test__" "$ROOT_DIR/packages/fedora/__test__"' EXIT

export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_CONFIG_HOME="$TEST_ROOT/config"

# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"

mkdir -p "$ROOT_DIR/bundles/fedora/__test__" "$ROOT_DIR/packages/fedora/__test__"
printf 'test-package\n' >"$ROOT_DIR/packages/fedora/__test__/valid.pkgs"

cat >"$ROOT_DIR/bundles/fedora/__test__/valid.bundle" <<'EOF'
BUNDLE_ID="test-valid"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_ID=""
BUNDLE_ITEMS_FILE="packages/fedora/__test__/valid.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Valid test bundle"
EOF

validate_bundle_descriptor fedora "$ROOT_DIR/bundles/fedora/__test__/valid.bundle"

cat >"$ROOT_DIR/bundles/fedora/__test__/missing-id.bundle" <<'EOF'
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_ID=""
BUNDLE_ITEMS_FILE="packages/fedora/__test__/valid.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Missing id"
EOF
! (validate_bundle_descriptor fedora "$ROOT_DIR/bundles/fedora/__test__/missing-id.bundle") >/dev/null 2>&1

cat >"$ROOT_DIR/bundles/fedora/__test__/bad-installer.bundle" <<'EOF'
BUNDLE_ID="test-bad-installer"
BUNDLE_INSTALLER="brew"
BUNDLE_SOURCE_ID=""
BUNDLE_ITEMS_FILE="packages/fedora/__test__/valid.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Bad installer"
EOF
! (validate_bundle_descriptor fedora "$ROOT_DIR/bundles/fedora/__test__/bad-installer.bundle") >/dev/null 2>&1

cat >"$ROOT_DIR/bundles/fedora/__test__/bad-source.bundle" <<'EOF'
BUNDLE_ID="test-bad-source"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_ID="missing-source"
BUNDLE_ITEMS_FILE="packages/fedora/__test__/valid.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Bad source"
EOF
! (validate_bundle_descriptor fedora "$ROOT_DIR/bundles/fedora/__test__/bad-source.bundle") >/dev/null 2>&1

cat >"$ROOT_DIR/bundles/fedora/__test__/missing-items.bundle" <<'EOF'
BUNDLE_ID="test-missing-items"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_ID=""
BUNDLE_ITEMS_FILE="packages/fedora/__test__/missing.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Missing items file"
EOF
! (validate_bundle_descriptor fedora "$ROOT_DIR/bundles/fedora/__test__/missing-items.bundle") >/dev/null 2>&1

printf 'bundles ok\n'
