#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
  DISTRO=fedora
  load_adapter
}

@test "KDE Qt theme config uses Noctalia colors and default Yaru icon theme" {
  build_fedora_plan
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
  build_fedora_plan
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
