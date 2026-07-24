#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "KDE Qt theme config uses Noctalia colors and default Yaru icon theme" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/kde-theme-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0

  have_cmd() {
    [[ "$1" != "kwriteconfig6" ]] && command -v "$1" >/dev/null 2>&1
  }
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  install_kde_qt_theme_config

  assert_file_contains "$TARGET_HOME/.config/kdeglobals" "ColorScheme=Noctalia"
  assert_file_contains "$TARGET_HOME/.config/kdeglobals" "Name=noctalia"
  assert_file_contains "$TARGET_HOME/.config/kdeglobals" "widgetStyle=Fusion"
  assert_file_contains "$TARGET_HOME/.config/kdeglobals" "Theme=Yaru-blue"
}

@test "installer mode globally enables user services without starting them" {
  build_test_plan
  TARGET_USER="test-user"
  DRY_RUN=0
  ZZ_INSTALLER_DEFER_START_SERVICES=1
  command_log="$TEST_ROOT/installer-user-services.log"

  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$command_log"
  }
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$command_log"
  }

  enable_user_services

  assert_file_contains "$command_log" "root:systemctl --global enable app-com.mitchellh.ghostty.service"
  refute_file_contains "$command_log" "--now"
  refute_file_contains "$command_log" "user:test-user"
}

@test "chroot install defers extra-data flatpaks, then first-run installs them in-session" {
  build_test_plan "media=spotify" "office=zoom,pinta"
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/extra-data-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  command_log="$TEST_ROOT/extra-data-commands.log"

  assert_plan_has "$PLAN_DIR/flatpak/apps.flatpaks" "com.spotify.Client"
  assert_plan_has "$PLAN_DIR/flatpak/apps.flatpaks" "us.zoom.Zoom"

  # Phase 1: deferred chroot install. The kernel refuses the user namespace
  # bwrap needs inside the chroot, so the sandbox probe fails and the two
  # extra-data apps are recorded for first-run instead of being attempted.
  FLATPAK_SANDBOX_AVAILABLE=0
  flatpak_app_uses_extra_data() {
    [[ "$2" == "com.spotify.Client" || "$2" == "us.zoom.Zoom" ]]
  }
  package_install_idempotent() {
    local backend="$1"
    shift
    printf '%s:%s\n' "$backend" "$*" >>"$command_log"
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$command_log"
  }

  run_without_bats_debug_trap module_32_optional_packages

  assert_file_line "$(flatpak_deferred_plan_file)" "com.spotify.Client"
  assert_file_line "$(flatpak_deferred_plan_file)" "us.zoom.Zoom"
  refute_file_contains "$command_log" "com.spotify.Client"
  refute_file_contains "$command_log" "us.zoom.Zoom"
  assert_file_contains "$command_log" "com.github.PintaProject.Pinta"

  # Phase 2: first login runs in the user's real session, where the sandbox
  # works and polkit allows an active session to install system flatpaks.
  : >"$command_log"
  stub_run_cmd_as_user "$command_log"
  register_first_run_hook
  run_without_bats_debug_trap module_85_first_run

  [[ -f "$(first_run_marker)" ]]
  [[ ! -e "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]
  [[ ! -e "$(flatpak_deferred_plan_file)" ]]
  [[ ! -e "$(flatpak_deferred_attempts_file)" ]]
  assert_file_contains "$command_log" "user:test-user:flatpak install -y --or-update --system flathub com.spotify.Client"
  assert_file_contains "$command_log" "user:test-user:flatpak install -y --or-update --system flathub us.zoom.Zoom"

  # Repeated logins stay clean: the marker short-circuits first-run.
  : >"$command_log"
  run_without_bats_debug_trap module_85_first_run
  [[ ! -s "$command_log" ]]
}

@test "deferred flatpak failure keeps the list and blocks the first-run marker for a retry" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/deferred-retry-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  command_log="$TEST_ROOT/deferred-retry-commands.log"

  printf 'com.spotify.Client\nus.zoom.Zoom\n' >"$(flatpak_deferred_plan_file)"

  stub_run_cmd_as_user "$command_log"
  stub_user_cmd_intercept() {
    [[ "$1" != "flatpak" || "$*" != *"com.spotify.Client"* ]]
  }
  register_first_run_hook

  local output status
  capture_without_bats_debug_trap output status module_85_first_run
  [ "$status" -ne 0 ]
  assert_contains "$output" "Deferred Flatpak failed and will be retried on next login: com.spotify.Client"

  # The failed app stays on the list, the successful one is dropped, the
  # failed pass is counted, and the hook plus missing marker keep first-run
  # scheduled for the next login.
  assert_file_line "$(flatpak_deferred_plan_file)" "com.spotify.Client"
  refute_file_contains "$(flatpak_deferred_plan_file)" "us.zoom.Zoom"
  assert_equal "1" "$(flatpak_deferred_attempts)"
  [[ ! -f "$(first_run_marker)" ]]
  [[ -e "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]

  # The next login converges: the remaining app is re-attempted, installs,
  # and first-run completes with the queue and attempt counter cleared.
  unset -f stub_user_cmd_intercept
  : >"$command_log"
  run_without_bats_debug_trap module_85_first_run

  assert_file_contains "$command_log" "user:test-user:flatpak install -y --or-update --system flathub com.spotify.Client"
  [[ -f "$(first_run_marker)" ]]
  [[ ! -e "$(flatpak_deferred_plan_file)" ]]
  [[ ! -e "$(flatpak_deferred_attempts_file)" ]]
}

@test "deferred flatpaks are dropped with a warning after the retry budget is spent" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/deferred-budget-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0

  printf 'com.spotify.Client\n' >"$(flatpak_deferred_plan_file)"
  stub_run_cmd_as_user ""
  stub_user_cmd_intercept() {
    [[ "$1" != "flatpak" ]]
  }
  register_first_run_hook

  local output status attempt
  for attempt in 1 2 3 4; do
    capture_without_bats_debug_trap output status module_85_first_run
    [ "$status" -ne 0 ]
    [[ ! -f "$(first_run_marker)" ]]
    assert_equal "$attempt" "$(flatpak_deferred_attempts)"
  done

  # The fifth failed pass gives up: the queue is dropped with a warning and
  # first-run completes so a permanently failing app cannot wedge every
  # subsequent login.
  capture_without_bats_debug_trap output status module_85_first_run
  [ "$status" -eq 0 ]
  assert_contains "$output" "giving up"
  [[ -f "$(first_run_marker)" ]]
  [[ ! -e "$(flatpak_deferred_plan_file)" ]]
  [[ ! -e "$(flatpak_deferred_attempts_file)" ]]
  [[ ! -e "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]
}

@test "a deferred list appearing after first-run completion is consumed at next login" {
  build_test_plan
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/late-deferral-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  command_log="$TEST_ROOT/late-deferral-commands.log"

  mkdir -p "$(dirname "$(first_run_marker)")"
  printf 'completed_at=test\n' >"$(first_run_marker)"
  printf 'us.zoom.Zoom\n' >"$(flatpak_deferred_plan_file)"
  stub_run_cmd_as_user "$command_log"
  register_first_run_hook

  run_without_bats_debug_trap module_85_first_run

  # The marker short-circuit still drains the queue and clears the
  # re-registered hook without re-running the rest of first-run.
  assert_file_contains "$command_log" "user:test-user:flatpak install -y --or-update --system flathub us.zoom.Zoom"
  refute_file_contains "$command_log" "systemctl --user daemon-reload"
  [[ ! -e "$(flatpak_deferred_plan_file)" ]]
  [[ ! -e "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]
  [[ -f "$(first_run_marker)" ]]
}

@test "extra-data metadata probe distrusts empty cached output" {
  setup_fake_bin

  # flathub's summary cache can answer `remote-info --cached` with exit 0 and
  # EMPTY output; the probe must fall through to the network lookup instead
  # of reading that as "no extra data" (observed in the Anaconda chroot).
  write_fake_command flatpak <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--cached"* ]]; then
  exit 0
fi
printf '[Application]\nname=com.spotify.Client\n\n[Extra Data]\nname=spotify.snap\n'
EOF
  PATH="$FAKE_BIN:$PATH" flatpak_app_uses_extra_data flathub com.spotify.Client

  # A fully unreadable probe reads as unknown (2), never as "no extra data".
  write_fake_command flatpak <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  local probe_status=0
  PATH="$FAKE_BIN:$PATH" flatpak_app_uses_extra_data flathub com.spotify.Client || probe_status=$?
  assert_equal "2" "$probe_status"

  # Non-empty metadata without the extra-data group is a clean "no" (1).
  write_fake_command flatpak <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *"--cached"* ]] && exit 0
printf '[Application]\nname=org.inkscape.Inkscape\n'
EOF
  probe_status=0
  PATH="$FAKE_BIN:$PATH" flatpak_app_uses_extra_data flathub org.inkscape.Inkscape || probe_status=$?
  assert_equal "1" "$probe_status"
}

@test "dry-run previews extra-data deferral when the sandbox is unavailable" {
  build_test_plan "media=spotify"
  DRY_RUN=1
  FLATPAK_SANDBOX_AVAILABLE=0

  local output status
  capture_without_bats_debug_trap output status defer_extra_data_flatpaks "$PLAN_DIR/flatpak/apps.flatpaks"
  [ "$status" -eq 0 ]
  assert_contains "$output" "DRY-RUN: defer extra-data Flatpaks to first login"
  [[ ! -e "$(flatpak_deferred_plan_file)" ]]
}

@test "extra-data flatpaks install directly when the sandbox is available" {
  build_test_plan "media=spotify" "office=zoom"
  DRY_RUN=0
  command_log="$TEST_ROOT/sandbox-ok-commands.log"

  # A queue left behind by an earlier sandbox-restricted run is superseded:
  # this run installs everything directly and clears the stale state.
  printf 'com.spotify.Client\n' >"$(flatpak_deferred_plan_file)"
  printf '2\n' >"$(flatpak_deferred_attempts_file)"

  FLATPAK_SANDBOX_AVAILABLE=1
  flatpak_app_uses_extra_data() {
    printf 'unexpected-metadata-probe:%s\n' "$2" >>"$command_log"
    return 0
  }
  package_install_idempotent() {
    local backend="$1"
    shift
    printf '%s:%s\n' "$backend" "$*" >>"$command_log"
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$command_log"
  }

  run_without_bats_debug_trap module_32_optional_packages

  [[ ! -e "$(flatpak_deferred_plan_file)" ]]
  [[ ! -e "$(flatpak_deferred_attempts_file)" ]]
  refute_file_contains "$command_log" "unexpected-metadata-probe"
  assert_file_contains "$command_log" "com.spotify.Client"
  assert_file_contains "$command_log" "us.zoom.Zoom"
}

@test "deferred enable failure for a home-deployed unit warns, then first-run converges it" {
  build_test_plan "browser=firefox"
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/deferred-first-run-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  command_log="$TEST_ROOT/deferred-first-run-commands.log"

  # Phase 1: deferred chroot install. systemctl --global cannot see units
  # installed as managed configuration, so the Pywalfox unit fails while
  # RPM-shipped units keep working; the run warns and continues.
  ZZ_INSTALLER_DEFER_START_SERVICES=1
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$command_log"
    [[ "$*" != *"pywalfox-theme-sync.path"* ]]
  }
  stub_run_cmd_as_user "$command_log"

  local output status
  capture_without_bats_debug_trap output status enable_user_services
  [ "$status" -eq 0 ]
  assert_contains "$output" "Could not enable user service: pywalfox-theme-sync.path"
  assert_file_contains "$command_log" "root:systemctl --global enable pywalfox-theme-sync.path"
  refute_file_contains "$command_log" "user:test-user"

  # Phase 2: first login runs in the user's real session against the durable
  # plan, so first-run enables the planned units in-session and records the
  # completion marker.
  ZZ_INSTALLER_DEFER_START_SERVICES=0
  : >"$command_log"
  stub_run_cmd_as_user "$command_log"
  register_first_run_hook
  run_without_bats_debug_trap module_85_first_run

  [[ -f "$(first_run_marker)" ]]
  [[ ! -e "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]
  assert_file_contains "$command_log" "user:test-user:systemctl --user enable --now pywalfox-theme-sync.path"
  assert_file_contains "$command_log" "user:test-user:systemctl --user enable --now app-com.mitchellh.ghostty.service"

  # Repeated logins stay clean: the marker short-circuits first-run.
  : >"$command_log"
  run_without_bats_debug_trap module_85_first_run
  [[ ! -s "$command_log" ]]
}
