#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
}

@test "Starship prompt uses Noctalia colors with managed and Catppuccin contrast coverage" {
  python3 "$ROOT_DIR/tests/helpers/starship_contrast.py" \
    "$ROOT_DIR/templates/starship.toml" \
    "$ROOT_DIR/tests/fixtures/noctalia-builtin-terminal-palettes.tsv" \
    "$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml"
}

@test "Starship prompt hides optional section separators when sections are empty" {
  command -v starship >/dev/null 2>&1 || skip "starship is not installed"

  local empty_dir="$TEST_ROOT/starship-empty"
  local git_dir="$TEST_ROOT/starship-git"
  local git_language_dir="$TEST_ROOT/starship-git-language"
  mkdir -p "$empty_dir" "$git_dir" "$git_language_dir"
  git -C "$git_dir" init -q
  git -C "$git_language_dir" init -q
  touch "$git_language_dir/Cargo.toml"

  local yellow_bg=$'\033[48;2;249;226;175'
  local yellow_to_green=$'\033[48;2;166;227;161;38;2;249;226;175'
  local yellow_to_blue=$'\033[48;2;137;180;250;38;2;249;226;175'
  local blue_to_green=$'\033[48;2;166;227;161;38;2;137;180;250'
  local prompt

  prompt="$(cd "$empty_dir" && TERM=xterm-256color STARSHIP_CONFIG="$ROOT_DIR/templates/starship.toml" STARSHIP_SHELL=bash starship prompt)"
  refute_contains "$prompt" "$yellow_bg"
  assert_contains "$prompt" "$blue_to_green"

  prompt="$(cd "$git_dir" && TERM=xterm-256color STARSHIP_CONFIG="$ROOT_DIR/templates/starship.toml" STARSHIP_SHELL=bash starship prompt)"
  assert_contains "$prompt" "$yellow_bg"
  assert_contains "$prompt" "$yellow_to_green"
  refute_contains "$prompt" "$yellow_to_blue"

  prompt="$(cd "$git_language_dir" && TERM=xterm-256color STARSHIP_CONFIG="$ROOT_DIR/templates/starship.toml" STARSHIP_SHELL=bash starship prompt)"
  assert_contains "$prompt" "$yellow_to_blue"
  assert_contains "$prompt" "$blue_to_green"
}
