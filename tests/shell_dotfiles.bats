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
  cp "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-zz-desktop.conf" \
    "$home_dir/.config/environment.d/10-zz-desktop.conf"
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
  # environment file installed may prepend the managed entries more than once.
  # The inherited PATH must survive intact underneath, and only the managed
  # desktop-session entries may appear ahead of it.
  local path_line="${output%%$'\n'*}"
  [[ "$path_line" == PATH=* ]]
  path_line="${path_line#PATH=}"
  [[ "$path_line" == *":$FAKE_BIN:/usr/bin" ]]
  local prepended="${path_line%":$FAKE_BIN:/usr/bin"}" path_entry
  local saw_local_bin=0 saw_brew_bin=0 saw_brew_sbin=0
  while [[ -n "$prepended" ]]; do
    path_entry="${prepended%%:*}"
    case "$path_entry" in
      "$home_dir/.local/bin") saw_local_bin=1 ;;
      /home/linuxbrew/.linuxbrew/bin) saw_brew_bin=1 ;;
      /home/linuxbrew/.linuxbrew/sbin) saw_brew_sbin=1 ;;
      *) return 1 ;;
    esac
    [[ "$prepended" == *:* ]] || break
    prepended="${prepended#*:}"
  done
  [ "$saw_local_bin" -eq 1 ]
  [ "$saw_brew_bin" -eq 1 ]
  [ "$saw_brew_sbin" -eq 1 ]
  assert_contains "$output" "NIRI=$FAKE_BIN/niri-session"
  refute_contains "$output" '${HOME}'
  refute_contains "$output" '${PATH:-'
}

@test "Zsh login profile imports the managed desktop environment" {
  local home_dir="$TEST_ROOT/zsh-login-home"
  mkdir -p "$home_dir/.config/environment.d" "$home_dir/.local/bin"
  ln -s "$ROOT_DIR" "$home_dir/.zz"
  ln -s "$ROOT_DIR/dotfiles/zsh/.zprofile" "$home_dir/.zprofile"
  cp "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-zz-desktop.conf" \
    "$home_dir/.config/environment.d/10-zz-desktop.conf"

  run env -i \
    HOME="$home_dir" \
    USER=zz-test \
    LOGNAME=zz-test \
    SHELL=/bin/zsh \
    PATH=/usr/local/bin:/usr/bin \
    /bin/zsh -lc 'printf "PATH=%s\nTERMINAL=%s\n" "$PATH" "$TERMINAL"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "$home_dir/.local/bin"
  assert_contains "$output" "/home/linuxbrew/.linuxbrew/bin"
  assert_contains "$output" "/home/linuxbrew/.linuxbrew/sbin"
  assert_contains "$output" "TERMINAL=xdg-terminal-exec"
  refute_contains "$output" '${HOME}'
  refute_contains "$output" '${PATH:-'
}
