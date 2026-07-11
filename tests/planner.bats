#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "planner fixture restores Bats debug tracing" {
  local debug_trap_before debug_trap_after shell_flags_before
  debug_trap_before="$(trap -p DEBUG)"
  shell_flags_before="$-"

  run_without_bats_debug_trap true

  fixture_failure() {
    printf 'fixture output\n'
    return 7
  }
  local captured_output captured_status
  capture_without_bats_debug_trap captured_output captured_status fixture_failure

  debug_trap_after="$(trap -p DEBUG)"
  assert_equal "$debug_trap_before" "$debug_trap_after"
  assert_equal "$shell_flags_before" "$-"
  assert_equal "fixture output" "$captured_output"
  assert_equal "7" "$captured_status"
}

@test "Fedora base plan includes protected base desktop bundles and rationale" {
  build_test_plan

  assert_plan_has "$PLAN_DIR/bundles.list" "base-source-rpmfusion-free"
  assert_plan_has "$PLAN_DIR/bundles.list" "base-source-rpmfusion-nonfree"
  assert_plan_has "$PLAN_DIR/bundles.list" "base-source-flathub"
  assert_plan_has "$PLAN_DIR/bundles.list" "base-source-cisco-openh264"
  assert_plan_has "$PLAN_DIR/sources/copr.list" "copr:lionheartp/Hyprland"
  assert_plan_has "$PLAN_DIR/sources/terra.list" "terra"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "ms-fonts"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "jetbrains-mono-nerd-font"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "noctalia-greeter"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "noctalia-v5"
  assert_plan_has "$PLAN_DIR/stow/packages.list" "noctalia"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "zsh"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "bats"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "nss-tools"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "nodejs24"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "nodejs24-npm"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "starship"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "yazi"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "ghostty-shell-integration"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "pavucontrol"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "system-config-printer"
  assert_plan_has "$PLAN_DIR/services/user-enable.list" "app-com.mitchellh.ghostty.service"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.local/bin/zz"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/autostart/zz-first-run.desktop"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/ghostty/themes/noctalia"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/noctalia/config.toml"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/noctalia/templates/icon-theme-accent"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.local/bin/noctalia-sync-icon-theme"
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'source\tcopr:lionheartp/Hyprland\tbase-login-manager'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'action\tnoctalia-greeter\tbase-login-manager\tdesktop-service\tgraphical login'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'source\tterra\tbase-ghostty'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tghostty-shell-integration\tbase-ghostty\tdefault-app\tterminal shell integration'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tbats\tbase-bootstrap\tinstaller-bootstrap'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tnss-tools\tbase-bootstrap\tinstaller-bootstrap\tbrowser certificate trust'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tnodejs24\tbase-nodejs'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tnodejs24-npm\tbase-nodejs'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tpavucontrol\tbase-desktop-controls\tdefault-app\taudio mixer'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tsystem-config-printer\tbase-desktop-controls\tdefault-app\tprint UI'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'action\tjetbrains-mono-nerd-font\tbase-jetbrains-mono-nerd-font'
}

@test "Fedora base plan does not include optional selections by default" {
  build_test_plan

  refute_plan_has "$PLAN_DIR/sources/vendor.list" "vendor:vscode"
  refute_plan_has "$PLAN_DIR/sources/vendor.list" "vendor:claude-desktop"
  refute_plan_has "$PLAN_DIR/sources/copr.list" "copr:dejan/lazygit"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "code"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "claude-desktop"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "lazygit"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "firefox"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "python3-pip"
  refute_plan_has "$PLAN_DIR/flatpak/apps.flatpaks" "com.discordapp.Discord"
  refute_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-sdk"
  refute_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-tools"
}

@test "full desktop app profile installs requested GNOME apps" {
  build_test_plan

  local package
  for package in \
    gnome-calendar \
    gnome-characters \
    gnome-clocks \
    gnome-system-monitor \
    gnome-logs \
    baobab \
    gnome-font-viewer \
    loupe \
    papers \
    showtime \
    decibels \
    snapshot \
    gnome-boxes \
    gnome-connections; do
    assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "$package"
  done
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "ghostty-nautilus"
}

@test "minimal desktop app profile keeps Niri baseline but skips full desktop app fill-ins" {
  DESKTOP_APP_PROFILE=minimal
  build_test_plan

  assert_plan_has "$PLAN_DIR/bundles.list" "base-desktop-niri"
  assert_plan_has "$PLAN_DIR/bundles.list" "base-noctalia"
  assert_plan_has "$PLAN_DIR/bundles.list" "base-ghostty"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "niri"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "noctalia-greeter"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "noctalia-v5"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "ghostty"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "ghostty-shell-integration"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "xdg-terminal-exec"

  refute_plan_has "$PLAN_DIR/bundles.list" "base-desktop-apps"
  refute_plan_has "$PLAN_DIR/bundles.list" "base-gtk-portals"
  refute_plan_has "$PLAN_DIR/bundles.list" "base-gtk-look"
  refute_plan_has "$PLAN_DIR/bundles.list" "base-desktop-controls"
  refute_plan_has "$PLAN_DIR/bundles.list" "base-file-integration-gtk"
  refute_plan_has "$PLAN_DIR/sources/rpmfusion.list" "rpmfusion-free"
  refute_plan_has "$PLAN_DIR/sources/flatpak-remotes.list" "flathub"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "nautilus"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "gnome-software"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "pavucontrol"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "system-config-printer"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "xdg-desktop-portal-gnome"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "qt6ct"
  refute_plan_has "$PLAN_DIR/flatpak/apps.flatpaks" "org.gtk.Gtk3theme.adw-gtk3"
  refute_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/xdg-desktop-portal/niri-portals.conf"
}

@test "auto desktop app profile uses minimal when an existing full desktop is detected" {
  DESKTOP_APP_PROFILE=auto
  existing_full_desktop_detected() {
    return 0
  }

  build_test_plan

  assert_file_contains "$PLAN_DIR/summary.txt" "Desktop app profile: minimal"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "niri"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "nautilus"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "pavucontrol"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "system-config-printer"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "xdg-desktop-portal-gnome"
}

@test "browser and development selections add their sources and packages" {
  build_test_plan "browser=brave,firefox" "dev=vscode,lazygit" "ai=codex"

  assert_plan_has "$PLAN_DIR/bundles.list" "browser-firefox"
  assert_plan_has "$PLAN_DIR/sources/vendor.list" "vendor:brave"
  assert_plan_has "$PLAN_DIR/sources/vendor.list" "vendor:vscode"
  assert_plan_has "$PLAN_DIR/sources/copr.list" "copr:dejan/lazygit"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "brave-browser"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "firefox"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "code"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "lazygit"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "npm-global:@openai/codex"
}

@test "Docker selection installs the engine and configures the user service" {
  build_test_plan "dev=docker"

  assert_plan_has "$PLAN_DIR/bundles.list" "dev-docker"
  assert_plan_has "$PLAN_DIR/bundles.list" "dev-docker-post"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "docker"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "docker-post-install"
}

@test "plan files stay unique after repeated overlapping selections" {
  build_test_plan "browser=zen-copr" "dev=vscode,neovim" "ai=codex,codex" "dotnet=tools"

  assert_unique_file "$PLAN_DIR/sources/flatpak-remotes.list"
  assert_unique_file "$PLAN_DIR/sources/vendor.list"
  assert_unique_file "$PLAN_DIR/packages/dnf.pkgs"
  assert_unique_file "$PLAN_DIR/actions/actions.list"
  assert_unique_file "$PLAN_DIR/services/system-enable-now.list"
  assert_unique_file "$PLAN_DIR/stow/packages.list"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.local/share/applications/nvim.desktop"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-sdk"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-tools"
}

@test "base manifests are always represented in the generated plan" {
  build_test_plan
  run_without_bats_debug_trap assert_base_manifests_in_plan
}
