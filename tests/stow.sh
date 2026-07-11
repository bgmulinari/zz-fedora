#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-fedora-stow.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

grep -F -- '--no-folding' "$ROOT_DIR/lib/stow.sh" >/dev/null

stow_dir="$TEST_ROOT/dotfiles"
target_home="$TEST_ROOT/home"
mkdir -p \
  "$stow_dir/sample/.config/Code/User" \
  "$stow_dir/sample/.local/share/wallpapers" \
  "$target_home"

printf '{}\n' >"$stow_dir/sample/.config/Code/User/settings.json"
printf 'image\n' >"$stow_dir/sample/.local/share/wallpapers/SilentPeaks.jpg"

stow --dir "$stow_dir" --target "$target_home" --no-folding sample

[[ -d "$target_home/.config" ]]
[[ ! -L "$target_home/.config" ]]
[[ -d "$target_home/.config/Code" ]]
[[ ! -L "$target_home/.config/Code" ]]
[[ -L "$target_home/.config/Code/User/settings.json" ]]

[[ -d "$target_home/.local" ]]
[[ ! -L "$target_home/.local" ]]
[[ -d "$target_home/.local/share" ]]
[[ ! -L "$target_home/.local/share" ]]
[[ -L "$target_home/.local/share/wallpapers/SilentPeaks.jpg" ]]

printf 'stow ok\n'
