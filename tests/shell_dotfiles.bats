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
    PATH="$home_dir/.local/bin:/usr/local/bin:/usr/bin" \
    /bin/zsh -lc 'printf "PATH=%s\nTERMINAL=%s\n" "$PATH" "$TERMINAL"'

  [ "$status" -eq 0 ]
  assert_equal "" "$(sed -n 's/^PATH=//p' <<<"$output" | tr ':' '\n' | sort | uniq -d)"
  assert_contains "$output" "$home_dir/.local/bin"
  assert_contains "$output" "/home/linuxbrew/.linuxbrew/bin"
  assert_contains "$output" "/home/linuxbrew/.linuxbrew/sbin"
  assert_contains "$output" "TERMINAL=xdg-terminal-exec"
  refute_contains "$output" '${HOME}'
  refute_contains "$output" '${PATH:-'
}

# niri-session re-executes itself through the Bash login shell, which reads
# ~/.bash_profile and never ~/.profile on its own. The product login profile
# must load the managed environment itself, because ~/.profile may be a file
# another installer created, then ~/.profile and ~/.bashrc for the user layers.
@test "Bash login profile imports the managed desktop environment, profile, and bashrc" {
  local home_dir="$TEST_ROOT/bash-login-home"
  mkdir -p "$home_dir/.config/environment.d" "$home_dir/.local/bin"
  ln -s "$ROOT_DIR" "$home_dir/.zz"
  ln -s "$ROOT_DIR/dotfiles/shell/.bash_profile" "$home_dir/.bash_profile"
  printf 'export ZZ_PROFILE_LOADED=1\n' >"$home_dir/.profile"
  printf 'ZZ_BASHRC_LOADED=1\n' >"$home_dir/.bashrc"
  cp "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-zz-desktop.conf" \
    "$home_dir/.config/environment.d/10-zz-desktop.conf"

  run env -i \
    HOME="$home_dir" \
    USER=zz-test \
    LOGNAME=zz-test \
    SHELL=/bin/bash \
    PATH=/usr/local/bin:/usr/bin \
    /bin/bash -lc 'printf "PATH=%s\nTERMINAL=%s\nPROFILE=%s\nBASHRC=%s\n" "$PATH" "$TERMINAL" "${ZZ_PROFILE_LOADED:-}" "${ZZ_BASHRC_LOADED:-}"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "$home_dir/.local/bin"
  assert_contains "$output" "/home/linuxbrew/.linuxbrew/bin"
  assert_contains "$output" "TERMINAL=xdg-terminal-exec"
  assert_contains "$output" "PROFILE=1"
  assert_contains "$output" "BASHRC=1"
}

# Account creation copies Fedora's /etc/skel/.bashrc, which prepends
# ~/.local/bin unless "$HOME/.local/bin:$HOME/bin:" already appears, and never
# loads the product bashrc. The login profile must still end with a clean PATH.
@test "Bash login with the seeded profile and a distro bashrc keeps PATH unique" {
  local home_dir="$TEST_ROOT/bash-seeded-login-home"
  mkdir -p "$home_dir/.config/environment.d" "$home_dir/.local/bin"
  ln -s "$ROOT_DIR" "$home_dir/.zz"
  ln -s "$ROOT_DIR/dotfiles/shell/.bash_profile" "$home_dir/.bash_profile"
  cp "$ROOT_DIR/templates/shell/profile" "$home_dir/.profile"
  cat >"$home_dir/.bashrc" <<'BASHRC'
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH
BASHRC
  cp "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-zz-desktop.conf" \
    "$home_dir/.config/environment.d/10-zz-desktop.conf"

  run env -i \
    HOME="$home_dir" \
    USER=zz-test \
    LOGNAME=zz-test \
    SHELL=/bin/bash \
    PATH=/usr/local/bin:/usr/bin \
    /bin/bash -lc 'printf "%s\n" "$PATH"'

  [ "$status" -eq 0 ]
  assert_equal "" "$(tr ':' '\n' <<<"$output" | sort | uniq -d)"
  [[ "$output" == "$home_dir/.local/bin:"* ]]
}

@test "PATH cleanup keeps the first occurrence of each entry and drops empty ones" {
  run env -i PATH='/a:/usr/bin::/b:/a:/usr/bin:/c:' /bin/sh -c \
    '. "$1"; printf "%s\n" "$PATH"' sh "$ROOT_DIR/dotfiles/shell/path-dedupe.sh"

  [ "$status" -eq 0 ]
  assert_equal "/a:/usr/bin:/b:/c" "$output"
}

# Each login shell in the session chain (greetd's profile, then niri-session's
# Bash login) re-imports the environment.d PATH, which prepends to the PATH it
# inherits, so a login shell must not grow duplicates from what it inherited.
@test "Bash login from an already-imported session environment keeps PATH unique" {
  local home_dir="$TEST_ROOT/bash-relogin-home" inherited
  mkdir -p "$home_dir/.config/environment.d" "$home_dir/.local/bin"
  ln -s "$ROOT_DIR" "$home_dir/.zz"
  ln -s "$ROOT_DIR/dotfiles/shell/.bash_profile" "$home_dir/.bash_profile"
  cp "$ROOT_DIR/templates/shell/profile" "$home_dir/.profile"
  printf 'export PATH="$PATH:/opt/vendor-tool"\n' >>"$home_dir/.profile"
  cp "$ROOT_DIR/templates/shell/bashrc" "$home_dir/.bashrc"
  cp "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-zz-desktop.conf" \
    "$home_dir/.config/environment.d/10-zz-desktop.conf"
  inherited="$home_dir/.local/bin:/usr/local/bin:/usr/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/opt/vendor-tool"

  run env -i \
    HOME="$home_dir" \
    USER=zz-test \
    LOGNAME=zz-test \
    SHELL=/bin/bash \
    PATH="$inherited" \
    /bin/bash -lc 'printf "%s\n" "$PATH"'

  [ "$status" -eq 0 ]
  assert_equal "" "$(tr ':' '\n' <<<"$output" | sort | uniq -d)"
  # Distro directories stay ahead of the Homebrew prefix.
  [[ "$output" == *"/usr/bin:"*"/home/linuxbrew/.linuxbrew/bin"* ]]
}

@test "interactive zsh drops PATH duplicates the session inherited" {
  local home_dir="$TEST_ROOT/zsh-interactive-home"
  mkdir -p "$home_dir"
  ln -s "$ROOT_DIR" "$home_dir/.zz"
  cp "$ROOT_DIR/templates/shell/zshrc" "$home_dir/.zshrc"

  run env -i \
    HOME="$home_dir" \
    PATH="/usr/local/bin:/usr/bin:/usr/local/bin:/usr/bin" \
    /bin/zsh -ic 'print -r -- "$PATH"' </dev/null

  [ "$status" -eq 0 ]
  assert_equal "" "$(tr ':' '\n' <<<"${lines[-1]}" | sort | uniq -d)"
  [[ "${lines[-1]}" == "/usr/local/bin:/usr/bin"* ]]
}

@test "fzf integration loads no key bindings in a shell without a terminal" {
  command -v fzf >/dev/null 2>&1 || skip "fzf is not installed"

  run bash -ic '. "$1"; type __fzf_history__ >/dev/null 2>&1 && echo loaded || echo skipped' \
    bash "$ROOT_DIR/dotfiles/shell-fzf/.shellrc.d/fzf" </dev/null

  [ "$status" -eq 0 ]
  assert_equal "skipped" "${lines[-1]}"
}

@test "fzf integration loads no zsh widgets in a shell without a terminal" {
  command -v fzf >/dev/null 2>&1 || skip "fzf is not installed"

  run zsh -ic '. "$1"; (( $+widgets[fzf-history-widget] )) && echo loaded || echo skipped' \
    zsh "$ROOT_DIR/dotfiles/shell-fzf/.shellrc.d/fzf" </dev/null

  [ "$status" -eq 0 ]
  refute_contains "$output" "can't change option"
  assert_equal "skipped" "${lines[-1]}"
}

@test "Ghostty defaults start zsh while the login shell stays bash" {
  assert_file_contains "$ROOT_DIR/dotfiles/ghostty/.config/ghostty/config" 'command = /usr/bin/zsh'
}

# The profile hardcodes the systemd environment.d generator path, which a
# host may or may not provide. Stage a copy pointing at a missing generator
# so the product defaults are asserted without any environment.d input.
stage_profile_without_generator() {
  local profile="$TEST_ROOT/profile-without-generator"
  sed "s#/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator#$TEST_ROOT/missing-environment-generator#" \
    "$ROOT_DIR/dotfiles/shell/.profile" >"$profile"
  printf '%s\n' "$profile"
}

@test "profile exports the product terminal without the environment.d generator" {
  local home_dir="$TEST_ROOT/no-generator-home" profile
  mkdir -p "$home_dir"
  profile="$(stage_profile_without_generator)"
  assert_file_contains "$profile" "$TEST_ROOT/missing-environment-generator"

  run env -i \
    HOME="$home_dir" \
    PATH=/usr/bin \
    /bin/sh -c '. "$1"; printf "TERMINAL=%s\n" "$TERMINAL"' \
    sh "$profile"

  [ "$status" -eq 0 ]
  assert_equal "TERMINAL=xdg-terminal-exec" "$output"
}

# greetd builds the session environment from a login shell, and Fedora's
# nano-default-editor profile.d script has already set EDITOR by the time the
# product profile runs. The profile must replace that with the installed editor
# so DMS and the ZZ menu rows, which never see an interactive shell, use it too.
@test "profile overrides the distro nano default with nvim in the login environment" {
  local home_dir="$TEST_ROOT/editor-home" profile
  mkdir -p "$home_dir" "$TEST_ROOT/editor-bin"
  printf '#!/bin/sh\n' >"$TEST_ROOT/editor-bin/nvim"
  chmod +x "$TEST_ROOT/editor-bin/nvim"
  profile="$(stage_profile_without_generator)"

  run env -i \
    HOME="$home_dir" \
    PATH="$TEST_ROOT/editor-bin:/usr/bin" \
    EDITOR=/usr/bin/nano \
    /bin/sh -c '. "$1"; printf "EDITOR=%s VISUAL=%s\n" "$EDITOR" "$VISUAL"' \
    sh "$profile"

  [ "$status" -eq 0 ]
  assert_contains "$output" "EDITOR=nvim VISUAL=nvim"
}

@test "profile falls back to vi for the login editor when nvim is not installed" {
  local home_dir="$TEST_ROOT/vi-home" profile
  mkdir -p "$home_dir" "$TEST_ROOT/vi-bin"
  printf '#!/bin/sh\n' >"$TEST_ROOT/vi-bin/vi"
  chmod +x "$TEST_ROOT/vi-bin/vi"
  profile="$(stage_profile_without_generator)"

  run env -i \
    HOME="$home_dir" \
    PATH="$TEST_ROOT/vi-bin" \
    EDITOR=/usr/bin/nano \
    /bin/sh -c '. "$1"; printf "EDITOR=%s\n" "$EDITOR"' \
    sh "$profile"

  [ "$status" -eq 0 ]
  assert_contains "$output" "EDITOR=vi"
}
