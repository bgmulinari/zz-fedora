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
