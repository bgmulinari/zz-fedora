#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
}

@test "Starship prompt uses the static ZZ palette with contrast coverage" {
  python3 "$ROOT_DIR/tests/support/starship_contrast.py" \
    "$ROOT_DIR/templates/starship.toml"
}

@test "Starship palette sync replaces only the marker-delimited block" {
  local home="$TEST_ROOT/starship-sync-home"
  mkdir -p "$home/.config" "$home/.cache/DankMaterialShell"
  cat >"$home/.config/starship.toml" <<'EOF'
palette = "zz"
user_top = "kept"
# >>> ZZ STARSHIP PALETTE >>>
[palettes.zz]
blue = "#old000"
# <<< ZZ STARSHIP PALETTE <<<
user_bottom = "kept"
EOF
  cat >"$home/.cache/DankMaterialShell/starship-palette.toml" <<'EOF'
# >>> ZZ STARSHIP PALETTE >>>
[palettes.zz]
blue = "#89b4fa"
red = "#f38ba8"
# <<< ZZ STARSHIP PALETTE <<<
EOF

  run env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-starship-palette"

  [ "$status" -eq 0 ]
  assert_file_contains "$home/.config/starship.toml" 'blue = "#89b4fa"'
  assert_file_contains "$home/.config/starship.toml" 'red = "#f38ba8"'
  refute_file_contains "$home/.config/starship.toml" "#old000"
  assert_file_contains "$home/.config/starship.toml" 'user_top = "kept"'
  assert_file_contains "$home/.config/starship.toml" 'user_bottom = "kept"'
  assert_equal "1" "$(grep -Fxc '# >>> ZZ STARSHIP PALETTE >>>' "$home/.config/starship.toml")"
  assert_equal "1" "$(grep -Fxc '# <<< ZZ STARSHIP PALETTE <<<' "$home/.config/starship.toml")"
}

@test "Starship palette sync leaves configurations without the markers alone" {
  local home="$TEST_ROOT/starship-optout-home"
  mkdir -p "$home/.config" "$home/.cache/DankMaterialShell"
  printf 'palette = "custom"\n' >"$home/.config/starship.toml"
  cat >"$home/.cache/DankMaterialShell/starship-palette.toml" <<'EOF'
# >>> ZZ STARSHIP PALETTE >>>
[palettes.zz]
blue = "#89b4fa"
# <<< ZZ STARSHIP PALETTE <<<
EOF

  run env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-starship-palette"

  [ "$status" -eq 0 ]
  assert_equal 'palette = "custom"' "$(cat "$home/.config/starship.toml")"
}

@test "Starship palette sync preserves a user-managed configuration symlink" {
  local home="$TEST_ROOT/starship-symlink-home"
  local managed="$TEST_ROOT/dotfiles/starship.toml"
  mkdir -p "$home/.config" "$home/.cache/DankMaterialShell" "$(dirname "$managed")"
  cat >"$managed" <<'EOF'
palette = "zz"
# >>> ZZ STARSHIP PALETTE >>>
[palettes.zz]
blue = "#old000"
# <<< ZZ STARSHIP PALETTE <<<
EOF
  chmod 0600 "$managed"
  ln -s "$managed" "$home/.config/starship.toml"
  cat >"$home/.cache/DankMaterialShell/starship-palette.toml" <<'EOF'
# >>> ZZ STARSHIP PALETTE >>>
[palettes.zz]
blue = "#89b4fa"
# <<< ZZ STARSHIP PALETTE <<<
EOF

  run env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_CACHE_HOME="$home/.cache" \
    "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-starship-palette"

  [ "$status" -eq 0 ]
  [[ -L "$home/.config/starship.toml" ]]
  assert_equal "$managed" "$(readlink "$home/.config/starship.toml")"
  assert_file_contains "$managed" 'blue = "#89b4fa"'
  assert_equal "600" "$(stat -c '%a' "$managed")"
}

@test "Starship matugen template covers exactly the static palette names" {
  local static_names template_names
  static_names="$(awk '/# >>> ZZ STARSHIP PALETTE >>>/,/# <<< ZZ STARSHIP PALETTE <<</' \
    "$ROOT_DIR/templates/starship.toml" | grep -oE '^[a-z0-9]+ =' | sort)"
  template_names="$(grep -oE '^[a-z0-9]+ =' \
    "$ROOT_DIR/dotfiles/dms/.config/matugen/templates/starship-palette.toml" | sort)"
  [ -n "$static_names" ]
  assert_equal "$static_names" "$template_names"
}

@test "Starship palette sync is wired through the matugen drop-in" {
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.config/matugen/dms/configs/zz-starship.toml\tproduct-link'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.local/bin/zz-sync-starship-palette\tproduct-link'
  assert_file_contains "$ROOT_DIR/dotfiles/dms/.config/matugen/dms/configs/zz-starship.toml" \
    "output_path = '~/.cache/DankMaterialShell/starship-palette.toml'"
  [[ -x "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-starship-palette" ]]
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
