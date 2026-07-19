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

@test "deferred enable failure for a home-deployed unit warns, then first-run converges it" {
  build_test_plan "browser=firefox"
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/deferred-first-run-home"
  mkdir -p "$TARGET_HOME"
  DRY_RUN=0
  command_log="$TEST_ROOT/deferred-first-run-commands.log"

  # Phase 1: deferred chroot install. systemctl --global cannot see units
  # stowed into the target user's home, so the Pywalfox unit fails while
  # RPM-shipped units keep working; the run warns and continues.
  ZZ_INSTALLER_DEFER_START_SERVICES=1
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$command_log"
    [[ "$*" != *"pywalfox-theme-sync.path"* ]]
  }
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$command_log"
    case "$1" in
      mkdir|rm|sh|install|cp)
        "$@"
        ;;
      *)
        return 0
        ;;
    esac
  }

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
