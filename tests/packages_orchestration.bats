#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "display manager detector recognizes Plasma Login Manager" {
  DRY_RUN=0
  systemd_unit_enabled() {
    [[ "$1" == "plasmalogin.service" ]]
  }

  run detect_enabled_display_manager

  [ "$status" -eq 0 ]
  assert_equal "plasmalogin.service" "$output"
}
@test "base packages are installed before optional packages" {
  build_test_plan "dev=vscode"
  package_install_calls=()
  package_install_idempotent() {
    local backend="$1"
    shift
    package_install_calls+=("$backend:$*")
    [[ " $* " != *" code "* ]]
  }
  fedora_service_exists() {
    return 0
  }
  detect_enabled_display_manager() {
    return 1
  }

  run_without_bats_debug_trap module_30_packages
  run_without_bats_debug_trap module_32_optional_packages

  [[ "${package_install_calls[0]}" == dnf:* ]]
  [[ " ${package_install_calls[0]#*:} " == *" tuned-ppd "* ]]

  optional_index=-1
  found_code_retry=0
  for idx in "${!package_install_calls[@]}"; do
    call="${package_install_calls[$idx]}"
    if [[ "$optional_index" -eq -1 && (" $call " == *" code "* || "$call" == *":code") ]]; then
      optional_index="$idx"
    fi
    [[ "$call" == *":code" ]] && found_code_retry=1
  done

  [ "$optional_index" -gt 0 ]
  [ "$found_code_retry" -eq 1 ]
  for required_item in niri policycoreutils-python-utils zsh starship zoxide fastfetch gh btop fd-find fzf bat yazi; do
    found_before_optional=0
    for ((idx = 0; idx < optional_index; idx++)); do
      [[ " ${package_install_calls[$idx]#*:} " == *" $required_item "* ]] && found_before_optional=1
    done
    [ "$found_before_optional" -eq 1 ]
  done
}

@test "base shell configuration preserves a user-owned zsh entrypoint" {
  local zsh_plan="$TEST_ROOT/zsh-plan.pkgs"
  printf 'zsh\n' >"$zsh_plan"
  printf 'source "$HOME/.zshrc.d/personal"\n' >"$TARGET_HOME/.zshrc"
  DRY_RUN=0

  command() {
    if [[ "$1" == "-v" && "${2:-}" == "zsh" ]]; then
      return 0
    fi
    builtin command "$@"
  }
  install_pinned_git_checkout() {
    return 0
  }
  getent() {
    printf '%s:x:1000:1000::%s:/bin/zsh\n' "$TARGET_USER" "$TARGET_HOME"
  }
  run_cmd_as_root() {
    return 0
  }
  run_cmd_as_user() {
    shift
    "$@"
  }

  run_without_bats_debug_trap configure_base_shell "$zsh_plan"

  assert_equal 'source "$HOME/.zshrc.d/personal"' "$(cat "$TARGET_HOME/.zshrc")"
}

@test "DMS Greeter Fedora action configures greetd fallback" {
  build_test_plan
  assert_plan_has "$PLAN_DIR/actions/actions.list" "dms-greeter"

  DRY_RUN=1
  detect_enabled_display_manager() { return 1; }
  run install_dms_greeter

  [ "$status" -eq 0 ]
  assert_contains "$output" "install DMS Greeter package dms-greeter"
  assert_contains "$output" "/etc/greetd/config.toml"
  assert_contains "$output" "usermod -aG greeter $TARGET_USER"
  assert_contains "$output" "chmod 2770 /var/cache/dms-greeter/users"
  assert_contains "$output" "link the greeter cache to the target user DMS state"
  assert_contains "$output" "systemctl set-default graphical.target"
  assert_contains "$output" "systemctl enable --force greetd.service"
}
@test "DMS Greeter greetd session runs the greeter under niri" {
  run dms_greetd_config_content

  [ "$status" -eq 0 ]
  assert_contains "$output" 'command = "/usr/bin/dms-greeter --command niri"'
  assert_contains "$output" 'user = "greeter"'
}
@test "DMS Greeter greetd config is rewritten only when foreign" {
  DRY_RUN=0
  DMS_GREETD_CONFIG="$TEST_ROOT/greetd-config.toml"
  write_root_file() {
    local mode="$1" destination="$2"
    cat >"$destination"
    printf 'wrote:%s:%s\n' "$mode" "$destination" >>"$TEST_ROOT/root.log"
  }

  printf '[default_session]\ncommand = "agreety --cmd /bin/sh"\n' >"$DMS_GREETD_CONFIG"
  run_without_bats_debug_trap ensure_dms_greetd_config
  assert_file_contains "$TEST_ROOT/root.log" "wrote:0644:$DMS_GREETD_CONFIG"
  assert_file_contains "$DMS_GREETD_CONFIG" 'command = "/usr/bin/dms-greeter --command niri"'

  : >"$TEST_ROOT/root.log"
  run_without_bats_debug_trap ensure_dms_greetd_config
  [ ! -s "$TEST_ROOT/root.log" ]
}
@test "DMS Greeter action grants greeter access and stages the theme sync" {
  build_test_plan
  DRY_RUN=0
  TARGET_USER="dms-user"
  TARGET_HOME="$TEST_ROOT/dms-greeter-home"
  mkdir -p "$TARGET_HOME"
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$TEST_ROOT/root.log"
  }
  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/root.log"
    case "$1" in
      mkdir|install|cp) HOME="$TARGET_HOME" "$@" ;;
      *) return 0 ;;
    esac
  }

  run_without_bats_debug_trap prepare_dms_greeter_access
  run_without_bats_debug_trap prepare_dms_greeter_cache
  run_without_bats_debug_trap stage_dms_greeter_theme_sync

  assert_file_contains "$TEST_ROOT/root.log" "root:usermod -aG greeter dms-user"
  # Traversal grants are batched into one setfacl over the home path chain.
  assert_file_contains "$TEST_ROOT/root.log" "root:setfacl -m g:greeter:rX $TARGET_HOME $TARGET_HOME/.config $TARGET_HOME/.local $TARGET_HOME/.local/state $TARGET_HOME/.local/share $TARGET_HOME/.cache"
  # The DMS state dirs get one recursive grant and one default-ACL grant.
  assert_file_contains "$TEST_ROOT/root.log" "root:setfacl -R -m g:greeter:rX $TARGET_HOME/.config/DankMaterialShell $TARGET_HOME/.local/state/DankMaterialShell $TARGET_HOME/.cache/DankMaterialShell $TARGET_HOME/.local/share/backgrounds"
  assert_file_contains "$TEST_ROOT/root.log" "root:setfacl -d -m g:greeter:rX $TARGET_HOME/.config/DankMaterialShell $TARGET_HOME/.local/state/DankMaterialShell $TARGET_HOME/.cache/DankMaterialShell $TARGET_HOME/.local/share/backgrounds"
  assert_file_contains "$TEST_ROOT/root.log" "root:chown greeter:greeter /var/cache/dms-greeter"
  assert_file_contains "$TEST_ROOT/root.log" "root:chmod 2770 /var/cache/dms-greeter/users"
  assert_file_contains "$TEST_ROOT/root.log" "root:ln -sfn $TARGET_HOME/.config/DankMaterialShell/settings.json /var/cache/dms-greeter/settings.json"
  assert_file_contains "$TEST_ROOT/root.log" "root:ln -sfn $TARGET_HOME/.local/state/DankMaterialShell/session.json /var/cache/dms-greeter/session.json"
  assert_file_contains "$TEST_ROOT/root.log" "root:ln -sfn $TARGET_HOME/.cache/DankMaterialShell/dms-colors.json /var/cache/dms-greeter/colors.json"
  # The staging seeds the real managed state, never bare placeholders: the
  # greeter action runs before the post-actions seeding, and its files must
  # not block the theme seeds (the seeder only writes missing files).
  assert_equal "registry" "$(jq -r '.currentThemeCategory' "$TARGET_HOME/.config/DankMaterialShell/settings.json")"
  assert_equal "$TARGET_HOME/.local/share/backgrounds/CraterBlue.jpg" \
    "$(jq -r '.wallpaperPath' "$TARGET_HOME/.local/state/DankMaterialShell/session.json")"
  # The colors placeholder keeps the greeter cache symlink from dangling.
  assert_equal "{}" "$(jq -c '.' "$TARGET_HOME/.cache/DankMaterialShell/dms-colors.json")"
}

@test "DMS Greeter access grants skip the recursive walk when already granted" {
  build_test_plan
  DRY_RUN=0
  TARGET_USER="dms-user"
  TARGET_HOME="$TEST_ROOT/dms-greeter-acl-home"
  mkdir -p "$TARGET_HOME"
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$TEST_ROOT/acl-root.log"
  }
  run_cmd_as_user() {
    shift
    case "$1" in
      mkdir|install|cp) HOME="$TARGET_HOME" "$@" ;;
      *) return 0 ;;
    esac
  }
  getfacl() {
    printf 'group:greeter:r-x\n'
  }

  run_without_bats_debug_trap prepare_dms_greeter_access

  refute_file_contains "$TEST_ROOT/acl-root.log" "setfacl -R"
  assert_file_contains "$TEST_ROOT/acl-root.log" "root:setfacl -d -m g:greeter:rX $TARGET_HOME/.config/DankMaterialShell"
}
@test "DMS Greeter verification requires the user sync unless it was skipped" {
  build_test_plan
  DMS_GREETD_CONFIG="$TEST_ROOT/greetd-config.toml"
  DMS_GREETER_CACHE_DIR="$TEST_ROOT/dms-greeter-cache"
  TARGET_USER="dms-user"
  dms_greetd_config_content >"$DMS_GREETD_CONFIG"
  rpm() { return 0; }
  command() { return 0; }
  systemctl() { return 0; }
  id() { printf 'dms-user wheel\n'; }

  # Without the greeter group membership and cache symlinks, verify fails.
  run verify_dms_greeter
  [ "$status" -ne 0 ]

  # A recorded user-sync skip is accepted in place of the sync state.
  dms_greeter_skip_user_sync "user config skipped"
  run verify_dms_greeter
  [ "$status" -eq 0 ]

  # With group membership and the three cache symlinks, verify passes on
  # the sync state itself.
  rm -f "$PLAN_DIR/system-skips.tsv"
  id() { printf 'dms-user wheel greeter\n'; }
  mkdir -p "$DMS_GREETER_CACHE_DIR"
  ln -sfn "$TEST_ROOT/settings.json" "$DMS_GREETER_CACHE_DIR/settings.json"
  ln -sfn "$TEST_ROOT/session.json" "$DMS_GREETER_CACHE_DIR/session.json"
  ln -sfn "$TEST_ROOT/colors.json" "$DMS_GREETER_CACHE_DIR/colors.json"
  run verify_dms_greeter
  [ "$status" -eq 0 ]
}
@test "DMS Greeter action skips user sync with --skip-user-config" {
  build_test_plan
  DRY_RUN=0
  SKIP_USER_CONFIG=1
  DMS_GREETD_CONFIG="$TEST_ROOT/greetd-config.toml"
  dms_greetd_config_content >"$DMS_GREETD_CONFIG"
  detect_enabled_display_manager() { return 1; }
  install_dms_greeter_package() { return 0; }
  fedora_service_exists() { return 0; }
  command() {
    [[ "$1" == "-v" && "${2:-}" == "dms-greeter" ]] && return 0
    builtin command "$@"
  }
  prepare_dms_greeter_access() { printf 'unexpected-access\n'; }
  prepare_dms_greeter_cache() { printf 'unexpected-cache\n'; }
  stage_dms_greeter_theme_sync() { printf 'unexpected-sync\n'; }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*"
  }

  run install_dms_greeter

  [ "$status" -eq 0 ]
  refute_contains "$output" "unexpected-access"
  refute_contains "$output" "unexpected-cache"
  refute_contains "$output" "unexpected-sync"
  assert_tsv_row "$PLAN_DIR/system-skips.tsv" $'action\tdms-greeter-user-sync\tuser config skipped'
  assert_contains "$output" "root:systemctl enable --force greetd.service"
}
@test "required base package failure aborts base setup before service work" {
  build_test_plan
  catalog_ensure_loaded
  DRY_RUN=0

  package_install_idempotent() {
    local backend="$1"
    shift
    printf 'install:%s:%s\n' "$backend" "$*"
    return 1
  }
  fedora_service_exists() {
    printf 'unexpected-service-check:%s\n' "$1"
    return 0
  }
  detect_enabled_display_manager() {
    return 1
  }
  run_cmd_as_root() {
    printf 'unexpected-cmd:%s\n' "$*"
  }

  capture_without_bats_debug_trap output status module_30_packages

  [ "$status" -ne 0 ]
  assert_contains "$output" "install:dnf:"
  refute_contains "$output" "unexpected-service-check"
  refute_contains "$output" "unexpected-cmd"
}
@test "existing display manager skips DMS Greeter action" {
  build_test_plan
  DRY_RUN=0

  detect_enabled_display_manager() {
    printf 'gdm.service\n'
  }
  install_dms_greeter_package() {
    printf 'install:dms-greeter\n'
  }
  run_cmd_as_root() {
    printf 'cmd:%s\n' "$*"
  }

  run install_dms_greeter

  [ "$status" -eq 0 ]
  assert_tsv_row "$PLAN_DIR/system-skips.tsv" $'action\tdms-greeter\texisting display manager: gdm.service'
  refute_contains "$output" "install:"
  refute_contains "$output" "cmd:"
}
@test "existing managed greetd re-runs the idempotent DMS Greeter setup" {
  build_test_plan
  DRY_RUN=0
  DMS_GREETD_CONFIG="$TEST_ROOT/greetd-config.toml"
  DMS_GREETER_CACHE_DIR="$TEST_ROOT/dms-greeter-cache"
  dms_greetd_config_content >"$DMS_GREETD_CONFIG"

  detect_enabled_display_manager() {
    printf 'greetd.service\n'
  }
  install_dms_greeter_package() {
    printf 'install:dms-greeter\n'
  }
  fedora_service_exists() { return 0; }
  command() {
    [[ "$1" == "-v" && "${2:-}" == "dms-greeter" ]] && return 0
    builtin command "$@"
  }
  prepare_dms_greeter_access() { printf 'access:prepared\n'; }
  prepare_dms_greeter_cache() { printf 'cache:prepared\n'; }
  stage_dms_greeter_theme_sync() { printf 'sync:staged\n'; }
  run_cmd_as_root() {
    printf 'cmd:%s\n' "$*"
  }

  run install_dms_greeter

  [ "$status" -eq 0 ]
  assert_contains "$output" "install:dms-greeter"
  assert_contains "$output" "access:prepared"
  assert_contains "$output" "cache:prepared"
  assert_contains "$output" "sync:staged"
  assert_contains "$output" "cmd:systemctl enable --force greetd.service"
  [[ ! -f "$PLAN_DIR/system-skips.tsv" ]] || refute_file_contains "$PLAN_DIR/system-skips.tsv" 'dms-greeter'
}
@test "missing required service retries owning package before failing" {
  build_test_plan
  DRY_RUN=0

  set +e
  output="$(
    fedora_service_exists() {
      [[ "$1" != "tuned-ppd" ]]
    }
    package_install_idempotent() {
      printf 'install:%s:%s\n' "$1" "$2"
    }
    run_cmd_as_root() {
      printf 'cmd:%s\n' "$*"
    }
    configure_base_system_services
  )"
  status=$?
  set -e

  [ "$status" -ne 0 ]
  assert_contains "$output" "install:dnf:tuned-ppd"
  assert_contains "$output" "cmd:systemctl daemon-reload"
  refute_contains "$output" "cmd:systemctl enable"
}
@test "base system services are enabled and started in one transaction" {
  build_test_plan
  DRY_RUN=0

  fedora_service_exists() {
    return 0
  }
  run_cmd_as_root() {
    printf 'cmd:%s\n' "$*"
  }

  run configure_base_system_services

  [ "$status" -eq 0 ]
  [ "$(grep -Fc 'cmd:systemctl enable --now' <<<"$output")" -eq 1 ]
  for service_name in NetworkManager firewalld bluetooth chronyd tuned-ppd cups avahi-daemon; do
    grep -F 'cmd:systemctl enable --now' <<<"$output" | grep -F "$service_name" >/dev/null
  done
}
@test "Niri readiness failure aborts base setup" {
  build_test_plan
  catalog_ensure_loaded
  DRY_RUN=0

  package_install_idempotent() {
    local backend="$1"
    shift
    printf 'install:%s:%s\n' "$backend" "$*"
    return 0
  }
  command() {
    [[ "$1" == "-v" && "${2:-}" == "niri" ]] && return 1
    builtin command "$@"
  }
  fedora_service_exists() {
    return 0
  }
  detect_enabled_display_manager() {
    return 1
  }
  run_cmd_as_root() {
    printf 'cmd:%s\n' "$*"
  }

  capture_without_bats_debug_trap output status module_30_packages

  [ "$status" -ne 0 ]
  grep -F 'install:dnf:' <<<"$output" | grep -F ' niri ' >/dev/null
}
