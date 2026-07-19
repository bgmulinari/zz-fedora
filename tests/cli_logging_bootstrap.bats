#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
}

@test "bootstrap defaults to a shallow hidden checkout" {
  assert_file_contains "$ROOT_DIR/bootstrap.sh" 'INSTALL_DIR="${HOME}/.zz"'
  assert_file_contains "$ROOT_DIR/bootstrap.sh" \
    'git clone --filter=blob:none --depth=1 "$REPO_URL" "$INSTALL_DIR"'
}

@test "install dry-run keeps base setup before optional work" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" DESKTOP_APP_PROFILE=full \
    bash "$ROOT_DIR/install.sh" install --dry-run --no-tui

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "==> [1/9] Preflight"
  assert_contains "$output" "==> [4/9] Base Setup"
  assert_contains "$output" "==> [5/9] Optional Packages"
  assert_contains "$output" "==> [6/9] Custom Actions"
  assert_contains "$output" "==> [9/9] Doctor"
  assert_contains "$output" "sudo npm install -g @openai/codex"
  assert_contains "$output" "DRY-RUN: user login shell: brew list 'opencode' >/dev/null 2>&1 || brew install 'opencode'"
  assert_contains "$output" "DRY-RUN: install active .NET SDK channels"
  assert_contains "$output" "jetbrains-mono-nerd-font"
  assert_contains "$output" "sudo systemctl daemon-reload"
  assert_contains "$output" "sudo systemctl set-default graphical.target"
  assert_contains "$output" "sudo systemctl enable --force greetd.service"
}

@test "ZZ_-prefixed environment overrides seed the flag defaults" {
  run env \
    ZZ_DRY_RUN=1 ZZ_ASSUME_YES=1 ZZ_NO_TUI=1 \
    ZZ_INSTALL_WEAK_DEPS=1 ZZ_VERIFY_INSTALLS=0 ZZ_SKIP_DOTFILES=1 \
    DRY_RUN=0 ASSUME_YES=0 NO_TUI=0 \
    INSTALL_WEAK_DEPS=0 VERIFY_INSTALLS=1 SKIP_DOTFILES=0 \
    bash -c 'source "'"$ROOT_DIR"'/lib/common.sh"; printf "dry=%s yes=%s notui=%s weak=%s verify=%s skipdot=%s\n" "$DRY_RUN" "$ASSUME_YES" "$NO_TUI" "$INSTALL_WEAK_DEPS" "$VERIFY_INSTALLS" "$SKIP_DOTFILES"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "dry=1 yes=1 notui=1 weak=1 verify=0 skipdot=1"
}

@test "ZZ_DRY_RUN environment override makes install behave as --dry-run" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" DESKTOP_APP_PROFILE=full \
    ZZ_DRY_RUN=1 ZZ_NO_TUI=1 \
    bash "$ROOT_DIR/install.sh" install --yes

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "==> [1/9] Preflight"
  assert_contains "$output" "DRY-RUN:"
}

@test "preflight accepts a worktree-style Git checkout" {
  fixture_root="$TEST_ROOT/worktree-checkout"
  mkdir -p "$fixture_root/config" "$fixture_root/home"
  touch "$fixture_root/.git"
  # shellcheck source=../modules/00-preflight.sh
  source "$ROOT_DIR/modules/00-preflight.sh"

  run_preflight_fixture() {
    ROOT_DIR="$fixture_root"
    COMMAND=install
    DRY_RUN=1
    TARGET_USER="$(id -un)"
    TARGET_HOME="$fixture_root/home"
    log_progress() { :; }
    die() { printf '%s\n' "$*" >&2; return 1; }
    acquire_lock() { :; }
    resolved_desktop_app_profile() { printf 'full\n'; }
    category_names() { :; }
    module_00_preflight
  }

  run run_preflight_fixture
  [ "$status" -eq 0 ]
  assert_contains "$output" "Mode: install"
}

@test "preflight accepts Git metadata discoverable above the repository root" {
  fixture_root="$ROOT_DIR/tests"
  [[ ! -e "$fixture_root/.git" ]]
  # shellcheck source=../modules/00-preflight.sh
  source "$ROOT_DIR/modules/00-preflight.sh"

  run_preflight_fixture() {
    ROOT_DIR="$fixture_root"
    COMMAND=install
    DRY_RUN=1
    TARGET_USER="$(id -un)"
    TARGET_HOME="$TEST_ROOT/home"
    log_progress() { :; }
    die() { printf '%s\n' "$*" >&2; return 1; }
    acquire_lock() { :; }
    resolved_desktop_app_profile() { printf 'full\n'; }
    category_names() { :; }
    module_00_preflight
  }

  run run_preflight_fixture
  [ "$status" -eq 0 ]
  assert_contains "$output" "Mode: install"
}

@test "logging captures command output and redacts secrets" {
  source_core
  COMMAND="logging-test"
  DRY_RUN=0
  NO_TUI=1
  init_log_file

  [[ -L "$LOG_DIR/latest.log" ]]
  assert_equal "$LOG_FILE" "$(readlink -f "$LOG_DIR/latest.log")"

  emit_output() {
    printf 'stdout from step\n'
    printf 'stderr from step\n' >&2
    log_info "structured log from step"
  }

  run_with_log_capture file emit_output
  assert_file_contains "$LOG_FILE" "stdout from step"
  assert_file_contains "$LOG_FILE" "stderr from step"
  assert_file_contains "$LOG_FILE" "structured log from step"

  run_cmd true --password=hunter2 api-token >/dev/null 2>&1
  assert_file_contains "$LOG_FILE" "CMD: true --password=REDACTED REDACTED"
  refute_file_contains "$LOG_FILE" "hunter2"
}

@test "dry-run commands are printed and not executed" {
  source_core
  DRY_RUN=1
  touch_target="$TEST_ROOT/should-not-exist"

  run run_cmd touch "$touch_target"

  [ "$status" -eq 0 ]
  assert_contains "$output" "DRY-RUN: touch"
  [[ ! -e "$touch_target" ]]
}

@test "tui sanitizer removes carriage-return progress control sequences" {
  source_core
  sanitized="$(
    printf 'plain\033[31m red\033[0m\rprogress\033[2Kdone\n' | tui_sanitize_output_stream
  )"

  assert_contains "$sanitized" $'plain\033[31m red\033[0m'
  assert_contains "$sanitized" "progressdone"
  refute_contains "$sanitized" $'\033[2K'
  refute_contains "$sanitized" $'\r'
}

@test "stow uses no-folding for managed dotfiles" {
  command -v stow >/dev/null 2>&1 || skip "stow is not installed"
  assert_file_contains "$ROOT_DIR/lib/stow.sh" "--no-folding"

  stow_dir="$TEST_ROOT/dotfiles"
  target_home="$TEST_ROOT/home"
  mkdir -p \
    "$stow_dir/sample/.config/Code/User" \
    "$stow_dir/sample/.local/share/wallpapers" \
    "$target_home"

  printf '{}\n' >"$stow_dir/sample/.config/Code/User/settings.json"
  printf 'image\n' >"$stow_dir/sample/.local/share/wallpapers/SilentPeaks.jpg"

  stow --dir "$stow_dir" --target "$target_home" --no-folding sample

  [[ -d "$target_home/.config" ]]
  [[ ! -L "$target_home/.config" ]]
  [[ -d "$target_home/.config/Code" ]]
  [[ ! -L "$target_home/.config/Code" ]]
  [[ -L "$target_home/.config/Code/User/settings.json" ]]
  [[ -d "$target_home/.local/share" ]]
  [[ ! -L "$target_home/.local/share" ]]
  [[ -L "$target_home/.local/share/wallpapers/SilentPeaks.jpg" ]]
}

@test "bootstrap installs only Fedora prerequisites needed before handoff" {
  source_bootstrap_functions
  DRY_RUN=1
  need_sudo() {
    return 1
  }

  output="$(bootstrap_notice)"
  assert_contains "$output" "Packages: ca-certificates curl git gum dnf5-plugins"
  refute_contains "$output" "bats"
  refute_contains "$output" "dnf-plugins-core"

  output="$(bootstrap_fedora)"
  assert_contains "$output" "dnf install -y ca-certificates curl git gum dnf5-plugins"
  refute_contains "$output" "bats"
  refute_contains "$output" "dnf-plugins-core"
}

@test "bootstrap confirmation prompts before continuing without --yes" {
  command -v script >/dev/null 2>&1 || skip "script is not installed"
  source_bootstrap_functions

  confirm_cmd="$(printf '%q' "source \"$TEST_ROOT/bootstrap-source.sh\"; ASSUME_YES=0; DRY_RUN=0; NO_TUI=1; bootstrap_confirm && exit 1 || exit 0")"
  confirm_output="$(printf 'n\n' | script -qfec "bash -lc $confirm_cmd" /dev/null 2>&1)"

  assert_contains "$confirm_output" "Continue with bootstrap? [y/N]"
}

@test "bootstrap clone update fast-forwards clean installs and rejects dirty installs" {
  command -v git >/dev/null 2>&1 || skip "git is not installed"
  source_bootstrap_functions

  git -c init.defaultBranch=main init --bare "$TEST_ROOT/origin.git" >/dev/null
  git -c init.defaultBranch=main init "$TEST_ROOT/source" >/dev/null
  git -C "$TEST_ROOT/source" config user.email test@example.invalid
  git -C "$TEST_ROOT/source" config user.name "Test User"
  printf 'old\n' >"$TEST_ROOT/source/version.txt"
  git -C "$TEST_ROOT/source" add version.txt
  git -C "$TEST_ROOT/source" commit -m old >/dev/null
  git -C "$TEST_ROOT/source" remote add origin "$TEST_ROOT/origin.git"
  git -C "$TEST_ROOT/source" push -u origin main >/dev/null 2>&1

  git clone "$TEST_ROOT/origin.git" "$TEST_ROOT/install" >/dev/null 2>&1
  old_commit="$(git -C "$TEST_ROOT/install" rev-parse HEAD)"
  printf 'new\n' >"$TEST_ROOT/source/version.txt"
  git -C "$TEST_ROOT/source" commit -am new >/dev/null
  git -C "$TEST_ROOT/source" push >/dev/null 2>&1
  new_commit="$(git -C "$TEST_ROOT/source" rev-parse HEAD)"

  REPO_URL="$TEST_ROOT/origin.git"
  INSTALL_DIR="$TEST_ROOT/install"
  REF=""
  clone_or_update_repo

  assert_equal "$new_commit" "$(git -C "$TEST_ROOT/install" rev-parse HEAD)"
  assert_equal "new" "$(cat "$TEST_ROOT/install/version.txt")"
  [[ "$(git -C "$TEST_ROOT/install" rev-parse HEAD)" != "$old_commit" ]]

  git -C "$TEST_ROOT/source" switch -c desktop >/dev/null
  printf 'desktop old\n' >"$TEST_ROOT/source/version.txt"
  git -C "$TEST_ROOT/source" commit -am "desktop old" >/dev/null
  git -C "$TEST_ROOT/source" push -u origin desktop >/dev/null 2>&1
  git -C "$TEST_ROOT/install" fetch origin desktop >/dev/null 2>&1
  git -C "$TEST_ROOT/install" switch -c desktop origin/desktop >/dev/null
  desktop_old_commit="$(git -C "$TEST_ROOT/install" rev-parse HEAD)"
  printf 'desktop new\n' >"$TEST_ROOT/source/version.txt"
  git -C "$TEST_ROOT/source" commit -am "desktop new" >/dev/null
  git -C "$TEST_ROOT/source" push >/dev/null 2>&1
  desktop_new_commit="$(git -C "$TEST_ROOT/source" rev-parse HEAD)"

  REF=""
  clone_or_update_repo
  assert_equal "desktop" "$(git -C "$TEST_ROOT/install" branch --show-current)"
  assert_equal "$desktop_new_commit" "$(git -C "$TEST_ROOT/install" rev-parse HEAD)"
  assert_equal "desktop new" "$(cat "$TEST_ROOT/install/version.txt")"
  [[ "$(git -C "$TEST_ROOT/install" rev-parse HEAD)" != "$desktop_old_commit" ]]

  REF="main"
  clone_or_update_repo
  assert_equal "main" "$(git -C "$TEST_ROOT/install" branch --show-current)"
  assert_equal "$new_commit" "$(git -C "$TEST_ROOT/install" rev-parse HEAD)"

  printf 'dirty\n' >"$TEST_ROOT/install/local.txt"
  set +e
  output="$(clone_or_update_repo 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ]
  assert_contains "$output" "has uncommitted changes"

  git -C "$TEST_ROOT/install" reset --hard -q
  git -C "$TEST_ROOT/install" remote set-url origin "$TEST_ROOT/other-origin.git"
  set +e
  output="$(clone_or_update_repo 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ]
  assert_contains "$output" "expected $REPO_URL"

  INSTALL_DIR="$TEST_ROOT/iso-snapshot-install"
  mkdir -p "$INSTALL_DIR/config"
  printf 'format=1\n' >"$INSTALL_DIR/config/iso-payload.conf"
  REF="main"
  clone_or_update_repo
  [[ -d "$INSTALL_DIR/.git" ]]
  compgen -G "$TEST_ROOT/iso-snapshot-install.iso-snapshot.*" >/dev/null
}
