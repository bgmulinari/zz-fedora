#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
}

@test "shell startup files tolerate missing Cargo env" {
  local home_dir="$TEST_ROOT/shell-home"
  mkdir -p "$home_dir"

  run env HOME="$home_dir" ROOT_DIR="$ROOT_DIR" bash -lc 'set -e; . "$ROOT_DIR/dotfiles/shell/.profile"; . "$ROOT_DIR/dotfiles/shell/.bashrc"'

  [ "$status" -eq 0 ]
  refute_contains "$output" ".cargo/env"
}

@test "selected product shell integrations load before user fragments" {
  local home_dir="$TEST_ROOT/layered-shell-home"
  mkdir -p "$home_dir/.config/zz-fedora/shell.d" "$home_dir/.shellrc.d"
  ln -s "$ROOT_DIR" "$home_dir/.zz"
  printf 'ZZ_LAYER="${ZZ_LAYER:+$ZZ_LAYER:}product"\n' \
    >"$home_dir/.config/zz-fedora/shell.d/test"
  printf 'ZZ_LAYER="${ZZ_LAYER:+$ZZ_LAYER:}user"\n' \
    >"$home_dir/.shellrc.d/test"

  run env HOME="$home_dir" bash -c '. "$HOME/.zz/dotfiles/shell/.bashrc"; printf "%s\n" "$ZZ_LAYER"'

  [ "$status" -eq 0 ]
  assert_equal "product:user" "$output"
}

@test "profile resolves environment.d expansions without corrupting PATH" {
  setup_fake_bin
  local home_dir="$TEST_ROOT/profile-home"
  mkdir -p "$home_dir/.config/environment.d" "$home_dir/.local/bin"
  cp "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-niri-gtk.conf" \
    "$home_dir/.config/environment.d/10-niri-gtk.conf"
  write_fake_command niri-session <<'EOF'
#!/usr/bin/env sh
EOF

  run env -u XDG_CONFIG_HOME \
    HOME="$home_dir" \
    PATH="$FAKE_BIN:/usr/bin" \
    /bin/sh -c '. "$1"; printf "PATH=%s\nNIRI=%s\n" "$PATH" "$(command -v niri-session)"' \
    sh "$ROOT_DIR/dotfiles/shell/.profile"

  [ "$status" -eq 0 ]
  # The generator also reads /usr/lib/environment.d, so a host with the product
  # environment file installed legitimately prepends the same user bin a second
  # time. The inherited PATH must survive intact underneath, and every element
  # ahead of it must still be that one directory.
  local path_line="${output%%$'\n'*}"
  [[ "$path_line" == PATH=* ]]
  path_line="${path_line#PATH=}"
  [[ "$path_line" == *":$FAKE_BIN:/usr/bin" ]]
  local prepended="${path_line%":$FAKE_BIN:/usr/bin"}"
  while [[ -n "$prepended" ]]; do
    assert_equal "$home_dir/.local/bin" "${prepended%%:*}"
    [[ "$prepended" == *:* ]] || break
    prepended="${prepended#*:}"
  done
  assert_contains "$output" "NIRI=$FAKE_BIN/niri-session"
  refute_contains "$output" '${HOME}'
  refute_contains "$output" '${PATH:-'
}
