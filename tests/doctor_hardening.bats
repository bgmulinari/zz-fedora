#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "installer lock ignores stale lock-file contents and releases cleanly" {
  mkdir -p "$(dirname "$LOCK_FILE")"
  printf '999999\n' >"$LOCK_FILE"

  acquire_lock
  assert_equal "1" "$LOCK_ACQUIRED"
  release_lock
  assert_equal "0" "$LOCK_ACQUIRED"

  acquire_lock
  assert_equal "1" "$LOCK_ACQUIRED"
  release_lock
}

@test "check command reports readiness without saving selections" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/install.sh" check --dry-run --no-tui

  [ "$status" -eq 0 ]
  assert_contains "$output" "Readiness:"
  assert_contains "$output" "dms command:dms"
  assert_contains "$output" "managed-config ~/.config/autostart/zz-first-run.desktop: first-run"
  assert_contains "$output" "Fatal readiness issues:"
  assert_contains "$output" "package-manager "
  [[ ! -e "$XDG_CONFIG_HOME/zz-fedora/selections.conf" ]]
}

@test "wizard confirmation omits full readiness report before proceed prompt" {
  COMMAND=wizard
  ASSUME_YES=0

  generate_readiness_status() { printf 'generated-readiness\n'; }
  tui_show_install_plan() { printf 'install-plan\n'; }
  render_readiness_report() { printf 'full-readiness-report\n'; }
  tui_confirm() {
    printf 'confirm:%s\n' "$1"
    return 1
  }

  run module_20_plan

  [ "$status" -eq 0 ]
  assert_contains "$output" "generated-readiness"
  assert_contains "$output" "install-plan"
  assert_contains "$output" "confirm:Proceed with this install plan?"
  assert_contains "$output" "Install cancelled."
  refute_contains "$output" "full-readiness-report"
}

@test "install planning still renders readiness report" {
  COMMAND=install
  ASSUME_YES=0

  generate_readiness_status() { printf 'generated-readiness\n'; }
  tui_show_install_plan() { printf 'install-plan\n'; }
  render_readiness_report() { printf 'full-readiness-report\n'; }
  tui_confirm() { printf 'unexpected-confirm\n'; }

  run module_20_plan

  [ "$status" -eq 0 ]
  assert_contains "$output" "generated-readiness"
  assert_contains "$output" "install-plan"
  assert_contains "$output" "full-readiness-report"
  refute_contains "$output" "unexpected-confirm"
}

step_table_failure_policy() {
  local wanted_step_id="$1"
  local raw row step_id label function_name predicate failure_policy description
  local -a rows=()
  mapfile -t rows < <(sed -n '/^declare -ag INSTALL_STEP_TABLE=(/,/^)/p' "$ROOT_DIR/install.sh" | sed '1d;$d')
  for raw in "${rows[@]}"; do
    raw="${raw#"${raw%%[![:space:]]*}"}"
    eval "row=${raw}"
    IFS=$'\t' read -r step_id label function_name predicate failure_policy description <<<"$row"
    if [[ "$step_id" == "$wanted_step_id" ]]; then
      printf '%s\n' "$failure_policy"
      return 0
    fi
  done
  return 1
}

@test "installer step registry marks base fatal and optional package failures continuable" {
  assert_equal "fatal" "$(step_table_failure_policy base-setup)"
  assert_equal "continue" "$(step_table_failure_policy optional-packages)"
  assert_file_contains "$ROOT_DIR/install.sh" 'root_env+=("$optional_env=${!optional_env}")'
  refute_file_contains "$ROOT_DIR/install.sh" '"DISPLAY=${DISPLAY:-}"'
}

@test "base responsibility and managed config policy include critical rationale rows" {
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tbash-completion\tshell-tool\tinteractive Bash\tProvides command completions for the persistent Bash shell environment.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tbats\tdevelopment-tool\trepository regression suite\tKeeps the repository\'s Bats test suites runnable out of the box on the development-focused desktop.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tdnf5-plugins\tinstaller-bootstrap\tFedora source setup and installer reruns\tProvides the DNF5 COPR and config-manager commands used during source setup.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tnss-tools\tinstaller-bootstrap\tbrowser certificate trust\tProvides certutil for importing development CAs into Firefox-style browser profiles.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tddcutil\tdms\texternal display brightness\tShips the i2c udev rules that grant the /dev/i2c-* access DMS\'s native DDC/CI brightness control needs, plus the debugging CLI.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tpavucontrol\tdefault-app\taudio mixer\tProvides a GUI mixer fallback for standalone Niri sessions.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'source\tcopr:avengemedia/danklinux\tdesktop-service\tDMS ecosystem and Qt theme\tProvides quickshell, matugen, danksearch, DMS Greeter, and qt6ct-kde for the required base desktop.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'action\tdms-greeter\tdesktop-service\tgraphical login\tInstalls DMS Greeter from COPR, ensures the greetd session config, grants the greeter user read access to the target user\'s DMS theme state, and enables the fallback graphical login.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'action\tdesktop-cursor-theme\ttheme-font\tNiri and graphical applications\tInstalls the pinned cursor theme selected by the managed Niri and desktop environment defaults.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tpolicycoreutils-python-utils\tdesktop-service\tgraphical login\tProvides the SELinux policy tooling the DMS Greeter package scriptlets use for its binary and state-directory contexts.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tdms\tdms\tDMS shell\tInstalls the DMS (DankMaterialShell) desktop shell started by the dms.service user unit under the Niri session.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'source\tterra\tdefault-app\tGhostty\tBootstraps Terra release packages for required Ghostty packages.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tghostty-shell-integration\tdefault-app\tterminal shell integration\tProvides Ghostty shell integration scripts for working-directory reporting, prompt marking, and shell-aware terminal behavior.'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.config/ghostty/themes/dankcolors\tseed-if-missing\tpreserve'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.config/niri/dms/colors.kdl\tseed-if-missing\tpreserve\ttemplates/niri/dms-colors.kdl'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.config/DankMaterialShell/settings.json\tseed-if-missing\tpreserve\t-\tdms'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.local/state/DankMaterialShell/session.json\tseed-if-missing\tpreserve\t-\tdms'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.config/DankMaterialShell/themes/catppuccin/theme.json\tproduct-link\tbackup-before-link\t'
}

@test "managed config conflicts and base rationale are generated in plan" {
  TARGET_HOME="$TEST_ROOT/home"
  mkdir -p "$TARGET_HOME/.config/ghostty"
  printf 'existing defaults\n' >"$TARGET_HOME/.config/ghostty/zz-defaults"

  ZZ_TEST_CONFLICT_PREVIEW=1
  build_test_plan

  assert_file_contains "$PLAN_DIR/files/config-conflicts.tsv" "~/.config/ghostty/zz-defaults"
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'flatpak\torg.gtk.Gtk3theme.adw-gtk3\tbase-source-flathub\ttheme-font'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'source\tcopr:avengemedia/danklinux\tbase-login-manager\tdesktop-service'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'action\tdms-greeter\tbase-login-manager\tdesktop-service'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'dnf\tdms\tbase-dms\tdms'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.bashrc\tseed-if-missing\tpreserve\tshell'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.config/ghostty/themes/dankcolors\tseed-if-missing\tpreserve\tghostty'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.config/DankMaterialShell/settings.json\tseed-if-missing\tpreserve\tdms'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.config/DankMaterialShell/themes/catppuccin/theme.json\tproduct-link\tbackup-before-link\tdms'
}

@test "readiness treats handled backup-before-link conflicts as informational" {
  TARGET_HOME="$TEST_ROOT/home"
  mkdir -p "$TARGET_HOME/.config/ghostty"
  printf 'existing defaults\n' >"$TARGET_HOME/.config/ghostty/zz-defaults"

  ZZ_TEST_CONFLICT_PREVIEW=1
  build_test_plan
  run_without_bats_debug_trap generate_readiness_status

  assert_file_contains "$(readiness_file)" $'config-conflict\t~/.config/ghostty/zz-defaults\tplanned-backup\tinfo\tghostty:backup-before-link'
  refute_file_contains "$(readiness_file)" $'config-conflict\t~/.config/ghostty/zz-defaults\tconflict\twarn'
}

@test "readiness grades session-bound wanted units by their wants symlink, never fatal" {
  TARGET_HOME="$TEST_ROOT/wants-home"
  mkdir -p "$TARGET_HOME"
  build_test_plan
  DRY_RUN=0
  COMMAND=doctor

  # The binding is applied at first login, so its absence is a warning on a
  # healthy pre-first-login system; a system-scope is-enabled would report
  # the user unit missing and had graded it fatal.
  run_without_bats_debug_trap readiness_reset
  run_without_bats_debug_trap readiness_generate_services
  assert_file_contains "$(readiness_file)" $'service\tdms.service\tmissing\twarn\twanted by niri.service'
  refute_file_contains "$(readiness_file)" $'service\tdms.service\tmissing\tfatal'

  mkdir -p "$TARGET_HOME/.config/systemd/user/niri.service.wants"
  ln -sfn /usr/lib/systemd/user/dms.service \
    "$TARGET_HOME/.config/systemd/user/niri.service.wants/dms.service"
  run_without_bats_debug_trap readiness_reset
  run_without_bats_debug_trap readiness_generate_services
  assert_file_contains "$(readiness_file)" $'service\tdms.service\tbound\tinfo\twanted by niri.service'
}

@test "doctor accepts globally enabled user services" {
  systemctl() {
    if [[ "$1" == "--user" && "$2" == "is-enabled" ]]; then
      return 1
    fi
    [[ "$1" == "--global" && "$2" == "is-enabled" && "$3" == "app-com.mitchellh.ghostty.service" ]]
  }

  run doctor_check_user_enabled app-com.mitchellh.ghostty.service

  [ "$status" -eq 0 ]
  assert_contains "$output" "user service enabled app-com.mitchellh.ghostty.service"
}

@test "doctor fails and identifies failed system units" {
  build_test_plan
  COMMAND=doctor
  DRY_RUN=0

  doctor_check_command() {
    printf '[ok] command %s\n' "$1"
  }
  doctor_check_file() {
    printf '[ok] file %s\n' "$1"
  }
  doctor_check_contains() {
    printf '[ok] %s contains %s\n' "$1" "$2"
  }
  doctor_check_dir_has_files() {
    printf '[ok] directory %s has %s\n' "$1" "$2"
  }
  doctor_check_user_enabled() {
    return 0
  }
  detect_enabled_display_manager() {
    printf 'gdm.service\n'
  }
  systemctl() {
    if [[ "$1" == "list-units" ]]; then
      printf 'foomaticrip-upgrade.service loaded failed failed Allowing already installed printers\n'
      return 0
    fi
    [[ "$1" == "is-enabled" ]]
  }
  run_cmd_as_root() {
    return 0
  }

  capture_without_bats_debug_trap output status module_90_doctor

  [ "$status" -ne 0 ]
  assert_contains "$output" "failed system units detected"
  assert_contains "$output" "foomaticrip-upgrade.service"
  assert_contains "$output" "Fatal desktop readiness checks failed: 1"
}

@test "doctor infers the portal service from a selected backend" {
  native_plan="$TEST_ROOT/native.pkgs"
  printf 'xdg-desktop-portal-gtk\n' >"$native_plan"

  run doctor_portal_planned "$native_plan"

  [ "$status" -eq 0 ]
}

@test "doctor fails when planned Niri desktop readiness is missing" {
  build_test_plan
  COMMAND=doctor
  DRY_RUN=0

  doctor_check_command() {
    if [[ "$1" == "niri" ]]; then
      printf '[warn] missing command %s\n' "$1"
      return 1
    fi
    command -v "$1" >/dev/null 2>&1
  }
  doctor_check_file() {
    if [[ "$1" == "/usr/share/wayland-sessions/niri.desktop" ]]; then
      printf '[warn] missing file %s\n' "$1"
      return 1
    fi
    [[ -f "$1" ]]
  }
  systemctl() {
    [[ "$1" == "is-enabled" && "$2" != "greetd" ]]
  }
  detect_enabled_display_manager() {
    return 1
  }
  run_cmd_as_root() {
    return 0
  }

  capture_without_bats_debug_trap output status module_90_doctor

  [ "$status" -ne 0 ]
  assert_contains "$output" "missing command niri"
  assert_contains "$output" "missing file /usr/share/wayland-sessions/niri.desktop"
  assert_contains "$output" "service not enabled greetd"
  assert_contains "$output" "Fatal desktop readiness checks failed"
}

@test "doctor accepts an existing display manager when DMS Greeter is planned" {
  build_test_plan
  COMMAND=doctor
  DRY_RUN=0

  output="$({
    doctor_check_command() {
      printf '[ok] command %s\n' "$1"
    }
    doctor_check_file() {
      printf '[ok] file %s\n' "$1"
    }
    doctor_check_contains() {
      printf '[ok] %s contains %s\n' "$1" "$2"
    }
    doctor_check_dir_has_files() {
      printf '[ok] directory %s has %s\n' "$1" "$2"
    }
    detect_enabled_display_manager() {
      printf 'gdm.service\n'
    }
    systemctl() {
      [[ "$1" == "is-enabled" && "$2" != "greetd" ]]
    }
    run_cmd_as_root() {
      printf 'cmd:%s\n' "$*"
    }
    module_90_doctor
  } 2>&1)"

  assert_contains "$output" "[ok] existing display manager gdm.service"
  assert_contains "$output" "[ok] file $TARGET_HOME/.config/niri/config.kdl"
  assert_contains "$output" "[ok] file $ROOT_DIR/dotfiles/niri/.config/niri/defaults.kdl"
  assert_contains "$output" "[ok] file $ROOT_DIR/dotfiles/niri/.config/niri/cfg/autostart.kdl"
  assert_contains "$output" "[ok] file /usr/lib/environment.d/10-zz-desktop.conf"
  refute_contains "$output" "service not enabled greetd"
  refute_contains "$output" "Fatal desktop readiness checks failed"
  assert_contains "$output" "Reboot, open your display manager, and choose the Niri session."
}

@test "doctor accepts skipped pre-existing greetd display manager" {
  build_test_plan
  COMMAND=doctor
  DRY_RUN=0
  record_system_skip action dms-greeter "existing display manager: greetd.service"

  output="$({
    doctor_check_command() {
      if [[ "$1" == dms-greeter* ]]; then
        printf '[warn] missing command %s\n' "$1"
        return 1
      fi
      printf '[ok] command %s\n' "$1"
    }
    doctor_check_file() {
      printf '[ok] file %s\n' "$1"
    }
    doctor_check_contains() {
      printf '[ok] %s contains %s\n' "$1" "$2"
    }
    doctor_check_dir_has_files() {
      printf '[ok] directory %s has %s\n' "$1" "$2"
    }
    detect_enabled_display_manager() {
      printf 'greetd.service\n'
    }
    systemctl() {
      [[ "$1" == "is-enabled" && "$2" == "greetd" ]]
    }
    run_cmd_as_root() {
      printf 'cmd:%s\n' "$*"
    }
    module_90_doctor
  } 2>&1)"

  assert_contains "$output" "[ok] existing display manager greetd.service"
  refute_contains "$output" "missing command dms-greeter"
  refute_contains "$output" "Fatal desktop readiness checks failed"
  assert_contains "$output" "Reboot, open your display manager, and choose the Niri session."
}

@test "doctor fails when managed greetd config does not use DMS Greeter" {
  build_test_plan
  COMMAND=doctor
  DRY_RUN=0
  DMS_GREETD_CONFIG="$TEST_ROOT/greetd-config.toml"
  printf '[default_session]\ncommand = "agreety --cmd niri"\n' >"$DMS_GREETD_CONFIG"

  set +e
  output="$({
    command() {
      if [[ "$1" == "-v" ]]; then
        return 0
      fi
      builtin command "$@"
    }
    doctor_check_command() {
      printf '[ok] command %s\n' "$1"
    }
    doctor_check_file() {
      printf '[ok] file %s\n' "$1"
    }
    doctor_check_contains() {
      printf '[ok] %s contains %s\n' "$1" "$2"
    }
    doctor_check_dir_has_files() {
      printf '[ok] directory %s has %s\n' "$1" "$2"
    }
    detect_enabled_display_manager() {
      printf 'greetd.service\n'
    }
    systemctl() {
      [[ "$1" == "is-enabled" ]]
    }
    run_cmd_as_root() {
      printf 'cmd:%s\n' "$*"
    }
    module_90_doctor
  } 2>&1)"
  status=$?
  set -e

  [ "$status" -ne 0 ]
  assert_contains "$output" "$DMS_GREETD_CONFIG missing pattern dms-greeter"
  assert_contains "$output" "Fatal desktop readiness checks failed"
}

@test "doctor greeter setup passes on a managed greetd config and warns on sync state" {
  DMS_GREETD_CONFIG="$TEST_ROOT/greetd-config.toml"
  printf '[default_session]\ncommand = "/usr/bin/dms-greeter --command niri"\nuser = "greeter"\n' >"$DMS_GREETD_CONFIG"
  doctor_check_command() { return 0; }
  doctor_check_file() {
    printf '[ok] file %s\n' "$1"
  }

  run doctor_check_dms_greeter_setup

  [ "$status" -eq 0 ]
  assert_contains "$output" "/var/cache/dms-greeter/settings.json"
  assert_contains "$output" "/var/cache/dms-greeter/colors.json"
}
