#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "vendored Catppuccin registry theme is structurally valid with accessible contrast" {
  "$SYSTEM_PYTHON" "$ROOT_DIR/tests/support/dms_theme.py" \
    "$ROOT_DIR/dotfiles/dms/.config/DankMaterialShell/themes/catppuccin/theme.json"
}

@test "vendored theme carries the shipped mocha and latte blue variants" {
  local theme="$ROOT_DIR/dotfiles/dms/.config/DankMaterialShell/themes/catppuccin/theme.json"

  assert_equal "#89b4fa" "$(jq -r '.variants.accents[] | select(.id == "blue") | .mocha.primary' "$theme")"
  assert_equal "#1e1e2e" "$(jq -r '.variants.flavors[] | select(.id == "mocha") | .dark.background' "$theme")"
  run jq -e '.variants.flavors[] | select(.id == "latte") | (.light // .dark) | has("background")' "$theme"
  [ "$status" -eq 0 ]
}

@test "DMS component plans the vendored theme link" {
  build_test_plan

  assert_plan_has \
    "$PLAN_DIR/files/managed-files.list" \
    "~/.config/DankMaterialShell/themes/catppuccin/theme.json"
}

@test "icon-theme sync selects the hue-nearest Yaru variant and applies it everywhere" {
  local home="$TEST_ROOT/icon-sync-home"
  mkdir -p "$home/.cache/DankMaterialShell" \
    "$home/.local/share/icons/Yaru" \
    "$home/.local/share/icons/Yaru-blue" \
    "$home/.local/share/icons/Yaru-red" \
    "$home/.local/share/icons/Yaru-yellow"
  printf '#e01b24\n' >"$home/.cache/DankMaterialShell/icon-theme-accent"
  setup_fake_bin
  make_fake_command gsettings
  make_fake_command dms
  make_fake_command kwriteconfig6

  run env PATH="$FAKE_BIN:$PATH" HOME="$home" XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_DIRS="$home/.local/share" \
    "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-icon-theme"

  [ "$status" -eq 0 ]
  assert_file_contains "$home/.config/qt6ct/qt6ct.conf" "icon_theme=Yaru-red"
  assert_file_contains "$COMMAND_LOG" "gsettings set org.gnome.desktop.interface icon-theme Yaru-red"
  assert_file_contains "$COMMAND_LOG" "dms ipc call settings set iconThemeDark Yaru-red"
  assert_file_contains "$COMMAND_LOG" "dms ipc call settings set iconThemeLight Yaru-red"
}

@test "icon-theme sync falls back to a neutral variant for low-chroma accents" {
  local home="$TEST_ROOT/icon-sync-gray-home"
  mkdir -p "$home/.cache/DankMaterialShell" \
    "$home/.local/share/icons/Yaru" \
    "$home/.local/share/icons/Yaru-dark" \
    "$home/.local/share/icons/Yaru-blue"
  printf '#808080\n' >"$home/.cache/DankMaterialShell/icon-theme-accent"
  setup_fake_bin
  make_fake_command gsettings
  make_fake_command dms
  make_fake_command kwriteconfig6

  run env PATH="$FAKE_BIN:$PATH" HOME="$home" XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_DIRS="$home/.local/share" \
    "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-icon-theme"

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "gsettings set org.gnome.desktop.interface icon-theme Yaru-dark"
}

@test "DMS component links the icon sync helper and matugen drop-in" {
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.local/bin/zz-sync-icon-theme\tproduct-link\tbackup-before-link\tdotfiles/dms/.local/bin/zz-sync-icon-theme'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.config/DankMaterialShell/matugen/dms/configs/zz-icon-theme.toml\tproduct-link'
  [[ -x "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-icon-theme" ]]
  assert_file_contains "$ROOT_DIR/dotfiles/dms/.config/DankMaterialShell/matugen/dms/configs/zz-icon-theme.toml" \
    "post_hook = 'sh -c \"command -v zz-sync-icon-theme"
}

@test "DMS settings seed selects the vendored theme with blue accents in both modes" {
  local seed
  seed="$(dms_settings_seed_json)"

  assert_equal "registry" "$(jq -r '.currentThemeCategory' <<<"$seed")"
  assert_equal "custom" "$(jq -r '.currentThemeName' <<<"$seed")"
  assert_equal "$TARGET_HOME/.config/DankMaterialShell/themes/catppuccin/theme.json" \
    "$(jq -r '.customThemeFile' <<<"$seed")"
  assert_equal "mocha" "$(jq -r '.registryThemeVariants.catppuccin.dark.flavor' <<<"$seed")"
  assert_equal "blue" "$(jq -r '.registryThemeVariants.catppuccin.dark.accent' <<<"$seed")"
  assert_equal "latte" "$(jq -r '.registryThemeVariants.catppuccin.light.flavor' <<<"$seed")"
  assert_equal "blue" "$(jq -r '.registryThemeVariants.catppuccin.light.accent' <<<"$seed")"
}
