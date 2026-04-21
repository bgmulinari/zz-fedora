#!/usr/bin/env bash
set -Eeuo pipefail

doctor_check_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '[ok] command %s\n' "$cmd"
  else
    printf '[warn] missing command %s\n' "$cmd"
  fi
}

doctor_check_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    printf '[ok] file %s\n' "$file"
  else
    printf '[warn] missing file %s\n' "$file"
  fi
}

doctor_check_contains() {
  local file="$1"
  local pattern="$2"
  if [[ -f "$file" ]] && grep -F "$pattern" "$file" >/dev/null 2>&1; then
    printf '[ok] %s contains %s\n' "$file" "$pattern"
  else
    printf '[warn] %s missing pattern %s\n' "$file" "$pattern"
  fi
}

doctor_check_enabled() {
  local service_name="$1"
  if systemctl is-enabled "$service_name" >/dev/null 2>&1; then
    printf '[ok] service enabled %s\n' "$service_name"
  else
    printf '[warn] service not enabled %s\n' "$service_name"
  fi
}

doctor_plan_has_entry() {
  local plan_file="$1"
  local entry="$2"
  [[ -f "$plan_file" ]] || return 1
  grep -Fx "$entry" "$plan_file" >/dev/null 2>&1
}

module_90_doctor() {
  if [[ "$COMMAND" != "doctor" && "$DRY_RUN" -eq 1 ]]; then
    printf 'Doctor skipped in dry-run mode.\n'
    return 0
  fi

  doctor_check_command niri
  doctor_check_command niri-session
  doctor_check_command qs
  doctor_check_command ghostty
  doctor_check_command dolphin
  doctor_check_command kwrite
  doctor_check_command fuzzel
  doctor_check_command xdg-desktop-portal
  doctor_check_command gum

  local user_config_home="$TARGET_HOME/.config"
  doctor_check_file "$user_config_home/niri/config.kdl"
  doctor_check_file "$user_config_home/xdg-desktop-portal/niri-portals.conf"
  doctor_check_file "$user_config_home/environment.d/10-niri-kde-qt.conf"
  doctor_check_file "$user_config_home/ghostty/config"
  doctor_check_file "$user_config_home/qt6ct/qt6ct.conf"
  doctor_check_file "$user_config_home/kdeglobals"

  doctor_check_contains "$user_config_home/niri/config.kdl" 'spawn-at-startup "qs" "-c" "noctalia-shell"'
  doctor_check_contains "$user_config_home/niri/config.kdl" 'spawn "ghostty"'
  doctor_check_contains "$user_config_home/niri/config.kdl" 'spawn "dolphin"'

  if doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "zsh"; then
    doctor_check_command zsh
    doctor_check_file "$TARGET_HOME/.zshrc"
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/copr.pkgs" "starship" || doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "starship"; then
    doctor_check_command starship
    doctor_check_file "$user_config_home/starship.toml"
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "zoxide"; then
    doctor_check_command zoxide
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "fastfetch"; then
    doctor_check_command fastfetch
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "gh" || doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "github-cli"; then
    doctor_check_command gh
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "btop"; then
    doctor_check_command btop
    doctor_check_file "$user_config_home/btop/btop.conf"
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "fd-find"; then
    doctor_check_command fdfind
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "fd"; then
    doctor_check_command fd
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "fzf"; then
    doctor_check_command fzf
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "bat"; then
    doctor_check_command bat
  fi
  if doctor_plan_has_entry "$PLAN_DIR/packages/copr.pkgs" "yazi" || doctor_plan_has_entry "$PLAN_DIR/packages/official.pkgs" "yazi"; then
    doctor_check_command yazi
  fi

  doctor_check_enabled NetworkManager
  doctor_check_enabled greetd
  doctor_check_enabled bluetooth
  doctor_check_enabled firewalld
  doctor_check_enabled chronyd
  doctor_check_enabled power-profiles-daemon

  case "$DISTRO" in
    fedora)
      run_cmd sudo dnf copr list || true
      run_cmd sudo dnf repolist || true
      run_cmd sudo dnf repoquery --whatprovides PolicyKit-authentication-agent || true
      run_cmd sudo dnf repoquery --whatprovides desktop-notification-daemon || true
      ;;
    arch)
      run_cmd pacman -Qs xdg-desktop-portal || true
      run_cmd pacman -Qs polkit || true
      ;;
  esac

  printf 'Doctor completed.\n'
  printf 'Warnings are not necessarily fatal.\n'
  printf 'Reboot and log into niri-session through greetd.\n'
}
