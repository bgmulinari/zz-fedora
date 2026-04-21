#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-linux-setup-idempotency.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_CONFIG_HOME="$TEST_ROOT/config"

# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=../lib/idempotency.sh
source "$ROOT_DIR/lib/idempotency.sh"
# shellcheck source=../lib/packages.sh
source "$ROOT_DIR/lib/packages.sh"
# shellcheck source=../lib/sources.sh
source "$ROOT_DIR/lib/sources.sh"
# shellcheck source=../lib/files.sh
source "$ROOT_DIR/lib/files.sh"
# shellcheck source=../lib/planner.sh
source "$ROOT_DIR/lib/planner.sh"
# shellcheck source=../lib/os.sh
source "$ROOT_DIR/lib/os.sh"

DISTRO="fedora"
TARGET_USER="${USER}"
TARGET_HOME="${HOME}"
DRY_RUN=1
load_adapter
add_category_selection "browser" "firefox,firefox,zen-flatpak"
add_category_selection "shell" "starship,starship,yazi"
append_unique EXPLICIT_ENABLED_SOURCES "flathub"
append_unique EXPLICIT_ENABLED_SOURCES "flathub"
build_plan_from_selections

[[ "$(grep -Fc 'flathub' "$PLAN_DIR/sources/fedora-flatpak-remotes.list")" -eq 1 ]]
[[ "$(grep -Fc 'firefox' "$PLAN_DIR/packages/official.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'starship' "$PLAN_DIR/packages/copr.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'yazi' "$PLAN_DIR/packages/copr.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'copr:atim/starship' "$PLAN_DIR/sources/fedora-copr.list")" -eq 1 ]]
[[ "$(grep -Fc 'copr:lihaohong/yazi' "$PLAN_DIR/sources/fedora-copr.list")" -eq 1 ]]
[[ "$(sort -u "$PLAN_DIR/services/system-enable-now.list" | wc -l | tr -d ' ')" -eq "$(wc -l <"$PLAN_DIR/services/system-enable-now.list" | tr -d ' ')" ]]
[[ "$(sort -u "$PLAN_DIR/stow/packages.list" | wc -l | tr -d ' ')" -eq "$(wc -l <"$PLAN_DIR/stow/packages.list" | tr -d ' ')" ]]
[[ "$(grep -Fc 'app.zen_browser.zen' "$PLAN_DIR/flatpak/apps.flatpaks")" -eq 1 ]]
grep -Fx 'shell' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'noctalia' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'shell-starship' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'shell-yazi' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'plasmalogin' "$PLAN_DIR/services/system-enable.list" >/dev/null
! grep -Fx 'zsh' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'qt5ct' "$PLAN_DIR/packages/official.pkgs" >/dev/null
grep -Fx 'plasma-login-manager' "$PLAN_DIR/packages/official.pkgs" >/dev/null
grep -Fx 'kcm-plasmalogin' "$PLAN_DIR/packages/official.pkgs" >/dev/null
grep -Fx '~/.config/noctalia/settings.json' "$PLAN_DIR/files/managed-files.list" >/dev/null
! grep -Fx '/etc/greetd/config.toml' "$PLAN_DIR/files/managed-files.list" >/dev/null

touch_target="$TEST_ROOT/should-not-exist"
run_cmd touch "$touch_target"
[[ ! -e "$touch_target" ]]

source_file="$TEST_ROOT/source.conf"
dest_file="$TEST_ROOT/dest.conf"
printf 'alpha\n' >"$source_file"
DRY_RUN=0
file_install_if_changed "$source_file" "$dest_file"
checksum_before="$(sha256sum "$dest_file" | awk '{print $1}')"
file_install_if_changed "$source_file" "$dest_file"
checksum_after="$(sha256sum "$dest_file" | awk '{print $1}')"
[[ "$checksum_before" == "$checksum_after" ]]

printf 'idempotency ok\n'
