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
  for required_item in niri zsh starship zoxide fastfetch gh btop fd-find fzf bat yazi; do
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
  assert_contains "$output" "noctalia-greeter-apply-appearance --setup-system"
  assert_contains "$output" "systemctl enable --force greetd.service"
}
@test "required base package failure aborts base setup before service work" {
  build_test_plan
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
