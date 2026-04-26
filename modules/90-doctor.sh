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
  doctor_check_command kitty
  doctor_check_command nautilus
  doctor_check_command nvim
  doctor_check_command evince
  doctor_check_command xdg-desktop-portal
  doctor_check_command gum

  local user_config_home="$TARGET_HOME/.config"
  local niri_config_home="$user_config_home/niri"
  doctor_check_file "$user_config_home/niri/config.kdl"
  doctor_check_file "$niri_config_home/cfg/autostart.kdl"
  doctor_check_file "$niri_config_home/cfg/keybinds.kdl"
  doctor_check_file "$niri_config_home/cfg/misc.kdl"
  doctor_check_file "$user_config_home/xdg-desktop-portal/niri-portals.conf"
  doctor_check_file "$user_config_home/environment.d/10-niri-gtk.conf"
  doctor_check_file "$user_config_home/kitty/kitty.conf"
  doctor_check_file "$user_config_home/noctalia/settings.json"
  doctor_check_file "$user_config_home/noctalia/plugins.json"
  doctor_check_file "$user_config_home/noctalia/user-templates.toml"
  doctor_check_file "$user_config_home/noctalia/templates/neovim.lua"
  doctor_check_file "$user_config_home/noctalia/templates/starship.toml"
  doctor_check_file "$user_config_home/noctalia/templates/zsh-syntax-highlighting.zsh"
  doctor_check_file "$TARGET_HOME/.cache/noctalia/wallpapers.json"
  doctor_check_file "$user_config_home/gtk-3.0/settings.ini"
  doctor_check_file "$user_config_home/qt5ct/qt5ct.conf"
  doctor_check_file "$user_config_home/qt6ct/qt6ct.conf"
  doctor_check_file "$user_config_home/nvim/plugin/noctalia.lua"
  doctor_check_file "$user_config_home/Code/User/settings.json"
  doctor_check_file "$TARGET_HOME/.local/bin/noctalia-screenshot"
  doctor_check_file "$TARGET_HOME/.local/share/wallpapers/SilentPeaks.jpg"

  doctor_check_contains "$niri_config_home/cfg/autostart.kdl" 'spawn-at-startup "qs" "-c" "noctalia-shell"'
  doctor_check_contains "$niri_config_home/cfg/keybinds.kdl" 'spawn "kitty"'
  doctor_check_contains "$niri_config_home/cfg/keybinds.kdl" 'spawn "nautilus"'
  doctor_check_contains "$niri_config_home/cfg/misc.kdl" 'QT_QPA_PLATFORMTHEME "qt6ct"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"terminalCommand": "kitty -e"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"predefinedScheme": "Catppuccin"'
  doctor_check_contains "$user_config_home/noctalia/plugins.json" '"polkit-agent"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "niri"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "gtk"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "qt"'
  doctor_check_contains "$TARGET_HOME/.cache/noctalia/wallpapers.json" '"defaultWallpaper": "'"$TARGET_HOME"'/.local/share/wallpapers/SilentPeaks.jpg"'
  doctor_check_contains "$user_config_home/noctalia/user-templates.toml" '[templates.neovim]'

  local native_plan
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  local aur_plan
  aur_plan="$(package_file_for_backend aur)"

  if doctor_plan_has_entry "$native_plan" "zsh"; then
    doctor_check_command zsh
    doctor_check_file "$TARGET_HOME/.zshrc"
    doctor_check_file "$TARGET_HOME/.zsh/noctalia-zsh-syntax-highlighting.zsh"
    doctor_check_contains "$user_config_home/noctalia/user-templates.toml" '[templates.zshSyntaxHighlighting]'
  fi
  if doctor_plan_has_entry "$native_plan" "starship"; then
    doctor_check_command starship
    doctor_check_file "$user_config_home/starship.toml"
    doctor_check_contains "$user_config_home/noctalia/user-templates.toml" '[templates.starship]'
  fi
  if doctor_plan_has_entry "$native_plan" "qt5ct"; then
    doctor_check_command qt5ct
  fi
  if doctor_plan_has_entry "$native_plan" "qt6ct"; then
    doctor_check_command qt6ct
  fi
  if doctor_plan_has_entry "$native_plan" "neovim"; then
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"enableUserTheming": true'
  fi
  if doctor_plan_has_entry "$native_plan" "code" || doctor_plan_has_entry "$native_plan" "codium" || doctor_plan_has_entry "$native_plan" "code-insiders" || doctor_plan_has_entry "$native_plan" "vscodium" || doctor_plan_has_entry "$aur_plan" "visual-studio-code-bin"; then
    doctor_check_command code
    doctor_check_file "$user_config_home/Code/User/settings.json"
    doctor_check_contains "$user_config_home/Code/User/settings.json" '"workbench.colorTheme": "NoctaliaTheme"'
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "code"'
  fi
  if doctor_plan_has_entry "$native_plan" "zoxide"; then
    doctor_check_command zoxide
  fi
  if doctor_plan_has_entry "$native_plan" "fastfetch"; then
    doctor_check_command fastfetch
  fi
  if doctor_plan_has_entry "$native_plan" "gh" || doctor_plan_has_entry "$native_plan" "github-cli"; then
    doctor_check_command gh
  fi
  if doctor_plan_has_entry "$native_plan" "btop"; then
    doctor_check_command btop
    doctor_check_file "$user_config_home/btop/btop.conf"
  fi
  if doctor_plan_has_entry "$native_plan" "fd-find"; then
    doctor_check_command fdfind
  fi
  if doctor_plan_has_entry "$native_plan" "fd"; then
    doctor_check_command fd
  fi
  if doctor_plan_has_entry "$native_plan" "fzf"; then
    doctor_check_command fzf
  fi
  if doctor_plan_has_entry "$native_plan" "bat"; then
    doctor_check_command bat
  fi
  if doctor_plan_has_entry "$native_plan" "yazi"; then
    doctor_check_command yazi
  fi
  if grep -Fx firefox < <(effective_choice_ids "$DISTRO" "browsers") >/dev/null 2>&1; then
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "pywalfox"'
  fi
  if grep -E '^(zen-flatpak|zen-copr|zen-aur)$' < <(effective_choice_ids "$DISTRO" "browsers") >/dev/null 2>&1; then
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "zenBrowser"'
  fi

  doctor_check_enabled NetworkManager
  doctor_check_enabled sddm
  doctor_check_enabled bluetooth
  doctor_check_enabled firewalld
  doctor_check_enabled chronyd
  doctor_check_enabled power-profiles-daemon

  case "$DISTRO" in
    fedora)
      run_cmd sudo dnf copr list || true
      run_cmd sudo dnf repolist || true
      run_cmd sudo dnf repoquery --whatprovides desktop-notification-daemon || true
      ;;
    arch)
      run_cmd pacman -Qs xdg-desktop-portal || true
      run_cmd pacman -Qs polkit || true
      ;;
  esac

  printf 'Doctor completed.\n'
  printf 'Warnings are not necessarily fatal.\n'
  printf 'Reboot, open SDDM, and choose the Niri session.\n'
}
