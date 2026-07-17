#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
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

@test "optional package verification rejects a provider for an architecture-qualified RPM" {
  plan_file="$TEST_ROOT/optional-exact.pkgs"
  install_log="$TEST_ROOT/optional-exact-installs.log"
  rpm_log="$TEST_ROOT/optional-exact-rpm.log"
  printf 'claude-desktop-unofficial.x86_64\n' >"$plan_file"
  VERIFY_INSTALLS=1
  DRY_RUN=0
  package_install_idempotent() {
    printf '%s:%s\n' "$1" "$2" >>"$install_log"
  }
  rpm() {
    printf '%s\n' "$*" >>"$rpm_log"
    if [[ "$*" == "-q --whatprovides claude-desktop-unofficial.x86_64" ]]; then
      return 0
    fi
    return 1
  }

  run install_from_plan_file dnf "$plan_file" optional

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$install_log")" -eq 2 ]
  assert_contains "$output" "Optional packages missing after install: claude-desktop-unofficial.x86_64"
  assert_contains "$output" "Optional dnf package failed and will be skipped for now: claude-desktop-unofficial.x86_64"
  refute_contains "$(<"$rpm_log")" "--whatprovides"
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

@test "run_cmd_as_user preserves UTF-8 locale variables" {
  TARGET_USER="locale-user"
  TARGET_HOME="$TEST_ROOT/locale-home"
  mkdir -p "$TARGET_HOME"
  export LANG=C.UTF-8
  export LC_ALL=C

  id() {
    if [[ "${1:-}" == "-u" && "${2:-}" == "locale-user" ]]; then
      printf '1234\n'
      return 0
    fi
    command id "$@"
  }
  getent() {
    if [[ "${1:-}" == "passwd" && "${2:-}" == "locale-user" ]]; then
      printf 'locale-user:x:1234:1234::%s:/bin/bash\n' "$TARGET_HOME"
      return 0
    fi
    command getent "$@"
  }
  run_cmd() {
    printf '%s\n' "$*"
  }

  run run_cmd_as_user locale-user true

  [ "$status" -eq 0 ]
  assert_contains "$output" "LANG=C.UTF-8"
  assert_contains "$output" "LC_ALL=C.UTF-8"
}

@test "pinned Git checkout is verified as its target user" {
  DRY_RUN=0
  TARGET_USER="checkout-user"
  destination="$TEST_ROOT/checkout"
  commit="d2379b2701df66a36b217a7707e77f8029a99814"
  command_log="$TEST_ROOT/checkout-commands.log"
  mkdir -p "$destination/.git"

  run_cmd_as_user() {
    printf '%s\n' "$*" >>"$command_log"
    if [[ "$*" == *" rev-parse HEAD" ]]; then
      printf '%s\n' "$commit"
    fi
  }
  git() {
    printf 'unexpected root Git invocation\n' >&2
    return 1
  }

  run install_pinned_git_checkout "Oh My Zsh" "https://example.invalid/ohmyzsh.git" "$commit" "$destination"

  [ "$status" -eq 0 ]
  assert_file_contains "$command_log" "checkout-user git -C $destination fetch --depth=1 origin $commit"
  assert_file_contains "$command_log" "checkout-user git -C $destination checkout --detach $commit"
  assert_file_contains "$command_log" "checkout-user git -C $destination rev-parse HEAD"
  refute_contains "$output" "unexpected root Git invocation"
}

@test "run_cmd honors opt-in command timeout" {
  DRY_RUN=0
  ZZ_COMMAND_TIMEOUT_SECONDS=7
  ZZ_COMMAND_TIMEOUT_KILL_AFTER=2s
  timeout() {
    printf 'timeout called:'
    printf ' %s' "$@"
    printf '\n'
    return 124
  }

  run run_cmd slow command

  [ "$status" -eq 124 ]
  assert_contains "$output" "timeout called: --foreground --kill-after=2s 7 slow command"
  assert_contains "$output" "Command timed out after 7s: slow command"
}

@test "media codec action installs the curated hardware-neutral package set" {
  DRY_RUN=0
  command_log="$TEST_ROOT/media-codec-commands.log"
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
  }

  run install_fedora_media_codecs

  [ "$status" -eq 0 ]
  expected_commands="$(cat <<'EOF'
dnf swap -y ffmpeg-free ffmpeg --allowerasing
dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver
dnf -y mark group multimedia pipewire-codec-aptx
dnf install -y mozilla-openh264
EOF
)"
  assert_equal "$expected_commands" "$(<"$command_log")"
}

@test "media codec action stops and reports a failed DNF transaction" {
  DRY_RUN=0
  command_log="$TEST_ROOT/media-codec-failure-commands.log"
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
    [[ "$*" != "dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver" ]]
  }

  run install_fedora_media_codecs

  [ "$status" -eq 1 ]
  assert_equal "$(cat <<'EOF'
dnf swap -y ffmpeg-free ffmpeg --allowerasing
dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver
EOF
)" "$(<"$command_log")"
}

@test "media codec action stops when aptX group ownership cannot be recorded" {
  DRY_RUN=0
  command_log="$TEST_ROOT/media-codec-aptx-failure-commands.log"
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
    [[ "$*" != "dnf -y mark group multimedia pipewire-codec-aptx" ]]
  }

  run install_fedora_media_codecs

  [ "$status" -eq 1 ]
  assert_equal "$(cat <<'EOF'
dnf swap -y ffmpeg-free ffmpeg --allowerasing
dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver
dnf -y mark group multimedia pipewire-codec-aptx
EOF
)" "$(<"$command_log")"
}

@test "media codec verification checks exact Fedora package names" {
  DRY_RUN=0
  rpm_log="$TEST_ROOT/media-codec-rpm.log"
  rpm() {
    printf '%s\n' "$*" >"$rpm_log"
  }

  run verify_custom_action media-codecs

  [ "$status" -eq 0 ]
  assert_equal \
    "-q ffmpeg ffmpeg-libs gstreamer1-plugin-libav gstreamer1-plugin-openh264 gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly pipewire-codec-aptx mozilla-openh264" \
    "$(<"$rpm_log")"
}

@test "Docker action lets the engine select CLI and containerd dependencies" {
  DRY_RUN=0
  command_log="$TEST_ROOT/docker-commands.log"
  fedora_repo_enabled() {
    return 0
  }
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
  }

  run install_fedora_docker

  [ "$status" -eq 0 ]
  assert_file_contains "$command_log" "dnf install -y docker-ce docker-buildx-plugin docker-compose-plugin"
  refute_file_contains "$command_log" "docker-ce-cli"
  refute_file_contains "$command_log" "containerd.io"
}

@test "Docker verification checks the complete dependency-selected result" {
  DRY_RUN=0
  rpm_log="$TEST_ROOT/docker-rpm.log"
  rpm() {
    printf '%s\n' "$*" >"$rpm_log"
  }

  run verify_custom_action docker

  [ "$status" -eq 0 ]
  assert_equal \
    "-q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" \
    "$(<"$rpm_log")"
}

@test "Discord action installs the validated official x86_64 RPM" {
  DRY_RUN=0
  command_log="$TEST_ROOT/discord-commands.log"
  rpm() {
    if [[ "${1:-}" == "-q" ]]; then
      return 1
    fi
    if [[ "${1:-}" == "-qp" ]]; then
      printf 'discord\tx86_64\n'
      return 0
    fi
    return 1
  }
  run_cmd() {
    printf 'download:%s\n' "$*" >>"$command_log"
    touch "${@: -1}"
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$command_log"
  }

  run install_discord

  [ "$status" -eq 0 ]
  assert_file_contains "$command_log" "download:curl -fsSL $DISCORD_RPM_URL -o $CACHE_DIR/discord."
  assert_file_contains "$command_log" "root:dnf install -y $CACHE_DIR/discord."
}

@test "Discord action rejects a download with unexpected RPM metadata" {
  DRY_RUN=0
  command_log="$TEST_ROOT/discord-invalid-commands.log"
  rpm() {
    if [[ "${1:-}" == "-q" ]]; then
      return 1
    fi
    if [[ "${1:-}" == "-qp" ]]; then
      printf 'unexpected\tx86_64\n'
      return 0
    fi
    return 1
  }
  run_cmd() {
    printf 'download:%s\n' "$*" >>"$command_log"
    touch "${@: -1}"
  }
  run_cmd_as_root() {
    printf 'unexpected root command: %s\n' "$*" >>"$command_log"
  }

  run install_discord

  [ "$status" -eq 1 ]
  assert_contains "$output" "expected discord.x86_64 RPM"
}

@test "JetBrains Toolbox install removes the vendor login autostart entry" {
  DRY_RUN=0
  command_log="$TEST_ROOT/toolbox-install-command.log"
  toolbox_bin="$TARGET_HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
  toolbox_link="$TARGET_HOME/.local/bin/jetbrains-toolbox"
  application_file="$TARGET_HOME/.local/share/applications/jetbrains-toolbox.desktop"
  autostart_file="$TARGET_HOME/.config/autostart/jetbrains-toolbox.desktop"

  run_user_login_shell() {
    printf '%s\n' "$1" >"$command_log"
    mkdir -p "$(dirname "$toolbox_bin")" "$(dirname "$toolbox_link")" \
      "$(dirname "$application_file")" "$(dirname "$autostart_file")"
    touch "$toolbox_bin" "$application_file"
    chmod +x "$toolbox_bin"
    ln -s "$toolbox_bin" "$toolbox_link"
    (sleep 0.2 && touch "$autostart_file") &
  }

  run install_jetbrains_toolbox

  [ "$status" -eq 0 ]
  [[ -x "$toolbox_bin" ]]
  [[ ! -e "$autostart_file" ]]
  assert_file_contains "$command_log" "nohup"
}

@test "JetBrains Toolbox install rerun removes an existing login autostart entry" {
  DRY_RUN=0
  toolbox_bin="$TARGET_HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
  autostart_file="$TARGET_HOME/.config/autostart/jetbrains-toolbox.desktop"
  mkdir -p "$(dirname "$toolbox_bin")" "$(dirname "$autostart_file")"
  touch "$toolbox_bin" "$autostart_file"
  chmod +x "$toolbox_bin"
  run_user_login_shell() {
    printf 'unexpected Toolbox relaunch\n' >&2
    return 1
  }

  run install_jetbrains_toolbox

  [ "$status" -eq 0 ]
  [[ ! -e "$autostart_file" ]]
  refute_contains "$output" "unexpected Toolbox relaunch"
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
  run install_fedora_noctalia_greeter

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

  run install_fedora_noctalia_greeter

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
  enable_required_system_service_now() {
    printf 'service:%s\n' "$1"
  }

  capture_without_bats_debug_trap output status module_30_packages

  [ "$status" -ne 0 ]
  grep -F 'install:dnf:' <<<"$output" | grep -F ' niri ' >/dev/null
}

@test "required install verification reports missing native packages" {
  plan_file="$TEST_ROOT/verify-native.pkgs"
  printf 'missing-native-package\n' >"$plan_file"
  VERIFY_INSTALLS=1
  DRY_RUN=0
  fedora_package_installed() {
    return 1
  }

  run verify_plan_entries dnf "$plan_file" "base packages" required

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

  run fedora_package_installed nodejs

  [ "$status" -eq 0 ]
}
