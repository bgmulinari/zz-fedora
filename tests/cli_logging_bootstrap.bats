#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
}

@test "bootstrap defaults to a shallow hidden checkout" {
  assert_file_contains "$ROOT_DIR/bootstrap.sh" 'INSTALL_DIR="${HOME}/.zz"'
  assert_file_contains "$ROOT_DIR/bootstrap.sh" \
    'git clone --filter=blob:none --depth=1 "$REPO_URL" "$INSTALL_DIR"'
  assert_file_contains "$ROOT_DIR/bootstrap.sh" 'fetch --prune origin'
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

@test "installer update mode keeps convergence steps and skips optional software installation" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" DESKTOP_APP_PROFILE=full \
    bash "$ROOT_DIR/install.sh" install --dry-run --no-tui
  [ "$status" -eq 0 ]

  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" DESKTOP_APP_PROFILE=full \
    bash "$ROOT_DIR/install.sh" install --dry-run --no-tui --yes --use-saved --update

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "Update mode: 1"
  assert_contains "$output" "==> [4/9] Base Setup"
  assert_contains "$output" "skipped: Optional Packages"
  assert_contains "$output" "skipped: Custom Actions"
  assert_contains "$output" "==> [7/9] User Configuration"
}

@test "installer update mode prunes obsolete saved choices and persists the current selection set" {
  mkdir -p "$XDG_CONFIG_HOME/zz-fedora"
  cat >"$XDG_CONFIG_HOME/zz-fedora/selections.conf" <<EOF
target_user=$TARGET_USER
desktop_app_profile=full
preferred_browser=retired-browser
select.browsers=firefox,retired-browser
select.desktop=retired-desktop-app
select.retired-category=retired-choice
EOF

  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" DESKTOP_APP_PROFILE=full \
    bash "$ROOT_DIR/install.sh" install --dry-run --no-tui --yes --use-saved --update

  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
  assert_contains "$output" "Saved choice 'retired-browser' in category 'browsers' is no longer available and was removed."
  assert_contains "$output" "Saved choice 'retired-desktop-app' in category 'desktop' is no longer available and was removed."
  assert_contains "$output" "Saved selection category 'retired-category' is no longer available and was removed."
  assert_contains "$output" "Saved preferred browser 'retired-browser' is no longer available and was removed."
  assert_file_contains "$XDG_CONFIG_HOME/zz-fedora/selections.conf" "preferred_browser="
  assert_file_contains "$XDG_CONFIG_HOME/zz-fedora/selections.conf" "select.browsers=firefox"
  assert_file_contains "$XDG_CONFIG_HOME/zz-fedora/selections.conf" "select.desktop="
}

@test "installer update mode still rejects an unknown explicit selection" {
  mkdir -p "$XDG_CONFIG_HOME/zz-fedora"
  cat >"$XDG_CONFIG_HOME/zz-fedora/selections.conf" <<EOF
target_user=$TARGET_USER
desktop_app_profile=full
preferred_browser=
select.browsers=firefox
EOF

  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" DESKTOP_APP_PROFILE=full \
    bash "$ROOT_DIR/install.sh" install --dry-run --no-tui --yes --use-saved --update --select desktop=retired-explicit-choice

  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown choice 'retired-explicit-choice' in category 'desktop'"
}

@test "ZZ_-prefixed environment overrides seed the flag defaults" {
  run env \
    ZZ_DRY_RUN=1 ZZ_ASSUME_YES=1 ZZ_NO_TUI=1 ZZ_UPDATE_MODE=1 \
    ZZ_INSTALL_WEAK_DEPS=1 ZZ_VERIFY_INSTALLS=0 ZZ_SKIP_USER_CONFIG=1 \
    DRY_RUN=0 ASSUME_YES=0 NO_TUI=0 UPDATE_MODE=0 \
    INSTALL_WEAK_DEPS=0 VERIFY_INSTALLS=1 SKIP_USER_CONFIG=0 \
    bash -c 'source "'"$ROOT_DIR"'/lib/common.sh"; printf "dry=%s yes=%s notui=%s update=%s weak=%s verify=%s skipconfig=%s\n" "$DRY_RUN" "$ASSUME_YES" "$NO_TUI" "$UPDATE_MODE" "$INSTALL_WEAK_DEPS" "$VERIFY_INSTALLS" "$SKIP_USER_CONFIG"'

  [ "$status" -eq 0 ]
  assert_contains "$output" "dry=1 yes=1 notui=1 update=1 weak=1 verify=0 skipconfig=1"
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

@test "bootstrap installs only Fedora prerequisites needed before handoff" {
  source_bootstrap_functions
  DRY_RUN=1
  need_sudo() {
    return 1
  }

  output="$(bootstrap_notice)"
  assert_contains "$output" "Packages: ca-certificates curl git gum python3 dnf5-plugins"
  refute_contains "$output" "bats"
  refute_contains "$output" "dnf-plugins-core"

  output="$(bootstrap_fedora)"
  assert_contains "$output" "dnf install -y ca-certificates curl git gum python3 dnf5-plugins"
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

  clone_or_update_repo
  assert_equal "desktop" "$(git -C "$TEST_ROOT/install" branch --show-current)"
  assert_equal "$desktop_new_commit" "$(git -C "$TEST_ROOT/install" rev-parse HEAD)"
  assert_equal "desktop new" "$(cat "$TEST_ROOT/install/version.txt")"
  [[ "$(git -C "$TEST_ROOT/install" rev-parse HEAD)" != "$desktop_old_commit" ]]

  git -C "$TEST_ROOT/install" config user.email test@example.invalid
  git -C "$TEST_ROOT/install" config user.name "Test User"
  printf 'local commit\n' >"$TEST_ROOT/install/local-commit.txt"
  git -C "$TEST_ROOT/install" add local-commit.txt
  git -C "$TEST_ROOT/install" commit -m "local commit" >/dev/null
  set +e
  output="$(clone_or_update_repo 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ]
  assert_contains "$output" "contains commits not present in origin/desktop"
  git -C "$TEST_ROOT/install" reset --hard -q origin/desktop

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
  clone_or_update_repo
  [[ -d "$INSTALL_DIR/.git" ]]
  compgen -G "$TEST_ROOT/iso-snapshot-install.iso-snapshot.*" >/dev/null
}

@test "bootstrap requires an origin-tracking branch before installer handoff" {
  command -v git >/dev/null 2>&1 || skip "git is not installed"
  source_bootstrap_functions

  git -c init.defaultBranch=main init --bare "$TEST_ROOT/origin.git" >/dev/null
  git -c init.defaultBranch=main init "$TEST_ROOT/source" >/dev/null
  git -C "$TEST_ROOT/source" config user.email test@example.invalid
  git -C "$TEST_ROOT/source" config user.name "Test User"
  git -C "$TEST_ROOT/source" commit --allow-empty -m initial >/dev/null
  git -C "$TEST_ROOT/source" remote add origin "$TEST_ROOT/origin.git"
  git -C "$TEST_ROOT/source" push -u origin main >/dev/null 2>&1
  git clone "$TEST_ROOT/origin.git" "$TEST_ROOT/install" >/dev/null 2>&1

  INSTALL_DIR="$TEST_ROOT/install"
  DRY_RUN=0

  git -C "$INSTALL_DIR" checkout --detach >/dev/null 2>&1
  set +e
  output="$(update_current_ref 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ]
  assert_contains "$output" "detached HEAD"

  git -C "$INSTALL_DIR" switch main >/dev/null 2>&1
  git -C "$INSTALL_DIR" switch -c local-only >/dev/null 2>&1
  set +e
  output="$(update_current_ref 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ]
  assert_contains "$output" "has no upstream branch"

  git -C "$INSTALL_DIR" switch main >/dev/null 2>&1
  git -C "$INSTALL_DIR" remote add fork "$TEST_ROOT/origin.git"
  git -C "$INSTALL_DIR" fetch fork >/dev/null 2>&1
  git -C "$INSTALL_DIR" branch --set-upstream-to=fork/main main >/dev/null
  set +e
  output="$(update_current_ref 2>&1)"
  status=$?
  set -e
  [ "$status" -ne 0 ]
  assert_contains "$output" "non-origin upstream fork/main"
}
