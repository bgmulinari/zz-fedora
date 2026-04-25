#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_case() {
  local name="$1"
  shift
  local test_root
  test_root="$(mktemp -d "/tmp/zz-linux-setup-${name}.XXXXXX")"
  XDG_STATE_HOME="$test_root/state" \
  XDG_CACHE_HOME="$test_root/cache" \
  XDG_CONFIG_HOME="$test_root/config" \
  bash "$ROOT_DIR/install.sh" "$@"
}

run_install_case() {
  local name="$1"
  shift
  local test_root
  test_root="$(mktemp -d "/tmp/zz-linux-setup-install-${name}.XXXXXX")"
  XDG_STATE_HOME="$test_root/state" \
  XDG_CACHE_HOME="$test_root/cache" \
  XDG_CONFIG_HOME="$test_root/config" \
  bash "$ROOT_DIR/install.sh" install "$@" --dry-run
}

fedora_browsers="$(run_case fedora-browsers print-plan --distro fedora --select browser=firefox,brave --dry-run)"
grep -F 'vendor:brave' <<<"$fedora_browsers" >/dev/null
! grep -F 'vendor:google-chrome' <<<"$fedora_browsers" >/dev/null

fedora_chrome="$(run_case fedora-chrome print-plan --distro fedora --select browser=chrome --dry-run)"
grep -F 'vendor:google-chrome' <<<"$fedora_chrome" >/dev/null

fedora_zen="$(run_case fedora-zen print-plan --distro fedora --select browser=zen-flatpak --dry-run)"
grep -F 'flathub' <<<"$fedora_zen" >/dev/null
! grep -F 'vendor:brave' <<<"$fedora_zen" >/dev/null

fedora_steam="$(run_case fedora-steam print-plan --distro fedora --select gaming=steam --dry-run)"
grep -F 'rpmfusion-free' <<<"$fedora_steam" >/dev/null
grep -F 'rpmfusion-nonfree' <<<"$fedora_steam" >/dev/null
grep -F 'steam' <<<"$fedora_steam" >/dev/null

fedora_codecs="$(run_case fedora-codecs print-plan --distro fedora --select media=codecs --dry-run)"
grep -F 'rpmfusion-free' <<<"$fedora_codecs" >/dev/null
grep -F 'rpmfusion-nonfree' <<<"$fedora_codecs" >/dev/null
grep -F 'gstreamer1-plugins-bad-freeworld' <<<"$fedora_codecs" >/dev/null
! grep -F 'vendor:brave' <<<"$fedora_codecs" >/dev/null

fedora_starship="$(run_case fedora-starship print-plan --distro fedora --select shell=starship --dry-run)"
grep -F 'copr:atim/starship' <<<"$fedora_starship" >/dev/null
! grep -F 'copr:lihaohong/yazi' <<<"$fedora_starship" >/dev/null

fedora_yazi="$(run_case fedora-yazi print-plan --distro fedora --select shell=yazi --dry-run)"
grep -F 'copr:lihaohong/yazi' <<<"$fedora_yazi" >/dev/null
! grep -F 'copr:atim/starship' <<<"$fedora_yazi" >/dev/null

fedora_shell_core="$(run_case fedora-shell-core print-plan --distro fedora --select shell=zsh,fastfetch,gh --dry-run)"
grep -F 'zsh' <<<"$fedora_shell_core" >/dev/null
grep -F 'fastfetch' <<<"$fedora_shell_core" >/dev/null
grep -F 'gh' <<<"$fedora_shell_core" >/dev/null
! grep -F 'copr:atim/starship' <<<"$fedora_shell_core" >/dev/null
! grep -F 'copr:lihaohong/yazi' <<<"$fedora_shell_core" >/dev/null

arch_zen="$(run_case arch-zen print-plan --distro arch --select browser=zen-flatpak --dry-run)"
grep -F 'flathub' <<<"$arch_zen" >/dev/null
! grep -F 'arch-aur.list' <<<"$arch_zen" >/dev/null

arch_base="$(run_case arch-base print-plan --distro arch --dry-run)"
grep -F 'arch-aur.list' <<<"$arch_base" >/dev/null
grep -F 'noctalia-shell' <<<"$arch_base" >/dev/null
grep -F 'ghostty' <<<"$arch_base" >/dev/null
grep -F 'plasma-login-manager' <<<"$arch_base" >/dev/null
grep -F 'plasmalogin' <<<"$arch_base" >/dev/null
grep -F 'qt5ct' <<<"$arch_base" >/dev/null
grep -F '  - noctalia' <<<"$arch_base" >/dev/null
grep -F '~/.config/noctalia/settings.json' <<<"$arch_base" >/dev/null
! grep -F 'greetd' <<<"$arch_base" >/dev/null

arch_shell="$(run_case arch-shell print-plan --distro arch --select shell=gh,fd,yazi --dry-run)"
grep -F 'github-cli' <<<"$arch_shell" >/dev/null
grep -F $'  - fd' <<<"$arch_shell" >/dev/null
grep -F 'yazi' <<<"$arch_shell" >/dev/null
! grep -F 'arch-flatpak-remotes.list' <<<"$arch_shell" >/dev/null

fedora_base="$(run_case fedora-base print-plan --distro fedora --dry-run)"
grep -F 'copr:yalter/niri' <<<"$fedora_base" >/dev/null
grep -F 'ghostty' <<<"$fedora_base" >/dev/null
grep -F 'plasma-login-manager' <<<"$fedora_base" >/dev/null
grep -F 'kcm-plasmalogin' <<<"$fedora_base" >/dev/null
grep -F 'plasmalogin' <<<"$fedora_base" >/dev/null
grep -F 'qt5ct' <<<"$fedora_base" >/dev/null
grep -F '  - noctalia' <<<"$fedora_base" >/dev/null
grep -F '~/.config/noctalia/settings.json' <<<"$fedora_base" >/dev/null
! grep -F 'alacritty' <<<"$fedora_base" >/dev/null
! grep -F 'greetd' <<<"$fedora_base" >/dev/null

fedora_install="$(run_install_case fedora-login-manager --distro fedora)"
grep -F 'sudo systemctl enable --force plasmalogin.service' <<<"$fedora_install" >/dev/null

fedora_skip_login_manager="$(run_install_case fedora-skip-login-manager --distro fedora --skip-login-manager)"
! grep -F 'sudo systemctl enable --force plasmalogin.service' <<<"$fedora_skip_login_manager" >/dev/null

fedora_flatpak_install="$(run_install_case fedora-flatpak-order --distro fedora --select browser=zen-flatpak)"
bootstrap_line="$(grep -n 'sudo dnf install -y --setopt=install_weak_deps=False flatpak' <<<"$fedora_flatpak_install" | head -n1 | cut -d: -f1)"
source_line="$(grep -n 'flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' <<<"$fedora_flatpak_install" | head -n1 | cut -d: -f1)"
install_line="$(grep -n 'flatpak install -y --or-update flathub app.zen_browser.zen' <<<"$fedora_flatpak_install" | head -n1 | cut -d: -f1)"
[[ -n "$bootstrap_line" && -n "$source_line" && -n "$install_line" ]]
[[ "$bootstrap_line" -lt "$source_line" ]]
[[ "$source_line" -lt "$install_line" ]]

empty_selection_case="$(run_case empty-selection-guard print-plan --distro fedora --select dev= --dry-run)"
grep -F 'Distro: fedora' <<<"$empty_selection_case" >/dev/null

printf 'planner ok\n'
