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
  # The managed entries wrap the inherited PATH: ~/.local/bin lands ahead of
  # it and the Homebrew prefix behind it, so distro binaries keep winning
  # lookups over Homebrew's unrequested duplicates (python3 especially). The
  # generator also reads /usr/lib/environment.d, so a host with the product
  # environment file installed may apply the managed entries more than once;
  # the inherited PATH must survive intact between them.
  local path_line="${output%%$'\n'*}"
  [[ "$path_line" == PATH=* ]]
  path_line="${path_line#PATH=}"
  [[ "$path_line" == *":$FAKE_BIN:/usr/bin"* ]]
  local prepended="${path_line%%":$FAKE_BIN:/usr/bin"*}"
  local appended="${path_line#*"$FAKE_BIN:/usr/bin"}" path_entry
  appended="${appended#:}"
  local saw_local_bin=0 saw_brew_bin=0 saw_brew_sbin=0
  while [[ -n "$prepended" ]]; do
    path_entry="${prepended%%:*}"
    [[ "$path_entry" == "$home_dir/.local/bin" ]] || return 1
    saw_local_bin=1
    [[ "$prepended" == *:* ]] || break
    prepended="${prepended#*:}"
  done
  while [[ -n "$appended" ]]; do
    path_entry="${appended%%:*}"
    case "$path_entry" in
      /home/linuxbrew/.linuxbrew/bin) saw_brew_bin=1 ;;
      /home/linuxbrew/.linuxbrew/sbin) saw_brew_sbin=1 ;;
      *) return 1 ;;
    esac
    [[ "$appended" == *:* ]] || break
    appended="${appended#*:}"
  done
  [ "$saw_local_bin" -eq 1 ]
  [ "$saw_brew_bin" -eq 1 ]
  [ "$saw_brew_sbin" -eq 1 ]
  assert_contains "$output" "NIRI=$FAKE_BIN/niri-session"
  refute_contains "$output" '${HOME}'
  refute_contains "$output" '${PATH:-'
}

# The fragment hardcodes the real Homebrew prefix, which a test cannot create.
# Rewrite that prefix to a sandbox copy carrying a fake brew whose shellenv
# output matches the real one, so the PATH handling itself is exercised.
stage_homebrew_fragment() {
  local prefix="$1"
  local fragment="$TEST_ROOT/homebrew-fragment"
  mkdir -p "$prefix/bin" "$prefix/sbin"
  cat >"$prefix/bin/brew" <<EOF
#!/usr/bin/env bash
printf 'export HOMEBREW_PREFIX="%s";\n' "$prefix"
printf 'export HOMEBREW_CELLAR="%s/Cellar";\n' "$prefix"
printf 'export PATH="%s/bin:%s/sbin\${PATH+:\$PATH}";\n' "$prefix" "$prefix"
EOF
  chmod +x "$prefix/bin/brew"
  sed "s#/home/linuxbrew/.linuxbrew#$prefix#g" \
    "$ROOT_DIR/dotfiles/shell/.shellrc.d/homebrew" >"$fragment"
  printf '%s\n' "$fragment"
}

@test "Homebrew fragment keeps the managed PATH order when the prefix is already present" {
  local prefix="$TEST_ROOT/brew-prefix" fragment
  fragment="$(stage_homebrew_fragment "$prefix")"
  local managed_path="$TEST_ROOT/home/.local/bin:/usr/bin:$prefix/bin:$prefix/sbin"

  run env PATH="$managed_path" bash -c \
    '. "$1"; printf "PATH=%s\nPREFIX=%s\n" "$PATH" "$HOMEBREW_PREFIX"' bash "$fragment"

  [ "$status" -eq 0 ]
  # environment.d put the prefix behind the distro directories; shellenv must
  # not promote it above them, nor repeat the prefix entries. Exact equality:
  # a substring check would miss duplicated entries appended after the match.
  assert_equal "PATH=$managed_path" "${lines[0]}"
  # The non-PATH half of shellenv still has to be applied.
  assert_contains "$output" "PREFIX=$prefix"
}

@test "Homebrew fragment appends the prefix when the managed PATH omits it" {
  local prefix="$TEST_ROOT/brew-prefix-absent" fragment
  fragment="$(stage_homebrew_fragment "$prefix")"

  run env PATH="/usr/bin" bash -c \
    '. "$1"; printf "PATH=%s\nPREFIX=%s\n" "$PATH" "$HOMEBREW_PREFIX"' bash "$fragment"

  [ "$status" -eq 0 ]
  # Homebrew only supplies tools Fedora does not package, so the prefix goes
  # behind the distro directories, never in front of them.
  assert_equal "PATH=/usr/bin:$prefix/bin:$prefix/sbin" "${lines[0]}"
  assert_contains "$output" "PREFIX=$prefix"
}

@test "Homebrew fragment completes a PATH carrying bin without sbin" {
  local prefix="$TEST_ROOT/brew-prefix-partial" fragment
  fragment="$(stage_homebrew_fragment "$prefix")"

  # lib/actions.sh login shells append only the bin directory; the fragment
  # must still supply sbin instead of treating the prefix as fully present.
  run env PATH="/usr/bin:$prefix/bin" bash -c \
    '. "$1"; printf "PATH=%s\nPREFIX=%s\n" "$PATH" "$HOMEBREW_PREFIX"' bash "$fragment"

  [ "$status" -eq 0 ]
  assert_equal "PATH=/usr/bin:$prefix/bin:$prefix/sbin" "${lines[0]}"
  assert_contains "$output" "PREFIX=$prefix"
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
