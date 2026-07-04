#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
  DISTRO=fedora
  load_adapter
}

@test "optional package transaction retries individually and continues" {
  plan_file="$TEST_ROOT/optional.pkgs"
  printf 'bad-package\ngood-package\n' >"$plan_file"
  install_attempts=()
  package_install_idempotent() {
    local backend="$1"
    shift
    install_attempts+=("$backend:$*")
    [[ " $* " != *" bad-package "* ]]
  }

  install_from_plan_file dnf "$plan_file" optional

  assert_equal "dnf:bad-package good-package" "${install_attempts[0]}"
  assert_equal "dnf:bad-package" "${install_attempts[1]}"
  assert_equal "dnf:good-package" "${install_attempts[2]}"
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

@test "required package transaction aborts without optional retry loop" {
  plan_file="$TEST_ROOT/required.pkgs"
  printf 'bad-package\ngood-package\n' >"$plan_file"
  package_install_idempotent() {
    local backend="$1"
    shift
    printf 'install:%s:%s\n' "$backend" "$*"
    return 1
  }

  run install_from_plan_file dnf "$plan_file" required

  [ "$status" -ne 0 ]
  assert_contains "$output" "install:dnf:bad-package good-package"
  [ "$(grep -Fc 'install:dnf:' <<<"$output")" -eq 1 ]
}

@test "base packages are installed before optional packages" {
  build_fedora_plan "dev=vscode"
  package_install_calls=()
  package_install_idempotent() {
    local backend="$1"
    shift
    package_install_calls+=("$backend:$*")
    [[ " $* " != *" code "* ]]
  }
  distro_service_exists() {
    return 0
  }
  detect_enabled_display_manager() {
    return 1
  }

  module_30_packages
  module_32_optional_packages

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
  build_fedora_plan
  assert_plan_has "$PLAN_DIR/actions/actions.list" "noctalia-greeter-fedora"

  DRY_RUN=1
  run install_fedora_noctalia_greeter

  [ "$status" -eq 0 ]
  assert_contains "$output" "install greetd and Noctalia Greeter package noctalia-greeter"
  assert_contains "$output" "/etc/greetd/config.toml"
  assert_contains "$output" "noctalia-greeter-apply-appearance --setup-system"
  assert_contains "$output" "systemctl enable --force greetd.service"
}

@test "Noctalia v5 Fedora action installs latest COPR build" {
  build_fedora_plan
  assert_plan_has "$PLAN_DIR/actions/actions.list" "noctalia-v5-fedora"

  DRY_RUN=1
  run install_fedora_noctalia_v5

  [ "$status" -eq 0 ]
  assert_contains "$output" "install or sync Noctalia v5 package"
  assert_contains "$output" "noctalia-git"
  assert_contains "$output" "copr:copr.fedorainfracloud.org:lionheartp:Hyprland"
}

@test "required base package failure aborts base setup before service work" {
  build_fedora_plan
  DRY_RUN=0

  set +e
  output="$(
    package_install_idempotent() {
      local backend="$1"
      shift
      printf 'install:%s:%s\n' "$backend" "$*"
      return 1
    }
    distro_service_exists() {
      printf 'unexpected-service-check:%s\n' "$1"
      return 0
    }
    detect_enabled_display_manager() {
      return 1
    }
    run_cmd_as_root() {
      printf 'unexpected-cmd:%s\n' "$*"
    }
    module_30_packages
  )"
  status=$?
  set -e

  [ "$status" -ne 0 ]
  assert_contains "$output" "install:dnf:"
  refute_contains "$output" "unexpected-service-check"
  refute_contains "$output" "unexpected-cmd"
}

@test "existing display manager skips Noctalia Greeter action" {
  build_fedora_plan
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

  run install_fedora_noctalia_greeter

  [ "$status" -eq 0 ]
  assert_tsv_row "$PLAN_DIR/system-skips.tsv" $'action\tnoctalia-greeter-fedora\texisting display manager: gdm.service'
  refute_contains "$output" "install:"
  refute_contains "$output" "cmd:"
}

@test "missing required service retries owning package before failing" {
  build_fedora_plan
  DRY_RUN=0

  set +e
  output="$(
    distro_service_exists() {
      [[ "$1" != "tuned-ppd" ]]
    }
    package_install_idempotent() {
      printf 'install:%s:%s\n' "$1" "$2"
    }
    run_cmd_as_root() {
      printf 'cmd:%s\n' "$*"
    }
    distro_enable_service_now() {
      printf 'enable:%s\n' "$1"
    }
    configure_base_system_services
  )"
  status=$?
  set -e

  [ "$status" -ne 0 ]
  assert_contains "$output" "install:dnf:tuned-ppd"
  assert_contains "$output" "cmd:systemctl daemon-reload"
  assert_contains "$output" "enable:NetworkManager"
}

@test "Niri readiness failure aborts base setup" {
  build_fedora_plan
  DRY_RUN=0

  set +e
  output="$(
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
    distro_service_exists() {
      return 0
    }
    detect_enabled_display_manager() {
      return 1
    }
    run_cmd_as_root() {
      printf 'cmd:%s\n' "$*"
    }
    enable_required_system_service_now() {
      printf 'service:%s\n' "$1"
    }
    module_30_packages
  )"
  status=$?
  set -e

  [ "$status" -ne 0 ]
  grep -F 'install:dnf:' <<<"$output" | grep -F ' niri ' >/dev/null
}

@test "required install verification reports missing native packages" {
  plan_file="$TEST_ROOT/verify-native.pkgs"
  printf 'missing-native-package\n' >"$plan_file"
  VERIFY_INSTALLS=1
  DRY_RUN=0
  distro_package_installed() {
    return 1
  }

  run verify_required_plan_entries dnf "$plan_file" "base packages"

  [ "$status" -ne 0 ]
  assert_contains "$output" "Required base packages missing after install: missing-native-package"
}

@test "Fedora package verification accepts installed providers" {
  mkdir -p "$TEST_ROOT/bin"
  cat >"$TEST_ROOT/bin/rpm" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-q" && "$2" == "nodejs" ]]; then
  exit 1
fi
if [[ "$1" == "-q" && "$2" == "--whatprovides" && "$3" == "nodejs" ]]; then
  printf 'nodejs22-22.22.2-3.fc44.x86_64\n'
  exit 0
fi
exit 1
EOF
  chmod +x "$TEST_ROOT/bin/rpm"
  PATH="$TEST_ROOT/bin:$PATH"

  run distro_package_installed nodejs

  [ "$status" -eq 0 ]
}
