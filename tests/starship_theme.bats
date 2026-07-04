#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
}

@test "Starship prompt uses Noctalia colors with default and Catppuccin contrast coverage" {
  python3 "$ROOT_DIR/tests/helpers/starship_contrast.py" \
    "$ROOT_DIR/templates/starship.toml" \
    "$ROOT_DIR/tests/fixtures/noctalia-builtin-terminal-palettes.tsv" \
    "$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml"
}
