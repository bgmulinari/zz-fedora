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
  bash "$ROOT_DIR/install.sh" install "$@" --dry-run 2>&1
}

fedora_browsers="$(run_case fedora-browsers print-plan --distro fedora --select browser=firefox,brave --dry-run)"
grep -F 'vendor:brave' <<<"$fedora_browsers" >/dev/null
grep -F 'python3-pip' <<<"$fedora_browsers" >/dev/null
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

fedora_dev_base="$(run_case fedora-dev-base print-plan --distro fedora --select dev=base --dry-run)"
grep -F 'vendor:vscode' <<<"$fedora_dev_base" >/dev/null
grep -F 'code' <<<"$fedora_dev_base" >/dev/null
grep -F '  - vscode' <<<"$fedora_dev_base" >/dev/null

arch_zen="$(run_case arch-zen print-plan --distro arch --select browser=zen-flatpak --dry-run)"
grep -F 'flathub' <<<"$arch_zen" >/dev/null
! grep -F 'arch-aur.list' <<<"$arch_zen" >/dev/null

arch_base="$(run_case arch-base print-plan --distro arch --dry-run)"
grep -F 'arch-aur.list' <<<"$arch_base" >/dev/null
grep -F 'noctalia-shell' <<<"$arch_base" >/dev/null
grep -F 'kitty' <<<"$arch_base" >/dev/null
grep -F 'sddm' <<<"$arch_base" >/dev/null
grep -F 'nautilus' <<<"$arch_base" >/dev/null
grep -F 'fontconfig' <<<"$arch_base" >/dev/null
grep -F 'gnome-themes-extra' <<<"$arch_base" >/dev/null
grep -F 'noto-fonts' <<<"$arch_base" >/dev/null
grep -F 'noto-fonts-cjk' <<<"$arch_base" >/dev/null
grep -F 'noto-fonts-emoji' <<<"$arch_base" >/dev/null
grep -F 'ttf-jetbrains-mono-nerd' <<<"$arch_base" >/dev/null
grep -F 'woff2-font-awesome' <<<"$arch_base" >/dev/null
grep -F 'yaru-icon-theme' <<<"$arch_base" >/dev/null
grep -F 'python-pywalfox' <<<"$arch_base" >/dev/null
grep -F '  - nvim' <<<"$arch_base" >/dev/null
grep -F '  - niri' <<<"$arch_base" >/dev/null
grep -F '  - noctalia' <<<"$arch_base" >/dev/null
grep -F '  - wallpapers' <<<"$arch_base" >/dev/null
grep -F '~/.config/nvim/plugin/noctalia.lua' <<<"$arch_base" >/dev/null
grep -F '~/.config/niri/config.kdl' <<<"$arch_base" >/dev/null
grep -F '~/.config/niri/noctalia.kdl' <<<"$arch_base" >/dev/null
grep -F '~/.config/noctalia/plugins.json' <<<"$arch_base" >/dev/null
grep -F '~/.config/noctalia/settings.json' <<<"$arch_base" >/dev/null
grep -F '~/.config/noctalia/user-templates.toml' <<<"$arch_base" >/dev/null
grep -F '~/.config/noctalia/templates/starship.toml' <<<"$arch_base" >/dev/null
grep -F '~/.config/noctalia/templates/zsh-syntax-highlighting.zsh' <<<"$arch_base" >/dev/null
grep -F '~/.local/share/wallpapers/SilentPeaks.jpg' <<<"$arch_base" >/dev/null

arch_shell="$(run_case arch-shell print-plan --distro arch --select shell=gh,fd,yazi --dry-run)"
grep -F 'github-cli' <<<"$arch_shell" >/dev/null
grep -F $'  - fd' <<<"$arch_shell" >/dev/null
grep -F 'yazi' <<<"$arch_shell" >/dev/null
! grep -F 'arch-flatpak-remotes.list' <<<"$arch_shell" >/dev/null

arch_dev_base="$(run_case arch-dev-base print-plan --distro arch --select dev=base --dry-run)"
grep -F 'arch-aur.list' <<<"$arch_dev_base" >/dev/null
grep -F 'visual-studio-code-bin' <<<"$arch_dev_base" >/dev/null
! grep -F $'\n  - code\n' <<<"$arch_dev_base" >/dev/null
grep -F '  - vscode' <<<"$arch_dev_base" >/dev/null

fedora_base="$(run_case fedora-base print-plan --distro fedora --dry-run)"
grep -F 'copr:yalter/niri' <<<"$fedora_base" >/dev/null
grep -F 'kitty' <<<"$fedora_base" >/dev/null
grep -F 'sddm' <<<"$fedora_base" >/dev/null
grep -F 'nautilus' <<<"$fedora_base" >/dev/null
grep -F 'firefox' <<<"$fedora_base" >/dev/null
grep -F 'python3-pip' <<<"$fedora_base" >/dev/null
grep -F 'fontconfig' <<<"$fedora_base" >/dev/null
grep -F 'gnome-themes-extra' <<<"$fedora_base" >/dev/null
grep -F 'google-noto-sans-fonts' <<<"$fedora_base" >/dev/null
grep -F 'google-noto-sans-cjk-fonts' <<<"$fedora_base" >/dev/null
grep -F 'google-noto-color-emoji-fonts' <<<"$fedora_base" >/dev/null
grep -F 'fontawesome-6-free-fonts' <<<"$fedora_base" >/dev/null
grep -F 'yaru-icon-theme' <<<"$fedora_base" >/dev/null
grep -F '  - nvim' <<<"$fedora_base" >/dev/null
grep -F '  - niri' <<<"$fedora_base" >/dev/null
grep -F '  - noctalia' <<<"$fedora_base" >/dev/null
grep -F '  - wallpapers' <<<"$fedora_base" >/dev/null
grep -F '~/.config/nvim/plugin/noctalia.lua' <<<"$fedora_base" >/dev/null
grep -F '~/.config/niri/config.kdl' <<<"$fedora_base" >/dev/null
grep -F '~/.config/niri/noctalia.kdl' <<<"$fedora_base" >/dev/null
grep -F '~/.config/noctalia/plugins.json' <<<"$fedora_base" >/dev/null
grep -F '~/.config/noctalia/settings.json' <<<"$fedora_base" >/dev/null
grep -F '~/.config/noctalia/user-templates.toml' <<<"$fedora_base" >/dev/null
grep -F '~/.config/noctalia/templates/starship.toml' <<<"$fedora_base" >/dev/null
grep -F '~/.config/noctalia/templates/zsh-syntax-highlighting.zsh' <<<"$fedora_base" >/dev/null
grep -F '~/.local/share/wallpapers/SilentPeaks.jpg' <<<"$fedora_base" >/dev/null
! grep -F 'alacritty' <<<"$fedora_base" >/dev/null

fedora_install="$(run_install_case fedora-login-manager --distro fedora)"
grep -F '==> [1/12] Preflight' <<<"$fedora_install" >/dev/null
grep -F '==> [12/12] Doctor' <<<"$fedora_install" >/dev/null
grep -F 'sudo systemctl enable --force sddm.service' <<<"$fedora_install" >/dev/null
! grep -F 'Reboot now?' <<<"$fedora_install" >/dev/null

fedora_skip_login_manager="$(run_install_case fedora-skip-login-manager --distro fedora --skip-login-manager)"
! grep -F 'sudo systemctl enable --force sddm.service' <<<"$fedora_skip_login_manager" >/dev/null

fedora_flatpak_install="$(run_install_case fedora-flatpak-order --distro fedora --select browser=zen-flatpak)"
bootstrap_line="$(grep -n 'sudo dnf install -y --setopt=install_weak_deps=False flatpak' <<<"$fedora_flatpak_install" | head -n1 | cut -d: -f1)"
source_line="$(grep -n 'flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo' <<<"$fedora_flatpak_install" | head -n1 | cut -d: -f1)"
install_line="$(grep -n 'flatpak install -y --or-update flathub app.zen_browser.zen' <<<"$fedora_flatpak_install" | head -n1 | cut -d: -f1)"
[[ -n "$bootstrap_line" && -n "$source_line" && -n "$install_line" ]]
[[ "$bootstrap_line" -lt "$source_line" ]]
[[ "$source_line" -lt "$install_line" ]]

fedora_firefox_install="$(run_install_case fedora-firefox-pywalfox --distro fedora --select browser=firefox)"
grep -F 'sudo python3 -m pip install --upgrade pywalfox' <<<"$fedora_firefox_install" >/dev/null
grep -F 'sudo -u deb pywalfox install' <<<"$fedora_firefox_install" >/dev/null

empty_selection_case="$(run_case empty-selection-guard print-plan --distro fedora --select dev= --dry-run)"
grep -F 'Distro: fedora' <<<"$empty_selection_case" >/dev/null

printf 'planner ok\n'
