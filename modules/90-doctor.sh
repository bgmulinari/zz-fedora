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

doctor_warn_command() {
  doctor_check_command "$1" || true
}

doctor_warn_file() {
  doctor_check_file "$1" || true
}

doctor_warn_enabled() {
  doctor_check_enabled "$1" || true
}

doctor_plan_has_entry() {
  local plan_file="$1"
  local entry="$2"
  [[ -f "$plan_file" ]] || return 1
  grep -Fx "$entry" "$plan_file" >/dev/null 2>&1
}

doctor_check_zen_browser_profiles() {
  local user_chrome_import user_content_import profile_dir found_profile
  user_chrome_import="@import \"$TARGET_HOME/.cache/noctalia/zen-browser/zen-userChrome.css\";"
  user_content_import="@import \"$TARGET_HOME/.cache/noctalia/zen-browser/zen-userContent.css\";"
  found_profile=0

  while IFS= read -r profile_dir; do
    [[ -n "$profile_dir" ]] || continue
    found_profile=1
    doctor_check_contains "$profile_dir/chrome/userChrome.css" "$user_chrome_import"
    doctor_check_contains "$profile_dir/chrome/userContent.css" "$user_content_import"
    doctor_check_contains "$profile_dir/user.js" 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
  done < <(zen_profile_dirs)

  if [[ "$found_profile" -eq 0 ]]; then
    printf '[warn] missing Zen Browser profile; launch Zen once, then rerun install or doctor\n'
  fi
}

doctor_check_pywalfox_firefox_extension() {
  if pywalfox_firefox_extension_installed; then
    printf '[ok] Firefox extension pywalfox@frewacom.org\n'
  else
    printf '[warn] missing Firefox extension pywalfox@frewacom.org; install the Pywalfox browser add-on to apply the generated theme\n'
  fi
}

module_90_doctor() {
  if [[ "$COMMAND" != "doctor" && "$DRY_RUN" -eq 1 ]]; then
    printf 'Doctor skipped in dry-run mode.\n'
    return 0
  fi

  doctor_warn_command niri
  doctor_warn_command niri-session
  doctor_warn_command qs
  doctor_warn_command ghostty
  doctor_warn_command xdg-terminal-exec
  doctor_warn_command nautilus
  doctor_warn_command nvim
  doctor_warn_command evince
  doctor_warn_command xdg-desktop-portal
  doctor_warn_command gum

  local user_config_home="$TARGET_HOME/.config"
  local niri_config_home="$user_config_home/niri"
  doctor_warn_file "$user_config_home/niri/config.kdl"
  doctor_warn_file "$niri_config_home/cfg/autostart.kdl"
  doctor_warn_file "$niri_config_home/cfg/keybinds.kdl"
  doctor_warn_file "$niri_config_home/cfg/misc.kdl"
  doctor_warn_file "$user_config_home/xdg-desktop-portal/niri-portals.conf"
  doctor_warn_file "$user_config_home/environment.d/10-niri-gtk.conf"
  doctor_warn_file "$user_config_home/xdg-terminals.list"
  doctor_warn_file "$user_config_home/ghostty/config"
  doctor_warn_file "$user_config_home/niri/noctalia.kdl"
  doctor_warn_file "$user_config_home/noctalia/settings.json"
  doctor_warn_file "$user_config_home/noctalia/plugins.json"
  doctor_warn_file "$user_config_home/noctalia/user-templates.toml"
  doctor_warn_file "$user_config_home/noctalia/templates/icon-theme-accent"
  doctor_warn_file "$user_config_home/noctalia/templates/neovim.lua"
  doctor_warn_file "$user_config_home/noctalia/templates/zsh-syntax-highlighting.zsh"
  doctor_warn_file "$TARGET_HOME/.cache/noctalia/wallpapers.json"
  doctor_warn_file "$user_config_home/gtk-3.0/noctalia.css"
  doctor_warn_file "$user_config_home/gtk-4.0/noctalia.css"
  doctor_warn_file "$user_config_home/qt5ct/qt5ct.conf"
  doctor_warn_file "$user_config_home/qt5ct/colors/noctalia.conf"
  doctor_warn_file "$user_config_home/qt6ct/qt6ct.conf"
  doctor_warn_file "$user_config_home/qt6ct/colors/noctalia.conf"
  doctor_warn_file "$TARGET_HOME/.local/share/color-schemes/noctalia.colors"
  doctor_warn_file "$user_config_home/kdeglobals"
  doctor_warn_file "$user_config_home/nvim/plugin/noctalia.lua"
  doctor_warn_file "$user_config_home/Code/User/settings.json"
  doctor_warn_file "$TARGET_HOME/.local/bin/noctalia-sync-icon-theme"
  doctor_warn_file "$TARGET_HOME/.local/bin/noctalia-screenshot"
  doctor_warn_file "$TARGET_HOME/.local/share/applications/nvim.desktop"
  doctor_warn_file "$TARGET_HOME/.local/share/nautilus-python/extensions/open-terminal-here.py"
  doctor_warn_file "$TARGET_HOME/.local/share/wallpapers/SilentPeaks.jpg"
  if [[ "$DISTRO" == "fedora" ]]; then
    doctor_check_dir_has_files "$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerdFont" '*.ttf'
  fi

  doctor_check_contains "$niri_config_home/cfg/autostart.kdl" 'spawn-at-startup "qs" "-c" "noctalia-shell"'
  doctor_check_contains "$niri_config_home/cfg/keybinds.kdl" 'spawn "xdg-terminal-exec"'
  doctor_check_contains "$niri_config_home/cfg/keybinds.kdl" 'spawn "nautilus"'
  doctor_check_contains "$niri_config_home/config.kdl" 'include "./noctalia.kdl"'
  doctor_check_contains "$user_config_home/ghostty/config" 'theme = noctalia'
  doctor_check_contains "$user_config_home/xdg-terminals.list" 'Alacritty.desktop'
  doctor_check_contains "$TARGET_HOME/.local/share/applications/nvim.desktop" 'Exec=xdg-terminal-exec'
  doctor_check_contains "$TARGET_HOME/.local/share/nautilus-python/extensions/open-terminal-here.py" 'xdg-terminal-exec'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"terminalCommand": "ghostty -e"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"predefinedScheme": "Catppuccin"'
  doctor_check_contains "$user_config_home/noctalia/plugins.json" '"polkit-agent"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "niri"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "gtk"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "qt"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "kcolorscheme"'
  doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "ghostty"'
  doctor_check_contains "$user_config_home/environment.d/10-niri-gtk.conf" 'QT_QPA_PLATFORMTHEME=qt6ct'
  doctor_check_contains "$user_config_home/environment.d/10-niri-gtk.conf" 'TERMINAL=xdg-terminal-exec'
  doctor_check_contains "$user_config_home/environment.d/10-niri-gtk.conf" 'EDITOR=nvim'
  doctor_check_contains "$user_config_home/kdeglobals" 'widgetStyle=Fusion'
  doctor_check_contains "$user_config_home/kdeglobals" 'Theme='
  doctor_check_contains "$user_config_home/qt5ct/qt5ct.conf" 'icon_theme='
  doctor_check_contains "$user_config_home/qt6ct/qt6ct.conf" 'icon_theme='
  doctor_check_contains "$user_config_home/noctalia/user-templates.toml" '[templates.iconTheme]'
  doctor_check_contains "$TARGET_HOME/.cache/noctalia/wallpapers.json" '"defaultWallpaper": "'"$TARGET_HOME"'/.local/share/wallpapers/SilentPeaks.jpg"'
  doctor_check_contains "$user_config_home/noctalia/user-templates.toml" '[templates.neovim]'

  local native_plan
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  local aur_plan
  aur_plan="$(package_file_for_backend aur)"
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
    doctor_warn_file "$TARGET_HOME/.zsh/noctalia-zsh-syntax-highlighting.zsh"
    doctor_check_contains "$user_config_home/noctalia/user-templates.toml" '[templates.zshSyntaxHighlighting]'
  fi
  if doctor_plan_has_entry "$native_plan" "starship"; then
    doctor_warn_command starship
    doctor_warn_file "$user_config_home/starship.toml"
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "starship"'
  fi
  if doctor_plan_has_entry "$native_plan" "neovim"; then
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"enableUserTheming": true'
  fi
  if doctor_plan_has_entry "$native_plan" "code" || doctor_plan_has_entry "$native_plan" "codium" || doctor_plan_has_entry "$native_plan" "code-insiders" || doctor_plan_has_entry "$native_plan" "vscodium" || doctor_plan_has_entry "$aur_plan" "visual-studio-code-bin"; then
    doctor_warn_command code
    doctor_warn_file "$user_config_home/Code/User/settings.json"
    doctor_check_contains "$user_config_home/Code/User/settings.json" '"workbench.colorTheme": "NoctaliaTheme"'
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "code"'
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
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "btop"'
  fi
  if doctor_plan_has_entry "$native_plan" "fd-find"; then
    doctor_warn_command fdfind
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
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "yazi"'
  fi
  if grep -Fx firefox < <(effective_choice_ids "$DISTRO" "browsers") >/dev/null 2>&1; then
    doctor_warn_command pywalfox
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "pywalfox"'
    doctor_warn_file "$TARGET_HOME/.cache/wal/colors.json"
    doctor_warn_file "$TARGET_HOME/.mozilla/native-messaging-hosts/pywalfox.json"
    doctor_check_contains "$(firefox_distribution_dir)/policies.json" '"pywalfox@frewacom.org"'
    if [[ -f "$TARGET_HOME/.config/mozilla/firefox/profiles.ini" ]]; then
      doctor_warn_file "$TARGET_HOME/.mozilla/firefox/profiles.ini"
    fi
    doctor_check_pywalfox_firefox_extension
  fi
  if grep -E '^(zen-copr|zen-aur)$' < <(effective_choice_ids "$DISTRO" "browsers") >/dev/null 2>&1; then
    doctor_check_contains "$user_config_home/noctalia/settings.json" '"id": "zenBrowser"'
    doctor_warn_file "$TARGET_HOME/.cache/noctalia/zen-browser/zen-userChrome.css"
    doctor_warn_file "$TARGET_HOME/.cache/noctalia/zen-browser/zen-userContent.css"
    doctor_check_zen_browser_profiles
  fi

  doctor_warn_enabled NetworkManager
  if doctor_check_enabled sddm; then
    :
  elif doctor_plan_has_entry "$native_plan" "sddm"; then
    ((++fatal_checks))
  fi
  doctor_warn_enabled bluetooth
  doctor_warn_enabled firewalld
  doctor_warn_enabled chronyd
  doctor_warn_enabled power-profiles-daemon

  case "$DISTRO" in
    fedora)
      run_cmd_as_root dnf copr list || true
      run_cmd_as_root dnf repolist || true
      run_cmd_as_root dnf repoquery --whatprovides desktop-notification-daemon || true
      ;;
    arch)
      run_cmd pacman -Qs xdg-desktop-portal || true
      run_cmd pacman -Qs polkit || true
      ;;
  esac

  printf 'Doctor completed.\n'
  if [[ "$fatal_checks" -gt 0 ]]; then
    printf 'Fatal desktop readiness checks failed: %s\n' "$fatal_checks"
    return 1
  fi
  printf 'Warnings are not necessarily fatal.\n'
  printf 'Reboot, open SDDM, and choose the Niri session.\n'
}
