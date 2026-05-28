#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "Fedora base plan includes protected base desktop bundles and rationale" {
  build_fedora_plan

  assert_plan_has "$PLAN_DIR/bundles.list" "base-source-rpmfusion-free"
  assert_plan_has "$PLAN_DIR/bundles.list" "base-source-rpmfusion-nonfree"
  assert_plan_has "$PLAN_DIR/bundles.list" "base-source-flathub"
  assert_plan_has "$PLAN_DIR/bundles.list" "base-source-cisco-openh264"
  assert_plan_has "$PLAN_DIR/sources/fedora-terra.list" "terra"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "ms-fonts-fedora"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "jetbrains-mono-nerd-font-fedora"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "zsh"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "bats"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "nodejs24"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "nodejs24-npm"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "starship"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "yazi"
  assert_plan_has "$PLAN_DIR/services/user-enable.list" "app-com.mitchellh.ghostty.service"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.local/bin/zz"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/autostart/zz-first-run.desktop"
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'source\tterra\tbase-noctalia'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tbats\tbase-bootstrap\tinstaller-bootstrap'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tnodejs24\tbase-nodejs'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tnodejs24-npm\tbase-nodejs'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'action\tjetbrains-mono-nerd-font-fedora\tbase-jetbrains-mono-nerd-font'
}

@test "Fedora base plan does not include optional selections by default" {
  build_fedora_plan

  refute_plan_has "$PLAN_DIR/sources/fedora-vendor.list" "vendor:vscode"
  refute_plan_has "$PLAN_DIR/sources/fedora-vendor.list" "vendor:claude-desktop"
  refute_plan_has "$PLAN_DIR/sources/fedora-copr.list" "copr:dejan/lazygit"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "code"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "claude-desktop"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "lazygit"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "firefox"
  refute_plan_has "$PLAN_DIR/packages/dnf.pkgs" "python3-pip"
  refute_plan_has "$PLAN_DIR/flatpak/apps.flatpaks" "com.discordapp.Discord"
  refute_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-sdk"
  refute_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-tools"
}

@test "browser and development selections add their sources and packages" {
  build_fedora_plan "browser=brave" "dev=vscode,lazygit" "ai=codex"

  assert_plan_has "$PLAN_DIR/sources/fedora-vendor.list" "vendor:brave"
  assert_plan_has "$PLAN_DIR/sources/fedora-vendor.list" "vendor:vscode"
  assert_plan_has "$PLAN_DIR/sources/fedora-copr.list" "copr:dejan/lazygit"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "brave-browser"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "code"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "lazygit"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "npm-global:@openai/codex"
}

@test "Firefox browser selection adds Firefox package bundle" {
  build_fedora_plan "browser=firefox"

  assert_plan_has "$PLAN_DIR/bundles.list" "browser-firefox"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "firefox"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "python3-pip"
}

@test "dotnet tools selection automatically includes SDK action" {
  build_fedora_plan "dotnet=tools"

  assert_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-sdk"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-tools"
}

@test "plan files stay unique after repeated overlapping selections" {
  build_fedora_plan "browser=zen-copr" "dev=vscode,neovim" "ai=codex,codex" "dotnet=tools"

  assert_unique_file "$PLAN_DIR/sources/fedora-flatpak-remotes.list"
  assert_unique_file "$PLAN_DIR/sources/fedora-vendor.list"
  assert_unique_file "$PLAN_DIR/packages/dnf.pkgs"
  assert_unique_file "$PLAN_DIR/actions/actions.list"
  assert_unique_file "$PLAN_DIR/services/system-enable-now.list"
  assert_unique_file "$PLAN_DIR/stow/packages.list"
}

@test "base manifests are always represented in the generated plan" {
  build_fedora_plan

  local bundle_id plan_file base_item
  for bundle_id in "${BASE_BUNDLE_IDS_fedora[@]}"; do
    assert_plan_has "$PLAN_DIR/bundles.list" "$bundle_id"
    load_bundle_descriptor fedora "$bundle_id"
    plan_file="$(package_file_for_backend "$BUNDLE_INSTALLER")"
    while IFS= read -r base_item; do
      [[ -n "$base_item" ]] || continue
      assert_plan_has "$plan_file" "$base_item"
    done < <(manifest_entries "$ROOT_DIR/$BUNDLE_ITEMS_FILE")
  done
}
