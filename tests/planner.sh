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

assert_contains() {
  local haystack="$1"
  local needle="$2"
  grep -F "$needle" <<<"$haystack" >/dev/null
}

fedora_base="$(run_case fedora-base print-plan --distro fedora --dry-run)"
assert_contains "$fedora_base" 'base-source-rpmfusion-free'
assert_contains "$fedora_base" 'base-source-rpmfusion-nonfree'
assert_contains "$fedora_base" 'base-source-cisco-openh264'
assert_contains "$fedora_base" 'base-source-flathub'
assert_contains "$fedora_base" 'terra'
assert_contains "$fedora_base" 'vendor:vscode'
assert_contains "$fedora_base" 'vendor:claude-desktop'
assert_contains "$fedora_base" 'copr:dejan/lazygit'
assert_contains "$fedora_base" 'code'
assert_contains "$fedora_base" 'claude-desktop'
assert_contains "$fedora_base" 'lazygit'
assert_contains "$fedora_base" 'steam'
assert_contains "$fedora_base" 'com.discordapp.Discord'
assert_contains "$fedora_base" 'net.davidotek.pupgui2'
assert_contains "$fedora_base" 'org.onlyoffice.desktopeditors'
assert_contains "$fedora_base" 'com.github.IsmaelMartinez.teams_for_linux'
assert_contains "$fedora_base" 'us.zoom.Zoom'
assert_contains "$fedora_base" 'com.spotify.Client'
assert_contains "$fedora_base" 'brew:codex'
assert_contains "$fedora_base" 'brew:opencode'
assert_contains "$fedora_base" 'brew:lazydocker'
assert_contains "$fedora_base" 'claude-code'
assert_contains "$fedora_base" 'jetbrains-toolbox'
assert_contains "$fedora_base" 'devtunnel'
assert_contains "$fedora_base" 'docker-fedora'
assert_contains "$fedora_base" 'dotnet-sdk'
assert_contains "$fedora_base" 'dotnet-tools'
assert_contains "$fedora_base" 'media-codecs-fedora'
assert_contains "$fedora_base" 'ms-fonts-fedora'
assert_contains "$fedora_base" 'build-tools-fedora'
assert_contains "$fedora_base" 'zsh'
assert_contains "$fedora_base" 'starship'
assert_contains "$fedora_base" 'zoxide'
assert_contains "$fedora_base" 'fastfetch'
assert_contains "$fedora_base" 'gh'
assert_contains "$fedora_base" 'btop'
assert_contains "$fedora_base" 'fd-find'
assert_contains "$fedora_base" 'fzf'
assert_contains "$fedora_base" 'bat'
assert_contains "$fedora_base" 'yazi'

fedora_helium="$(run_case fedora-helium print-plan --distro fedora --select browser=helium-copr --dry-run)"
assert_contains "$fedora_helium" 'copr:imput/helium'
assert_contains "$fedora_helium" 'helium-bin'

fedora_chrome="$(run_case fedora-chrome print-plan --distro fedora --select browser=chrome --dry-run)"
assert_contains "$fedora_chrome" 'vendor:google-chrome'
assert_contains "$fedora_chrome" 'google-chrome-stable'

fedora_brave="$(run_case fedora-brave print-plan --distro fedora --select browser=brave --dry-run)"
assert_contains "$fedora_brave" 'vendor:brave'
assert_contains "$fedora_brave" 'brave-browser'

fedora_dotnet_tools="$(run_case fedora-dotnet-tools print-plan --distro fedora --select dotnet=tools --dry-run)"
assert_contains "$fedora_dotnet_tools" 'dotnet-sdk'
assert_contains "$fedora_dotnet_tools" 'dotnet-tools'

arch_base="$(run_case arch-base print-plan --distro arch --dry-run)"
assert_contains "$arch_base" 'base-devel'
assert_contains "$arch_base" 'ttf-ms-fonts'
assert_contains "$arch_base" 'claude-desktop-appimage'
assert_contains "$arch_base" 'visual-studio-code-bin'
assert_contains "$arch_base" 'docker'
assert_contains "$arch_base" 'docker-buildx'
assert_contains "$arch_base" 'docker-compose'
assert_contains "$arch_base" 'docker-arch'
assert_contains "$arch_base" 'steam'
assert_contains "$arch_base" 'net.davidotek.pupgui2'
assert_contains "$arch_base" 'com.discordapp.Discord'
assert_contains "$arch_base" 'ffmpeg'
assert_contains "$arch_base" 'gst-plugins-good'

arch_helium="$(run_case arch-helium print-plan --distro arch --select browser=helium-aur --dry-run)"
assert_contains "$arch_helium" 'helium-bin-browser'

fedora_install="$(run_install_case fedora-install --distro fedora)"
assert_contains "$fedora_install" '==> [1/9] Preflight'
assert_contains "$fedora_install" '==> [4/9] Base Setup'
assert_contains "$fedora_install" '==> [5/9] Optional Packages'
assert_contains "$fedora_install" '==> [6/9] Custom Actions'
assert_contains "$fedora_install" '==> [9/9] Doctor'
assert_contains "$fedora_install" 'sudo dnf group install -y development-tools'
assert_contains "$fedora_install" 'DRY-RUN: brew install codex'
assert_contains "$fedora_install" 'DRY-RUN: install active .NET SDK channels'
assert_contains "$fedora_install" 'sudo systemctl daemon-reload'
assert_contains "$fedora_install" 'sudo systemctl set-default graphical.target'
assert_contains "$fedora_install" 'sudo systemctl enable --force sddm.service'

printf 'planner ok\n'
