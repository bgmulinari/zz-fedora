#!/usr/bin/env bash
set -Eeuo pipefail

install_user_file_if_changed() {
  local source_file="$1"
  local destination="$2"
  local mode="${3:-0644}"

  if [[ -f "$destination" ]] && cmp -s "$source_file" "$destination"; then
    log_info "Unchanged file: $destination"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install %s -> %s (mode %s)\n' "$source_file" "$destination" "$mode"
    return 0
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    backup_file_if_needed "$destination"
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$destination")"
  run_cmd_as_user "$TARGET_USER" install -m "$mode" "$source_file" "$destination"
}

install_qtct_config() {
  local version="$1"
  local temp_file destination color_scheme_path

  destination="$TARGET_HOME/.config/qt${version}ct/qt${version}ct.conf"
  color_scheme_path="$TARGET_HOME/.config/qt${version}ct/colors/noctalia.conf"
  temp_file="$(mktemp "$CACHE_DIR/qt${version}ct.XXXXXX")"

  cat >"$temp_file" <<EOF
[Appearance]
color_scheme_path=$color_scheme_path
custom_palette=false
icon_theme=Yaru-blue
standard_dialogs=xdgdesktopportal
style=Fusion

[Fonts]
fixed="JetBrains Mono,10,-1,5,50,0,0,0,0,0"
general="Noto Sans,10,-1,5,50,0,0,0,0,0"

[Interface]
activate_item_on_single_click=1
buttonbox_layout=0
cursor_flash_time=1000
dialog_buttons_have_icons=1
double_click_interval=400
gui_effects=@Invalid()
keyboard_scheme=2
menus_have_icons=true
show_shortcuts_in_context_menus=true
stylesheets=@Invalid()
toolbutton_style=4
underline_shortcut=1
wheel_scroll_lines=3
EOF

  install_user_file_if_changed "$temp_file" "$destination"
  rm -f "$temp_file"
}

install_noctalia_wallpaper_state() {
  local wallpaper_path destination temp_file

  wallpaper_path="$TARGET_HOME/.local/share/wallpapers/SilentPeaks.jpg"
  destination="$TARGET_HOME/.cache/noctalia/wallpapers.json"
  temp_file="$(mktemp "$CACHE_DIR/noctalia-wallpapers.XXXXXX")"

  cat >"$temp_file" <<EOF
{
  "defaultWallpaper": "$wallpaper_path",
  "wallpapers": {}
}
EOF

  install_user_file_if_changed "$temp_file" "$destination"
  rm -f "$temp_file"
}

native_plan_has_any() {
  local native_plan="$1"
  shift
  local entry
  for entry in "$@"; do
    [[ -f "$native_plan" ]] || return 1
    if grep -Fx "$entry" "$native_plan" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

plan_has_any_backend_entry() {
  local plan_file="$1"
  shift
  local entry
  for entry in "$@"; do
    [[ -f "$plan_file" ]] || continue
    if grep -Fx "$entry" "$plan_file" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

noctalia_browser_template_ids() {
  local browser
  while IFS= read -r browser; do
    case "$browser" in
      firefox)
        printf 'pywalfox\n'
        ;;
      zen-flatpak|zen-copr|zen-aur)
        printf 'zenBrowser\n'
        ;;
    esac
  done < <(effective_choice_ids "$DISTRO" "browsers")
}

update_noctalia_settings() {
  local settings_file="$TARGET_HOME/.config/noctalia/settings.json"
  [[ -f "$settings_file" ]] || return 0

  local native_plan aur_plan enable_user_theming
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  aur_plan="$(package_file_for_backend aur)"
  enable_user_theming=false
  if native_plan_has_any "$native_plan" neovim starship zsh; then
    enable_user_theming=true
  fi

  local -a template_ids=("niri" "gtk" "qt")
  if native_plan_has_any "$native_plan" code codium code-insiders vscodium || native_plan_has_any "$aur_plan" visual-studio-code-bin; then
    template_ids+=("code")
  fi

  local template_id
  while IFS= read -r template_id; do
    [[ -n "$template_id" ]] || continue
    append_unique template_ids "$template_id"
  done < <(noctalia_browser_template_ids)

  local templates_json temp_file
  templates_json="$(printf '%s\n' "${template_ids[@]}" | jq -R . | jq -cs 'map({id: ., enabled: true})')"
  temp_file="$(mktemp "$CACHE_DIR/noctalia-settings.XXXXXX")"

  jq \
    --arg scheme "Catppuccin" \
    --argjson active_templates "$templates_json" \
    --argjson enable_user_theming "$enable_user_theming" \
    '
      .colorSchemes = ((.colorSchemes // {}) + {
        useWallpaperColors: false,
        predefinedScheme: $scheme
      }) |
      .appLauncher = ((.appLauncher // {}) + {
        terminalCommand: "kitty -e"
      }) |
      .templates = ((.templates // {}) + {
        activeTemplates: $active_templates,
        enableUserTheming: $enable_user_theming
      })
    ' \
    "$settings_file" >"$temp_file"

  if ! cmp -s "$temp_file" "$settings_file"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'DRY-RUN: update %s\n' "$settings_file"
    else
      run_cmd_as_user "$TARGET_USER" sh -c "cat '$temp_file' > '$settings_file'"
    fi
  fi

  rm -f "$temp_file"
}

install_vscode_noctalia_extension() {
  local native_plan aur_plan
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  aur_plan="$(package_file_for_backend aur)"

  if ! plan_has_any_backend_entry "$native_plan" code codium code-insiders vscodium && ! plan_has_any_backend_entry "$aur_plan" visual-studio-code-bin; then
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: sudo -u %s code --install-extension Noctalia.noctaliatheme --force\n' "$TARGET_USER"
    return 0
  fi

  if ! command -v code >/dev/null 2>&1; then
    log_warn "VS Code was planned but 'code' is unavailable; skipping NoctaliaTheme extension install"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" code --install-extension Noctalia.noctaliatheme --force
}

module_80_post_actions() {
  if [[ "$DISTRO" == "fedora" && "$CODECS_SELECTED" -eq 1 ]]; then
    run_cmd sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    run_cmd sudo dnf group update -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
  fi

  if array_contains "libvirt" $(effective_choice_ids "$DISTRO" "virtualization"); then
    run_cmd sudo usermod -aG libvirt "$TARGET_USER"
  fi

  run_cmd_as_user "$TARGET_USER" xdg-user-dirs-update || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default org.gnome.Nautilus.desktop inode/directory || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default org.gnome.Evince.desktop application/pdf || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/plain || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/english || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-makefile || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-c++hdr || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-c++src || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-chdr || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-csrc || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-java || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-moc || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-pascal || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-tcl || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-tex || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop application/x-shellscript || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-c || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/x-c++ || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop application/xml || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default nvim.desktop text/xml || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/png || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/jpeg || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/gif || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/webp || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/bmp || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/tiff || true
  run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3 || true
  run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
  run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface icon-theme Yaru-blue || true
  install_qtct_config 5
  install_qtct_config 6
  install_noctalia_wallpaper_state
  update_noctalia_settings
  install_vscode_noctalia_extension

  local -a browsers=()
  while IFS= read -r browser; do
    [[ -n "$browser" ]] && browsers+=("$browser")
  done < <(effective_choice_ids "$DISTRO" "browsers")

  local browser_choice=""
  if [[ -n "$PREFERRED_BROWSER" ]]; then
    browser_choice="$PREFERRED_BROWSER"
  elif [[ "${#browsers[@]}" -eq 1 ]]; then
    browser_choice="${browsers[0]}"
  fi
  if [[ -n "$browser_choice" ]]; then
    local desktop_file=""
    desktop_file="$(browser_desktop_file "$browser_choice" || true)"
    if [[ -n "$desktop_file" ]]; then
      run_cmd_as_user "$TARGET_USER" xdg-settings set default-web-browser "$desktop_file" || log_warn "Could not set default browser to $desktop_file"
    fi
  fi
}
