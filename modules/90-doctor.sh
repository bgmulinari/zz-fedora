#!/usr/bin/env bash
set -Eeuo pipefail

doctor_check_command() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '[ok] command %s\n' "$cmd"
    return 0
  else
    printf '[warn] missing command %s\n' "$cmd"
    return 1
  fi
}

doctor_check_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    printf '[ok] file %s\n' "$file"
    return 0
  else
    printf '[warn] missing file %s\n' "$file"
    return 1
  fi
}

doctor_check_dir_has_files() {
  local dir="$1"
  local pattern="$2"
  if [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -type f -name "$pattern" -print -quit | grep -q .; then
    printf '[ok] directory %s has %s\n' "$dir" "$pattern"
  else
    printf '[warn] directory %s missing %s\n' "$dir" "$pattern"
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
    return 0
  else
    printf '[warn] service not enabled %s\n' "$service_name"
    return 1
  fi
}

doctor_check_user_enabled() {
  local service_name="$1"
  if systemctl --user is-enabled "$service_name" >/dev/null 2>&1; then
    printf '[ok] user service enabled %s\n' "$service_name"
    return 0
  else
    printf '[warn] user service not enabled %s\n' "$service_name"
    return 1
  fi
}

doctor_warn_command() {
  doctor_check_command "$1" || true
}

doctor_warn_file() {
  doctor_check_file "$1" || true
}

doctor_warn_enabled() {
  doctor_check_enabled "$1" || true
}

doctor_warn_user_enabled() {
  doctor_check_user_enabled "$1" || true
}

doctor_plan_has_entry() {
  local plan_file="$1"
  local entry="$2"
  [[ -f "$plan_file" ]] || return 1
  grep -Fx "$entry" "$plan_file" >/dev/null 2>&1
}

doctor_noctalia_planned() {
  local native_plan="$1"
  local action_plan
  doctor_plan_has_entry "$native_plan" "noctalia-git" && return 0
  action_plan="$(package_file_for_backend action)"
  doctor_plan_has_entry "$action_plan" "noctalia-v5-fedora"
}

module_90_doctor() {
  if [[ "$COMMAND" != "doctor" && "$DRY_RUN" -eq 1 ]]; then
    printf 'Doctor skipped in dry-run mode.\n'
    return 0
  fi

  local native_plan
  local native_backend
  native_backend="$(native_backend_for_distro "$DISTRO")"
  native_plan="$(package_file_for_backend "$native_backend")"

  if doctor_plan_has_entry "$native_plan" "niri"; then
    doctor_warn_command niri
    doctor_warn_command niri-session
  fi
  if doctor_noctalia_planned "$native_plan"; then
    doctor_warn_command noctalia
  fi
  if doctor_plan_has_entry "$native_plan" "ghostty"; then
    doctor_warn_command ghostty
    doctor_warn_user_enabled app-com.mitchellh.ghostty.service
  fi
  doctor_plan_has_entry "$native_plan" "xdg-terminal-exec" && doctor_warn_command xdg-terminal-exec
  doctor_plan_has_entry "$native_plan" "nautilus" && doctor_warn_command nautilus
  if doctor_plan_has_entry "$native_plan" "neovim" || doctor_plan_has_entry "$native_plan" "nvim"; then
    doctor_warn_command nvim
  fi
  doctor_plan_has_entry "$native_plan" "evince" && doctor_warn_command evince
  doctor_warn_command gum
  doctor_plan_has_entry "$native_plan" "mpv" && doctor_warn_command mpv
  doctor_plan_has_entry "$native_plan" "pavucontrol" && doctor_warn_command pavucontrol
  doctor_plan_has_entry "$native_plan" "system-config-printer" && doctor_warn_command system-config-printer
  doctor_plan_has_entry "$native_plan" "simple-scan" && doctor_warn_command simple-scan

  local user_config_home="$TARGET_HOME/.config"
  local niri_config_home="$user_config_home/niri"
  if doctor_plan_has_entry "$native_plan" "niri"; then
    doctor_warn_file "$user_config_home/niri/config.kdl"
    doctor_warn_file "$niri_config_home/cfg/autostart.kdl"
    doctor_warn_file "$niri_config_home/cfg/keybinds.kdl"
    doctor_warn_file "$niri_config_home/cfg/misc.kdl"
    doctor_warn_file "$user_config_home/environment.d/10-niri-gtk.conf"
    doctor_warn_file "$user_config_home/niri/noctalia.kdl"
  fi
  if doctor_plan_has_entry "$native_plan" "xdg-desktop-portal"; then
    doctor_warn_file "$user_config_home/xdg-desktop-portal/niri-portals.conf"
  fi
  doctor_warn_file "$user_config_home/xdg-terminals.list"
  doctor_plan_has_entry "$native_plan" "ghostty" && doctor_warn_file "$user_config_home/ghostty/config"
  doctor_plan_has_entry "$native_plan" "ghostty" && doctor_warn_file "$user_config_home/ghostty/themes/noctalia"
  if doctor_plan_has_entry "$native_plan" "qt5ct" || doctor_plan_has_entry "$native_plan" "qt6ct" || doctor_plan_has_entry "$native_plan" "qt6ct-kde"; then
    doctor_warn_file "$user_config_home/qt5ct/qt5ct.conf"
    doctor_warn_file "$user_config_home/qt6ct/qt6ct.conf"
    doctor_warn_file "$user_config_home/kdeglobals"
  fi
  if doctor_plan_has_entry "$native_plan" "code" || doctor_plan_has_entry "$native_plan" "codium" || doctor_plan_has_entry "$native_plan" "code-insiders" || doctor_plan_has_entry "$native_plan" "vscodium"; then
    doctor_warn_file "$user_config_home/Code/User/settings.json"
  fi
  doctor_warn_file "$TARGET_HOME/.local/share/applications/nvim.desktop"
  doctor_plan_has_entry "$native_plan" "nautilus-python" && doctor_warn_file "$TARGET_HOME/.local/share/nautilus-python/extensions/open-terminal-here.py"
  doctor_warn_file "$TARGET_HOME/Wallpapers/BlueTide.jpg"
  if doctor_noctalia_planned "$native_plan"; then
    doctor_warn_file "$user_config_home/noctalia/config.toml"
    doctor_warn_file "$user_config_home/noctalia/templates/icon-theme-accent"
    doctor_warn_file "$TARGET_HOME/.local/bin/noctalia-sync-icon-theme"
  fi
  if [[ "$DISTRO" == "fedora" ]]; then
    doctor_check_dir_has_files "$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerdFont" '*.ttf'
  fi

  if doctor_plan_has_entry "$native_plan" "niri"; then
    doctor_check_contains "$niri_config_home/cfg/autostart.kdl" 'spawn-at-startup "noctalia"'
    doctor_check_contains "$niri_config_home/cfg/keybinds.kdl" 'noctalia msg panel-toggle launcher'
    doctor_check_contains "$niri_config_home/cfg/keybinds.kdl" 'spawn "ghostty" "+new-window"'
    doctor_check_contains "$niri_config_home/config.kdl" 'include "./noctalia.kdl"'
    doctor_check_contains "$user_config_home/environment.d/10-niri-gtk.conf" 'TERMINAL=xdg-terminal-exec'
    doctor_check_contains "$user_config_home/environment.d/10-niri-gtk.conf" 'EDITOR=nvim'
    if doctor_plan_has_entry "$native_plan" "nautilus"; then
      doctor_check_contains "$niri_config_home/cfg/keybinds.kdl" 'spawn "nautilus"'
    fi
    if doctor_plan_has_entry "$native_plan" "qt5ct" || doctor_plan_has_entry "$native_plan" "qt6ct" || doctor_plan_has_entry "$native_plan" "qt6ct-kde"; then
      doctor_check_contains "$user_config_home/environment.d/10-niri-gtk.conf" 'QT_QPA_PLATFORMTHEME=qt6ct'
    fi
  fi
  if doctor_plan_has_entry "$native_plan" "ghostty"; then
    doctor_check_contains "$user_config_home/ghostty/config" 'quit-after-last-window-closed = false'
    doctor_check_contains "$user_config_home/ghostty/config" 'theme = noctalia'
  fi
  if doctor_noctalia_planned "$native_plan"; then
    doctor_check_contains "$user_config_home/noctalia/config.toml" '[theme.templates.user.icon_theme]'
    doctor_check_contains "$user_config_home/noctalia/templates/icon-theme-accent" '{{ colors.primary.default.hex }}'
    doctor_check_contains "$TARGET_HOME/.local/bin/noctalia-sync-icon-theme" 'QS_ICON_THEME='
  fi
  if doctor_plan_has_entry "$native_plan" "xdg-terminal-exec"; then
    doctor_check_contains "$user_config_home/xdg-terminals.list" 'Alacritty.desktop'
    doctor_check_contains "$TARGET_HOME/.local/share/applications/nvim.desktop" 'Exec=xdg-terminal-exec'
  fi
  if doctor_plan_has_entry "$native_plan" "nautilus-python"; then
    doctor_check_contains "$TARGET_HOME/.local/share/nautilus-python/extensions/open-terminal-here.py" 'xdg-terminal-exec'
  fi
  if doctor_plan_has_entry "$native_plan" "qt5ct" || doctor_plan_has_entry "$native_plan" "qt6ct" || doctor_plan_has_entry "$native_plan" "qt6ct-kde"; then
    doctor_check_contains "$user_config_home/kdeglobals" 'widgetStyle=Fusion'
    doctor_check_contains "$user_config_home/kdeglobals" 'Theme='
    doctor_check_contains "$user_config_home/qt5ct/qt5ct.conf" "color_scheme_path=$TARGET_HOME/.local/share/color-schemes/noctalia.colors"
    doctor_check_contains "$user_config_home/qt6ct/qt6ct.conf" "color_scheme_path=$TARGET_HOME/.local/share/color-schemes/noctalia.colors"
  fi

  local fatal_checks=0

  if doctor_plan_has_entry "$native_plan" "niri"; then
    doctor_check_command niri || ((++fatal_checks))
    doctor_check_file /usr/share/wayland-sessions/niri.desktop || ((++fatal_checks))
    doctor_check_file "$user_config_home/niri/config.kdl" || ((++fatal_checks))
    doctor_check_file "$niri_config_home/cfg/autostart.kdl" || ((++fatal_checks))
    doctor_check_file "$niri_config_home/cfg/keybinds.kdl" || ((++fatal_checks))
    doctor_check_file "$niri_config_home/cfg/misc.kdl" || ((++fatal_checks))
  fi

  if doctor_plan_has_entry "$native_plan" "zsh"; then
    doctor_warn_command zsh
    doctor_warn_file "$TARGET_HOME/.zshrc"
  fi
  if doctor_plan_has_entry "$native_plan" "starship"; then
    doctor_warn_command starship
    doctor_warn_file "$user_config_home/starship.toml"
  fi
  if doctor_plan_has_entry "$native_plan" "code" || doctor_plan_has_entry "$native_plan" "codium" || doctor_plan_has_entry "$native_plan" "code-insiders" || doctor_plan_has_entry "$native_plan" "vscodium"; then
    doctor_warn_command code
    doctor_warn_file "$user_config_home/Code/User/settings.json"
  fi
  if doctor_plan_has_entry "$native_plan" "zoxide"; then
    doctor_warn_command zoxide
  fi
  if doctor_plan_has_entry "$native_plan" "fastfetch"; then
    doctor_warn_command fastfetch
  fi
  if doctor_plan_has_entry "$native_plan" "gh" || doctor_plan_has_entry "$native_plan" "github-cli"; then
    doctor_warn_command gh
  fi
  if doctor_plan_has_entry "$native_plan" "btop"; then
    doctor_warn_command btop
    doctor_warn_file "$user_config_home/btop/btop.conf"
  fi
  if doctor_plan_has_entry "$native_plan" "fd-find"; then
    doctor_warn_command fd
  fi
  if doctor_plan_has_entry "$native_plan" "fd"; then
    doctor_warn_command fd
  fi
  if doctor_plan_has_entry "$native_plan" "fzf"; then
    doctor_warn_command fzf
  fi
  if doctor_plan_has_entry "$native_plan" "bat"; then
    doctor_warn_command bat
  fi
  if doctor_plan_has_entry "$native_plan" "yazi"; then
    doctor_warn_command yazi
  fi

  doctor_warn_enabled NetworkManager
  local display_manager_hint="SDDM"
  local existing_display_manager=""
  existing_display_manager="$(detect_enabled_display_manager || true)"
  if [[ "$existing_display_manager" == "sddm.service" ]] && doctor_check_enabled sddm; then
    :
  elif [[ -n "$existing_display_manager" ]]; then
    printf '[ok] existing display manager %s\n' "$existing_display_manager"
    display_manager_hint="your display manager"
  elif doctor_check_enabled sddm; then
    :
  elif doctor_plan_has_entry "$native_plan" "sddm"; then
    ((++fatal_checks))
  fi
  doctor_warn_enabled bluetooth
  doctor_warn_enabled firewalld
  doctor_warn_enabled chronyd
  doctor_warn_enabled tuned-ppd
  doctor_warn_enabled cups
  doctor_warn_enabled avahi-daemon

  case "$DISTRO" in
    fedora)
      run_cmd_as_root dnf copr list || true
      run_cmd_as_root dnf repolist || true
      run_cmd_as_root dnf repoquery --whatprovides desktop-notification-daemon || true
      ;;
  esac

  printf 'Doctor completed.\n'
  if [[ "$fatal_checks" -gt 0 ]]; then
    printf 'Fatal desktop readiness checks failed: %s\n' "$fatal_checks"
    return 1
  fi
  printf 'Doctor completed with no fatal readiness failures.\n'
  printf 'Reboot, open %s, and choose the Niri session.\n' "$display_manager_hint"
}
