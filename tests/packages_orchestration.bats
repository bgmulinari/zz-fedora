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
@test "Noctalia Greeter Fedora action configures greetd fallback" {
  build_test_plan
  assert_plan_has "$PLAN_DIR/actions/actions.list" "noctalia-greeter"

  DRY_RUN=1
  run install_noctalia_greeter

  [ "$status" -eq 0 ]
  assert_contains "$output" "install greetd and Noctalia Greeter package noctalia-greeter"
  assert_contains "$output" "/etc/greetd/config.toml"
  assert_contains "$output" "ensure SELinux fcontext xdm_var_lib_t"
  assert_contains "$output" "noctalia-greeter-apply-appearance --setup-system"
  assert_contains "$output" "seed Noctalia Greeter appearance"
  assert_contains "$output" "restore SELinux contexts under /var/lib/noctalia-greeter"
  assert_contains "$output" "systemctl enable --force greetd.service"
}
@test "Noctalia Greeter disables hardware cursors in its greetd session" {
  run noctalia_greetd_config_content

  [ "$status" -eq 0 ]
  assert_contains "$output" 'command = "/usr/bin/env WLR_NO_HARDWARE_CURSORS=1 /usr/bin/noctalia-greeter-session"'
}
@test "Noctalia Greeter verification requires the hardware cursor workaround" {
  NOCTALIA_GREETD_CONFIG="$TEST_ROOT/greetd-config.toml"
  NOCTALIA_GREETER_STATE_DIR="$TEST_ROOT/noctalia-greeter"
  mkdir -p "$NOCTALIA_GREETER_STATE_DIR"
  printf '{}\n' >"$NOCTALIA_GREETER_STATE_DIR/appearance.json"
  rpm() { return 0; }
  command() { return 0; }
  systemctl() { return 0; }
  verify_noctalia_greeter_selinux_context() { return 0; }

  printf '[default_session]\ncommand = "%s"\n' "$NOCTALIA_GREETER_SESSION_BIN" >"$NOCTALIA_GREETD_CONFIG"
  run verify_noctalia_greeter
  [ "$status" -ne 0 ]

  noctalia_greetd_config_content >"$NOCTALIA_GREETD_CONFIG"
  run verify_noctalia_greeter
  [ "$status" -eq 0 ]
}
@test "Noctalia Greeter SELinux fcontext setup is idempotent" {
  DRY_RUN=0
  NOCTALIA_GREETER_STATE_DIR="$TEST_ROOT/noctalia-greeter"
  local current_type=""
  selinuxenabled() { return 0; }
  semanage() {
    if [[ "$*" == "fcontext -l -C" && -n "$current_type" ]]; then
      printf '%s all files system_u:object_r:%s:s0\n' "$NOCTALIA_GREETER_STATE_DIR(/.*)?" "$current_type"
    fi
  }
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$TEST_ROOT/root.log"
  }

  run_without_bats_debug_trap ensure_noctalia_greeter_selinux_fcontext
  assert_file_contains "$TEST_ROOT/root.log" "semanage fcontext -a -t xdm_var_lib_t $NOCTALIA_GREETER_STATE_DIR(/.*)?"

  : >"$TEST_ROOT/root.log"
  current_type="xdm_var_lib_t"
  run_without_bats_debug_trap ensure_noctalia_greeter_selinux_fcontext
  [ ! -s "$TEST_ROOT/root.log" ]

  current_type="var_lib_t"
  run_without_bats_debug_trap ensure_noctalia_greeter_selinux_fcontext
  assert_file_contains "$TEST_ROOT/root.log" "semanage fcontext -m -t xdm_var_lib_t $NOCTALIA_GREETER_STATE_DIR(/.*)?"
}
@test "Noctalia Greeter restores and verifies its SELinux state contexts" {
  DRY_RUN=0
  NOCTALIA_GREETER_STATE_DIR="$TEST_ROOT/noctalia-greeter"
  local current_type="xdm_var_lib_t"
  local context_matches=0
  selinuxenabled() { return 0; }
  restorecon() { :; }
  matchpathcon() {
    case "$1" in
      -n)
        printf 'system_u:object_r:%s:s0\n' "$current_type"
        ;;
      -V)
        return "$context_matches"
        ;;
    esac
  }
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$TEST_ROOT/root.log"
  }

  run_without_bats_debug_trap restore_noctalia_greeter_selinux_context
  assert_file_contains "$TEST_ROOT/root.log" "restorecon -RF $NOCTALIA_GREETER_STATE_DIR"

  run verify_noctalia_greeter_selinux_context
  [ "$status" -eq 0 ]

  current_type="var_lib_t"
  run verify_noctalia_greeter_selinux_context
  [ "$status" -ne 0 ]

  current_type="xdm_var_lib_t"
  context_matches=1
  run verify_noctalia_greeter_selinux_context
  [ "$status" -ne 0 ]
}
@test "Noctalia Greeter SELinux setup skips cleanly when SELinux is disabled" {
  DRY_RUN=0
  selinuxenabled() { return 1; }
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$TEST_ROOT/root.log"
  }

  run_without_bats_debug_trap ensure_noctalia_greeter_selinux_fcontext
  run_without_bats_debug_trap restore_noctalia_greeter_selinux_context
  [ ! -f "$TEST_ROOT/root.log" ]

  run verify_noctalia_greeter_selinux_context
  [ "$status" -eq 0 ]
}
@test "Noctalia Greeter appearance seed stages the managed palette and wallpaper" {
  build_test_plan
  DRY_RUN=0
  run_cmd_as_root() {
    if [[ "$1" == "env" ]]; then
      shift
      while [[ "$1" == *=* ]]; do shift; done
    fi
    printf 'root:%s\n' "$*" >>"$TEST_ROOT/root.log"
    if [[ "$1" == "noctalia-greeter-apply-appearance" && -d "${2:-}" ]]; then
      cp "$2/appearance.json" "$TEST_ROOT/appearance.json"
      cp "$2"/wallpaper.* "$TEST_ROOT/"
    fi
  }

  run_without_bats_debug_trap seed_noctalia_greeter_appearance

  assert_file_contains "$TEST_ROOT/root.log" "noctalia-greeter-apply-appearance"
  [ -s "$TEST_ROOT/appearance.json" ]

  # The staged manifest mirrors the managed palette exactly and satisfies the
  # greeter contract: version 1 and sixteen non-null snake_case palette keys.
  local palette_file="$ROOT_DIR/dotfiles/noctalia/.config/noctalia/palettes/catppuccin-mocha-blue.json"
  assert_equal "1" "$(jq -r '.version' "$TEST_ROOT/appearance.json")"
  assert_equal "dark" "$(jq -r '.theme_mode' "$TEST_ROOT/appearance.json")"
  assert_equal "16" "$(jq -r '[.palette | to_entries[] | select(.value | type == "string")] | length' "$TEST_ROOT/appearance.json")"
  assert_equal "$(jq -r '.dark.mPrimary' "$palette_file")" "$(jq -r '.palette.primary' "$TEST_ROOT/appearance.json")"
  assert_equal "$(jq -r '.dark.mSurface' "$palette_file")" "$(jq -r '.palette.surface' "$TEST_ROOT/appearance.json")"
  assert_equal "$(jq -r '.dark.mOnSurfaceVariant' "$palette_file")" "$(jq -r '.palette.on_surface_variant' "$TEST_ROOT/appearance.json")"

  # The wallpaper is staged from the bundled assets and referenced at its
  # installed location inside the greeter state directory.
  local wallpaper_path
  wallpaper_path="$(jq -r '.wallpaper.path' "$TEST_ROOT/appearance.json")"
  assert_equal "/var/lib/noctalia-greeter" "$(dirname "$wallpaper_path")"
  [ -s "$TEST_ROOT/$(basename "$wallpaper_path")" ]
}
@test "Noctalia Greeter appearance seed skips gracefully instead of failing the install" {
  build_test_plan
  DRY_RUN=0
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$TEST_ROOT/root.log"
  }

  # --skip-dotfiles keeps the greeter's own defaults and records the skip.
  SKIP_DOTFILES=1
  run_without_bats_debug_trap seed_noctalia_greeter_appearance
  SKIP_DOTFILES=0

  [ ! -f "$TEST_ROOT/root.log" ]
  # The skip is recorded, which is what verification accepts in place of
  # the manifest.
  noctalia_greeter_appearance_seed_skipped
  assert_file_contains "$PLAN_DIR/system-skips.tsv" 'noctalia-greeter-appearance'
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
@test "existing display manager skips Noctalia Greeter action" {
  build_test_plan
  DRY_RUN=0

  detect_enabled_display_manager() {
    printf 'gdm.service\n'
  }
  package_install_idempotent() {
    local backend="$1"
    shift
    printf 'install:%s:%s\n' "$backend" "$*"
    return 0
  }
  run_cmd_as_root() {
    printf 'cmd:%s\n' "$*"
  }

  run install_noctalia_greeter

  [ "$status" -eq 0 ]
  assert_tsv_row "$PLAN_DIR/system-skips.tsv" $'action\tnoctalia-greeter\texisting display manager: gdm.service'
  refute_contains "$output" "install:"
  refute_contains "$output" "cmd:"
}
@test "existing managed greetd reconciles Noctalia Greeter SELinux state before skipping setup" {
  build_test_plan
  DRY_RUN=0
  NOCTALIA_GREETD_CONFIG="$TEST_ROOT/greetd-config.toml"
  NOCTALIA_GREETER_STATE_DIR="$TEST_ROOT/noctalia-greeter"
  local verification_status=0
  mkdir -p "$NOCTALIA_GREETER_STATE_DIR"
  printf '{}\n' >"$NOCTALIA_GREETER_STATE_DIR/greeter.toml"
  noctalia_greetd_config_content >"$NOCTALIA_GREETD_CONFIG"

  detect_enabled_display_manager() {
    printf 'greetd.service\n'
  }
  ensure_noctalia_greeter_selinux_fcontext() {
    printf 'selinux:ensure\n'
  }
  restore_noctalia_greeter_selinux_context() {
    printf 'selinux:restore\n'
  }
  verify_noctalia_greeter_selinux_context() {
    printf 'selinux:verify\n'
    return "$verification_status"
  }
  package_install_idempotent() {
    printf 'unexpected-install:%s\n' "$*"
  }
  run_cmd_as_root() {
    printf 'unexpected-cmd:%s\n' "$*"
  }

  run install_noctalia_greeter

  [ "$status" -eq 0 ]
  assert_contains "$output" "selinux:ensure"
  assert_contains "$output" "selinux:restore"
  assert_contains "$output" "selinux:verify"
  assert_tsv_row "$PLAN_DIR/system-skips.tsv" $'action\tnoctalia-greeter\texisting display manager: greetd.service'
  refute_contains "$output" "unexpected-install:"
  refute_contains "$output" "unexpected-cmd:"

  verification_status=1
  run install_noctalia_greeter
  [ "$status" -ne 0 ]
  assert_contains "$output" "state does not have the required SELinux context"
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
