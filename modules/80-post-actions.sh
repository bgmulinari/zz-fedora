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

install_fedora_jetbrains_mono_nerd_font() {
  [[ "$DISTRO" == "fedora" ]] || return 0

  local font_dir="$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerdFont"
  local download_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip"

  if [[ -d "$font_dir" ]] && find "$font_dir" -maxdepth 1 -type f -name '*.ttf' -print -quit | grep -q .; then
    log_info "JetBrainsMono Nerd Font already installed at $font_dir"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install JetBrainsMono Nerd Font -> %s\n' "$font_dir"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$font_dir"
  run_cmd_as_user "$TARGET_USER" bash -c "
    set -Eeuo pipefail
    tmp_zip=\$(mktemp --suffix=.zip)
    trap 'rm -f \"\$tmp_zip\"' EXIT
    curl -fsSL '$download_url' -o \"\$tmp_zip\"
    unzip -o \"\$tmp_zip\" -d '$font_dir'
    fc-cache -f '$font_dir'
  "
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

pywalfox_available_for_plan() {
  local native_plan="$1"
  local aur_plan="$2"

  plan_has_any_backend_entry "$native_plan" pywalfox python-pywalfox python3-pywalfox && return 0
  plan_has_any_backend_entry "$aur_plan" pywalfox python-pywalfox python3-pywalfox && return 0
  [[ "$DISTRO" == "fedora" ]] && browser_choice_selected firefox && return 0
  command -v pywalfox >/dev/null 2>&1
}

noctalia_browser_template_ids() {
  local native_plan="$1"
  local aur_plan="$2"
  local browser
  while IFS= read -r browser; do
    case "$browser" in
      firefox)
        if pywalfox_available_for_plan "$native_plan" "$aur_plan"; then
          printf 'pywalfox\n'
        fi
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

  local -a template_ids=("niri" "gtk" "kitty")
  local -a managed_template_ids=("niri" "gtk" "kitty" "code" "pywalfox" "zenBrowser")
  if native_plan_has_any "$native_plan" code codium code-insiders vscodium || native_plan_has_any "$aur_plan" visual-studio-code-bin; then
    template_ids+=("code")
  fi

  local template_id
  while IFS= read -r template_id; do
    [[ -n "$template_id" ]] || continue
    append_unique template_ids "$template_id"
  done < <(noctalia_browser_template_ids "$native_plan" "$aur_plan")

  local templates_json managed_templates_json temp_file
  templates_json="$(printf '%s\n' "${template_ids[@]}" | jq -R . | jq -cs 'map({id: ., enabled: true})')"
  managed_templates_json="$(printf '%s\n' "${managed_template_ids[@]}" | jq -R . | jq -cs '.')"
  temp_file="$(mktemp "$CACHE_DIR/noctalia-settings.XXXXXX")"

  jq \
    --arg scheme "Catppuccin" \
    --argjson active_templates "$templates_json" \
    --argjson managed_template_ids "$managed_templates_json" \
    --argjson enable_user_theming "$enable_user_theming" \
    '
      (.templates.activeTemplates // []) as $existing_templates |
      ($existing_templates | map(select(.id as $id | ($managed_template_ids | index($id) | not)))) as $user_templates |
      .colorSchemes = ((.colorSchemes // {}) + {
        useWallpaperColors: false,
        predefinedScheme: $scheme
      }) |
      .appLauncher = ((.appLauncher // {}) + {
        terminalCommand: "kitty -e"
      }) |
      .templates = ((.templates // {}) + {
        activeTemplates: ($user_templates + $active_templates),
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

browser_choice_selected() {
  local expected="$1"
  local browser
  while IFS= read -r browser; do
    [[ "$browser" == "$expected" ]] && return 0
  done < <(effective_choice_ids "$DISTRO" "browsers")
  return 1
}

zen_browser_selected() {
  local browser
  while IFS= read -r browser; do
    case "$browser" in
      zen-flatpak|zen-copr|zen-aur)
        return 0
        ;;
    esac
  done < <(effective_choice_ids "$DISTRO" "browsers")
  return 1
}

install_pywalfox_native_host() {
  browser_choice_selected firefox || return 0

  local native_plan aur_plan
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  aur_plan="$(package_file_for_backend aur)"

  if ! pywalfox_available_for_plan "$native_plan" "$aur_plan"; then
    log_warn "Firefox was selected but 'pywalfox' is unavailable; skipping Noctalia Firefox theming"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "$DISTRO" == "fedora" ]]; then
      printf 'DRY-RUN: sudo python3 -m pip install --upgrade pywalfox\n'
    fi
    printf 'DRY-RUN: sudo -u %s pywalfox install\n' "$TARGET_USER"
    return 0
  fi

  if [[ "$DISTRO" == "fedora" ]]; then
    run_cmd sudo python3 -m pip install --upgrade pywalfox
  fi

  run_cmd_as_user "$TARGET_USER" pywalfox install || log_warn "Could not install Pywalfox native messaging host"
}

ensure_user_file_contains_line() {
  local destination="$1"
  local line="$2"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: ensure %s contains %q\n' "$destination" "$line"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" sh -c '
    destination="$1"
    line="$2"
    mkdir -p "$(dirname "$destination")"
    touch "$destination"
    grep -Fx "$line" "$destination" >/dev/null 2>&1 || printf "\n%s\n" "$line" >>"$destination"
  ' sh "$destination" "$line"
}

zen_profile_dirs() {
  local root profile_path
  for root in "$TARGET_HOME/.zen" "$TARGET_HOME/.var/app/app.zen_browser.zen/.zen"; do
    [[ -d "$root" ]] || continue
    if [[ -f "$root/profiles.ini" ]]; then
      while IFS= read -r profile_path; do
        [[ -n "$profile_path" ]] || continue
        if [[ "$profile_path" == /* ]]; then
          [[ -d "$profile_path" ]] && printf '%s\n' "$profile_path"
        else
          [[ -d "$root/$profile_path" ]] && printf '%s\n' "$root/$profile_path"
        fi
      done < <(awk -F= '$1 == "Path" { print $2 }' "$root/profiles.ini")
    fi
    find "$root" -mindepth 1 -maxdepth 2 -type f \( -name prefs.js -o -name compatibility.ini \) -printf '%h\n' 2>/dev/null || true
  done | sort -u
}

configure_zen_browser_noctalia_theme() {
  zen_browser_selected || return 0

  local user_chrome_import user_content_import profile_dir found_profile
  user_chrome_import="@import \"$TARGET_HOME/.cache/noctalia/zen-browser/zen-userChrome.css\";"
  user_content_import="@import \"$TARGET_HOME/.cache/noctalia/zen-browser/zen-userContent.css\";"
  found_profile=0

  while IFS= read -r profile_dir; do
    [[ -n "$profile_dir" ]] || continue
    found_profile=1
    ensure_user_file_contains_line "$profile_dir/chrome/userChrome.css" "$user_chrome_import"
    ensure_user_file_contains_line "$profile_dir/chrome/userContent.css" "$user_content_import"
    ensure_user_file_contains_line "$profile_dir/user.js" 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
  done < <(zen_profile_dirs)

  if [[ "$found_profile" -eq 0 ]]; then
    log_warn "Zen Browser was selected but no existing Zen profile was found; launch Zen once, then rerun install or doctor"
  fi
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
  run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark || true
  run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
  run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface icon-theme Yaru-blue || true
  install_fedora_jetbrains_mono_nerd_font
  install_noctalia_wallpaper_state
  update_noctalia_settings
  install_pywalfox_native_host
  configure_zen_browser_noctalia_theme
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
