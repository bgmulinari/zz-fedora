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

@test "profile resolves environment.d expansions without corrupting PATH" {
  local home_dir="$TEST_ROOT/profile-home"
  local fake_bin="$TEST_ROOT/profile-bin"
  mkdir -p "$home_dir/.config/environment.d" "$home_dir/.local/bin" "$fake_bin"
  cp "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-niri-gtk.conf" \
    "$home_dir/.config/environment.d/10-niri-gtk.conf"
  printf '#!/usr/bin/env sh\n' >"$fake_bin/niri-session"
  chmod +x "$fake_bin/niri-session"

  run env -u XDG_CONFIG_HOME \
    HOME="$home_dir" \
    PATH="$fake_bin:/usr/bin" \
    /bin/sh -c '. "$1"; printf "PATH=%s\nNIRI=%s\n" "$PATH" "$(command -v niri-session)"' \
    sh "$ROOT_DIR/dotfiles/shell/.profile"

  [ "$status" -eq 0 ]
  assert_contains "$output" "PATH=$home_dir/.local/bin:$fake_bin:/usr/bin"
  assert_contains "$output" "NIRI=$fake_bin/niri-session"
  refute_contains "$output" '${HOME}'
  refute_contains "$output" '${PATH:-'
}
