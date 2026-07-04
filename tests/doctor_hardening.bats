#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
  DISTRO=fedora
  load_adapter
}

@test "check command reports readiness without saving selections" {
  run env XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/install.sh" check --distro fedora --dry-run --no-tui

  [ "$status" -eq 0 ]
  assert_contains "$output" "Readiness:"
  assert_contains "$output" "noctalia-v5 command:noctalia"
  assert_contains "$output" "managed-config ~/.config/autostart/zz-first-run.desktop: first-run"
  assert_contains "$output" "Fatal readiness issues:"
  assert_contains "$output" "package-manager locks"
  [[ ! -e "$XDG_CONFIG_HOME/zz-linux-setup/selections.conf" ]]
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

@test "installer step registry marks base fatal and optional package failures continuable" {
  assert_file_contains "$ROOT_DIR/install.sh" "register_step base-setup"
  grep -F "register_step base-setup" "$ROOT_DIR/install.sh" | grep -F " fatal" >/dev/null
  grep -F "register_step optional-packages" "$ROOT_DIR/install.sh" | grep -F " continue" >/dev/null
  assert_file_contains "$ROOT_DIR/install.sh" 'root_env+=("$optional_env=${!optional_env}")'
  refute_file_contains "$ROOT_DIR/install.sh" '"DISPLAY=${DISPLAY:-}"'
}

@test "base responsibility and managed config policy include critical rationale rows" {
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tbats\tinstaller-bootstrap\ttest-runner\tProvides the Bats test runner used by the repository regression suite.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tnss-tools\tinstaller-bootstrap\tbrowser certificate trust\tProvides certutil for importing development CAs into Firefox-style browser profiles.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tgnome-software\tdefault-app\tapp discovery\tProvides a GUI software browsing/update front end.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'dnf\tddcutil\tdesktop-service\texternal monitor brightness\tControls DDC/CI-capable external displays.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'source\tcopr:lionheartp/Hyprland\tnoctalia\tNoctalia v5 shell and greeter\tProvides Noctalia v5 and Noctalia Greeter for the required base desktop.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'action\tnoctalia-greeter-fedora\tdesktop-service\tgraphical login\tInstalls Noctalia Greeter from COPR, configures greetd, and enables the fallback graphical login.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'action\tnoctalia-v5-fedora\tnoctalia\tNoctalia v5 shell\tInstalls the COPR native shell binary launched by Niri autostart.'
  assert_tsv_row "$ROOT_DIR/config/base-responsibility.tsv" $'source\tterra\tdefault-app\tGhostty\tBootstraps Terra release packages for required Ghostty packages.'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.config/niri/cfg/display.kdl\tseed-if-missing\tpreserve'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.config/ghostty/themes/noctalia\tseed-if-missing\tpreserve'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.config/noctalia/config.toml\tstow\tbackup-before-stow\tnoctalia'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.config/noctalia/templates/icon-theme-accent\tstow\tbackup-before-stow\tnoctalia-icon-theme'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" $'~/.local/bin/noctalia-sync-icon-theme\tstow\tbackup-before-stow\tnoctalia-icon-theme'
  assert_file_contains "$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml" "[shell.greeter_sync]"
  assert_file_contains "$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml" "auto_sync = true"
}

@test "managed config conflicts and base rationale are generated in plan" {
  TARGET_HOME="$TEST_ROOT/home"
  mkdir -p "$TARGET_HOME/.config/niri"
  printf 'existing shell\n' >"$TARGET_HOME/.bashrc"

  ZZ_TEST_CONFLICT_PREVIEW=1
  build_fedora_plan

  assert_file_contains "$PLAN_DIR/files/config-conflicts.tsv" "~/.bashrc"
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'flatpak\torg.gtk.Gtk3theme.adw-gtk3\tbase-source-flathub\ttheme-font'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'source\tcopr:lionheartp/Hyprland\tbase-login-manager\tnoctalia'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'action\tnoctalia-greeter-fedora\tbase-login-manager\tdesktop-service'
  assert_file_contains "$PLAN_DIR/base-rationale.tsv" $'action\tnoctalia-v5-fedora\tbase-noctalia\tnoctalia'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.bashrc\tstow\tbackup-before-stow\tshell'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.config/niri/cfg/display.kdl\tseed-if-missing\tpreserve\tniri-display'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.config/ghostty/themes/noctalia\tseed-if-missing\tpreserve\tghostty-theme'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.config/noctalia/config.toml\tstow\tbackup-before-stow\tnoctalia'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.config/noctalia/templates/icon-theme-accent\tstow\tbackup-before-stow\tnoctalia-icon-theme'
  assert_file_contains "$PLAN_DIR/files/managed-config-policy.tsv" $'~/.local/bin/noctalia-sync-icon-theme\tstow\tbackup-before-stow\tnoctalia-icon-theme'
}

@test "doctor fails when planned Niri desktop readiness is missing" {
  build_fedora_plan
  COMMAND=doctor
  DRY_RUN=0

  set +e
  output="$({
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
    module_90_doctor
  } 2>&1)"
  status=$?
  set -e

  [ "$status" -ne 0 ]
  assert_contains "$output" "missing command niri"
  assert_contains "$output" "missing file /usr/share/wayland-sessions/niri.desktop"
  assert_contains "$output" "service not enabled greetd"
  assert_contains "$output" "Fatal desktop readiness checks failed"
}

@test "doctor accepts an existing display manager when Noctalia Greeter is planned" {
  build_fedora_plan
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
  refute_contains "$output" "service not enabled greetd"
  refute_contains "$output" "Fatal desktop readiness checks failed"
  assert_contains "$output" "Reboot, open your display manager, and choose the Niri session."
}

@test "doctor accepts skipped pre-existing greetd display manager" {
  build_fedora_plan
  COMMAND=doctor
  DRY_RUN=0
  record_system_skip action noctalia-greeter-fedora "existing display manager: greetd.service"

  output="$({
    doctor_check_command() {
      if [[ "$1" == noctalia-greeter* ]]; then
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
  refute_contains "$output" "missing command noctalia-greeter"
  refute_contains "$output" "Fatal desktop readiness checks failed"
  assert_contains "$output" "Reboot, open your display manager, and choose the Niri session."
}

@test "doctor fails when managed greetd config does not use Noctalia Greeter" {
  build_fedora_plan
  COMMAND=doctor
  DRY_RUN=0
  NOCTALIA_GREETD_CONFIG="$TEST_ROOT/greetd-config.toml"
  printf '[default_session]\ncommand = "agreety --cmd niri"\n' >"$NOCTALIA_GREETD_CONFIG"

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
  assert_contains "$output" "$NOCTALIA_GREETD_CONFIG missing pattern noctalia-greeter-session"
  assert_contains "$output" "Fatal desktop readiness checks failed"
}
