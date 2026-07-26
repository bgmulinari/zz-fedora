#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "managed Noctalia custom palettes have complete, contrasting color roles" {
  python3 "$ROOT_DIR/tests/support/noctalia_palette.py" \
    "$ROOT_DIR"/dotfiles/noctalia/.config/noctalia/palettes/*.json
}

@test "Fedora palette uses official swatches with accessible light-terminal adaptations" {
  local palette="$ROOT_DIR/dotfiles/noctalia/.config/noctalia/palettes/fedora.json"

  assert_equal "#51a2da" "$(jq -r '.dark.mPrimary' "$palette")"
  assert_equal "#e59728" "$(jq -r '.dark.mSecondary' "$palette")"
  assert_equal "#79db32" "$(jq -r '.dark.mTertiary' "$palette")"
  assert_equal "#080d15" "$(jq -r '.dark.mSurface' "$palette")"
  assert_equal "#0c1420" "$(jq -r '.dark.mSurfaceVariant' "$palette")"
  assert_equal "#080d15" "$(jq -r '.dark.terminal.background' "$palette")"
  assert_equal "#294172" "$(jq -r '.light.mPrimary' "$palette")"
  assert_equal "#3c6eb4" "$(jq -r '.light.mSecondary' "$palette")"
  assert_equal "#db3279" "$(jq -r '.light.mError' "$palette")"
  assert_equal "#448217" "$(jq -r '.light.terminal.normal.green' "$palette")"
  assert_equal "#9b6313" "$(jq -r '.light.terminal.normal.yellow' "$palette")"

  run jq -e '
    [
      "#000000", "#1d252e", "#4c4c4c", "#8c8c8c", "#dedede", "#ffffff",
      "#294172", "#6f81a6", "#d8e1ee",
      "#3c6eb4", "#8faed9", "#e8eff8",
      "#51a2da", "#aad0ee", "#dcebf8",
      "#a07cbc", "#cfbddd", "#ece5f1",
      "#db3279", "#ed97bb", "#f9dde9",
      "#e59728", "#f2ca92", "#fbeedb",
      "#79db32", "#bbed97", "#e9f9dd",
      "#448217", "#9b6313", "#0c1420", "#080d15"
    ] as $official |
    all(.. | strings | select(test("^#[0-9a-f]{6}$")); . as $color | $official | index($color) != null)
  ' "$palette"

  [ "$status" -eq 0 ]
}

@test "Noctalia component plans both managed custom palettes" {
  build_test_plan

  assert_plan_has \
    "$PLAN_DIR/files/managed-files.list" \
    "~/.config/noctalia/palettes/catppuccin-mocha-blue.json"
  assert_plan_has \
    "$PLAN_DIR/files/managed-files.list" \
    "~/.config/noctalia/palettes/fedora.json"
}
