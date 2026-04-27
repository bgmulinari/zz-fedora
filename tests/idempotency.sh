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
# shellcheck source=../lib/stow.sh
source "$ROOT_DIR/lib/stow.sh"
# shellcheck source=../lib/planner.sh
source "$ROOT_DIR/lib/planner.sh"
# shellcheck source=../lib/os.sh
source "$ROOT_DIR/lib/os.sh"
# shellcheck source=../modules/80-post-actions.sh
source "$ROOT_DIR/modules/80-post-actions.sh"

DISTRO="fedora"
TARGET_USER="${USER}"
TARGET_HOME="${HOME}"
DRY_RUN=1
load_adapter
add_category_selection "browser" "firefox,firefox,zen-flatpak"
add_category_selection "dev" "base"
add_category_selection "shell" "starship,starship,yazi"
build_plan_from_selections

[[ "$(grep -Fc 'flathub' "$PLAN_DIR/sources/fedora-flatpak-remotes.list")" -eq 1 ]]
[[ "$(grep -Fc 'vendor:vscode' "$PLAN_DIR/sources/fedora-vendor.list")" -eq 1 ]]
[[ "$(grep -Fc 'firefox' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'python3-pip' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'code' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'starship' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'yazi' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'copr:atim/starship' "$PLAN_DIR/sources/fedora-copr.list")" -eq 1 ]]
[[ "$(grep -Fc 'copr:lihaohong/yazi' "$PLAN_DIR/sources/fedora-copr.list")" -eq 1 ]]
[[ "$(grep -Fc 'flatpak' "$PLAN_DIR/prereqs/dnf.pkgs")" -eq 1 ]]
[[ "$(sort -u "$PLAN_DIR/services/system-enable-now.list" | wc -l | tr -d ' ')" -eq "$(wc -l <"$PLAN_DIR/services/system-enable-now.list" | tr -d ' ')" ]]
[[ "$(sort -u "$PLAN_DIR/stow/packages.list" | wc -l | tr -d ' ')" -eq "$(wc -l <"$PLAN_DIR/stow/packages.list" | tr -d ' ')" ]]
[[ "$(grep -Fc 'app.zen_browser.zen' "$PLAN_DIR/flatpak/apps.flatpaks")" -eq 1 ]]
grep -Fx 'shell' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'nvim' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'noctalia' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'vscode' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'wallpapers' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'shell-starship' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'shell-yazi' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'sddm' "$PLAN_DIR/services/system-enable.list" >/dev/null
! grep -Fx 'zsh' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'nautilus' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'fontconfig' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'gnome-themes-extra' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'google-noto-sans-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'google-noto-sans-cjk-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'google-noto-color-emoji-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'fontawesome-6-free-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'yaru-icon-theme' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'sddm' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx '~/.config/niri/config.kdl' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/niri/noctalia.kdl' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/nvim/plugin/noctalia.lua' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/plugins.json' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/settings.json' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/user-templates.toml' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/templates/starship.toml' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/templates/zsh-syntax-highlighting.zsh' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/Code/User/settings.json' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.local/share/wallpapers/SilentPeaks.jpg' "$PLAN_DIR/files/managed-files.list" >/dev/null

settings_home="$TEST_ROOT/settings-home"
mkdir -p "$settings_home/.config/noctalia"
printf '{}\n' >"$settings_home/.config/noctalia/settings.json"
TARGET_HOME="$settings_home"
DRY_RUN=0
update_noctalia_settings
grep -F '"id": "kitty"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "pywalfox"' "$settings_home/.config/noctalia/settings.json" >/dev/null
DRY_RUN=1
TARGET_HOME="${HOME}"

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

fake_home="$TEST_ROOT/home"
mkdir -p "$fake_home"
TARGET_HOME="$fake_home"
printf 'existing bashrc\n' >"$TARGET_HOME/.bashrc"
stow_prepare_known_shell_files
[[ ! -e "$TARGET_HOME/.bashrc" ]]
find "$STATE_DIR/backups" -path '*/home/.bashrc' -type f -print -quit | grep -q .

mkdir -p "$TARGET_HOME/.config/niri" "$TARGET_HOME/.config/noctalia"
printf 'binds {}\n' >"$TARGET_HOME/.config/niri/config.kdl"
printf '{}\n' >"$TARGET_HOME/.config/noctalia/settings.json"
stow_prepare_known_conflicts niri noctalia
[[ ! -e "$TARGET_HOME/.config/niri" ]]
[[ ! -e "$TARGET_HOME/.config/noctalia" ]]
find "$STATE_DIR/backups" -path '*/home/.config/niri/config.kdl' -type f -print -quit | grep -q .
find "$STATE_DIR/backups" -path '*/home/.config/noctalia/settings.json' -type f -print -quit | grep -q .

printf 'idempotency ok\n'
