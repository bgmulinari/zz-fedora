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
    local backup_root backup_path
    backup_root="$STATE_DIR/backups/$(timestamp)"
    backup_path="$backup_root$destination"
    run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$backup_path")"
    run_cmd_as_user "$TARGET_USER" cp -a "$destination" "$backup_path"
    log_info "Backed up $destination to $backup_path"
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
  chmod 0644 "$temp_file"

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

pywalfox_firefox_extension_installed() {
  local firefox_config_dir extensions_file

  for firefox_config_dir in "$TARGET_HOME/.mozilla/firefox" "$TARGET_HOME/.config/mozilla/firefox"; do
    [[ -d "$firefox_config_dir" ]] || continue
    while IFS= read -r extensions_file; do
      [[ -n "$extensions_file" ]] || continue
      if grep -F '"id":"pywalfox@frewacom.org"' "$extensions_file" >/dev/null 2>&1 || grep -F '"id": "pywalfox@frewacom.org"' "$extensions_file" >/dev/null 2>&1; then
        return 0
      fi
    done < <(find "$firefox_config_dir" -maxdepth 2 -type f -name extensions.json 2>/dev/null)
  done

  return 1
}

firefox_distribution_dir() {
  if [[ -n "${FIREFOX_DISTRIBUTION_DIR:-}" ]]; then
    printf '%s\n' "$FIREFOX_DISTRIBUTION_DIR"
    return 0
  fi

  local candidate
  for candidate in /usr/lib64/firefox/distribution /usr/lib/firefox/distribution; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' "/usr/lib/firefox/distribution"
}

install_firefox_pywalfox_extension_policy() {
  browser_choice_selected firefox || return 0

  local distribution_dir policies_file temp_file
  distribution_dir="$(firefox_distribution_dir)"
  policies_file="$distribution_dir/policies.json"
  temp_file="$(mktemp "$CACHE_DIR/firefox-policies.XXXXXX")"

  if [[ -f "$policies_file" ]]; then
    jq \
      '.policies = ((.policies // {}) + {
        ExtensionSettings: ((.policies.ExtensionSettings // {}) + {
          "pywalfox@frewacom.org": {
            installation_mode: "normal_installed",
            install_url: "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"
          }
        })
      })' \
      "$policies_file" >"$temp_file"
  else
    cat >"$temp_file" <<'EOF'
{
  "policies": {
    "ExtensionSettings": {
      "pywalfox@frewacom.org": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"
      }
    }
  }
}
EOF
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Firefox Pywalfox extension policy -> %s\n' "$policies_file"
    rm -f "$temp_file"
    return 0
  fi

  if [[ -n "${FIREFOX_DISTRIBUTION_DIR:-}" ]]; then
    run_cmd mkdir -p "$distribution_dir"
    run_cmd install -m 0644 "$temp_file" "$policies_file"
  else
    run_cmd_as_root mkdir -p "$distribution_dir"
    run_cmd_as_root install -m 0644 "$temp_file" "$policies_file"
  fi
  rm -f "$temp_file"
}

ensure_firefox_profile_compat_for_pywalfox() {
  browser_choice_selected firefox || return 0

  local xdg_firefox_dir legacy_firefox_dir
  xdg_firefox_dir="$TARGET_HOME/.config/mozilla/firefox"
  legacy_firefox_dir="$TARGET_HOME/.mozilla/firefox"

  [[ -f "$xdg_firefox_dir/profiles.ini" ]] || return 0

  if [[ -L "$legacy_firefox_dir" ]]; then
    return 0
  fi

  if [[ -e "$legacy_firefox_dir" ]]; then
    log_warn "Firefox profiles are under $xdg_firefox_dir, but $legacy_firefox_dir already exists; Pywalfox may not find the active profile"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: ln -s %s %s\n' "$xdg_firefox_dir" "$legacy_firefox_dir"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$TARGET_HOME/.mozilla"
  run_cmd_as_user "$TARGET_USER" ln -s "$xdg_firefox_dir" "$legacy_firefox_dir"
}

zen_browser_available_for_plan() {
  local native_plan="$1"
  local aur_plan="$2"

  plan_has_any_backend_entry "$native_plan" zen-browser zen-browser-bin && return 0
  plan_has_any_backend_entry "$aur_plan" zen-browser-bin zen-browser-avx2-bin zen-browser-git && return 0

  [[ -d "$TARGET_HOME/.config/zen" ]] && return 0
  [[ -d "$TARGET_HOME/.zen" ]] && return 0

  return 1
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
      zen-copr|zen-aur)
        printf 'zenBrowser\n'
        ;;
    esac
  done < <(effective_choice_ids "$DISTRO" "browsers")

  if zen_browser_available_for_plan "$native_plan" "$aur_plan"; then
    printf 'zenBrowser\n'
  fi
}

vscode_theming_available_for_plan() {
  local native_plan="$1"
  local aur_plan="$2"

  plan_has_any_backend_entry "$native_plan" code codium code-insiders vscodium && return 0
  plan_has_any_backend_entry "$aur_plan" visual-studio-code-bin && return 0

  [[ -d "$TARGET_HOME/.config/Code" ]] && return 0
  [[ -d "$TARGET_HOME/.config/VSCodium" ]] && return 0
  [[ -d "$TARGET_HOME/.vscode/extensions" ]] && return 0
  [[ -d "$TARGET_HOME/.vscode-oss/extensions" ]] && return 0

  return 1
}

user_templates_available_for_plan() {
  local native_plan="$1"
  local aur_plan="$2"

  plan_has_any_backend_entry "$native_plan" neovim nvim zsh && return 0
  plan_has_any_backend_entry "$aur_plan" neovim nvim zsh && return 0

  command -v nvim >/dev/null 2>&1 && return 0
  command -v neovim >/dev/null 2>&1 && return 0
  command -v zsh >/dev/null 2>&1 && return 0

  [[ -d "$TARGET_HOME/.config/nvim" ]] && return 0
  [[ -d "$TARGET_HOME/.zsh" ]] && return 0
  [[ -f "$TARGET_HOME/.zshrc" ]] && return 0
  [[ -f "$TARGET_HOME/.config/noctalia/user-templates.toml" ]] && return 0

  return 1
}

noctalia_installed_template_ids() {
  local native_plan="$1"
  local aur_plan="$2"
  local flatpak_plan="$3"

  plan_has_any_backend_entry "$native_plan" niri && printf 'niri\n'
  plan_has_any_backend_entry "$native_plan" ghostty && printf 'ghostty\n'
  plan_has_any_backend_entry "$native_plan" starship && printf 'starship\n'
  plan_has_any_backend_entry "$native_plan" btop && printf 'btop\n'
  plan_has_any_backend_entry "$native_plan" yazi && printf 'yazi\n'
  plan_has_any_backend_entry "$native_plan" code codium code-insiders vscodium && printf 'code\n'

  plan_has_any_backend_entry "$aur_plan" visual-studio-code-bin && printf 'code\n'
  plan_has_any_backend_entry "$aur_plan" starship && printf 'starship\n'
  plan_has_any_backend_entry "$aur_plan" btop && printf 'btop\n'
  plan_has_any_backend_entry "$aur_plan" yazi && printf 'yazi\n'

}

starship_theming_available_for_plan() {
  local native_plan="$1"
  local aur_plan="$2"

  plan_has_any_backend_entry "$native_plan" starship && return 0
  plan_has_any_backend_entry "$aur_plan" starship && return 0

  return 1
}

install_starship_config() {
  local native_plan aur_plan
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  aur_plan="$(package_file_for_backend aur)"

  starship_theming_available_for_plan "$native_plan" "$aur_plan" || return 0
  [[ -e "$TARGET_HOME/.config/starship.toml" || -L "$TARGET_HOME/.config/starship.toml" ]] && return 0
  install_user_file_if_changed "$ROOT_DIR/templates/starship.toml" "$TARGET_HOME/.config/starship.toml"
}

install_niri_noctalia_seed_if_missing() {
  local native_plan destination
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  plan_has_any_backend_entry "$native_plan" niri || return 0

  destination="$TARGET_HOME/.config/niri/noctalia.kdl"
  [[ -e "$destination" || -L "$destination" ]] && return 0
  install_user_file_if_changed "$ROOT_DIR/templates/niri/noctalia.kdl" "$destination"
}

install_qtct_config() {
  local version="$1"
  local config_file temp_file color_file

  config_file="$TARGET_HOME/.config/qt${version}ct/qt${version}ct.conf"
  color_file="$TARGET_HOME/.config/qt${version}ct/colors/noctalia.conf"
  temp_file="$(mktemp "$CACHE_DIR/qt${version}ct.XXXXXX")"

  cat >"$temp_file" <<EOF
[Appearance]
color_scheme_path=$color_file
custom_palette=true
standard_dialogs=default
style=Fusion
EOF
  chmod 0644 "$temp_file"
  install_user_file_if_changed "$temp_file" "$config_file"
  rm -f "$temp_file"
}

install_qt_theme_config() {
  local native_plan
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  plan_has_any_backend_entry "$native_plan" qt5ct qt6ct || return 0

  install_qtct_config 5
  install_qtct_config 6
  install_kde_qt_theme_config
}

install_kde_config_key() {
  local group="$1"
  local key="$2"
  local value="$3"

  have_cmd kwriteconfig6 || return 0
  run_cmd_as_user "$TARGET_USER" env HOME="$TARGET_HOME" kwriteconfig6 --file kdeglobals --group "$group" --key "$key" "$value"
}

install_kde_qt_theme_config() {
  install_kde_config_key KDE widgetStyle Fusion
}

patch_noctalia_starship_template_apply_if_needed() {
  local script_path="${NOCTALIA_TEMPLATE_APPLY_PATH:-/etc/xdg/quickshell/noctalia-shell/Scripts/bash/template-apply.sh}"
  [[ -f "$script_path" ]] || return 0

  awk '
    /^starship\)/ { in_starship = 1; next }
    in_starship && /^[[:space:]]*;;$/ { exit }
    in_starship && /PALETTE_FILE=.*starship-palette\.toml/ { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "$script_path" && return 0

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: patch Noctalia Starship hook in %s\n' "$script_path"
    return 0
  fi

  local temp_file
  temp_file="$(mktemp "$CACHE_DIR/noctalia-template-apply.XXXXXX")"
  awk '
    /^starship\)/ && !patched {
      print
      print "    PALETTE_FILE=\"$HOME/.cache/noctalia/starship-palette.toml\""
      print ""
      patched = 1
      next
    }
    { print }
  ' "$script_path" >"$temp_file"

  run_cmd_as_root install -m 0755 "$temp_file" "$script_path"
  rm -f "$temp_file"
  log_info "Patched Noctalia Starship hook: $script_path"
}

apply_noctalia_starship_palette_if_available() {
  local native_plan aur_plan
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  aur_plan="$(package_file_for_backend aur)"

  starship_theming_available_for_plan "$native_plan" "$aur_plan" || return 0

  local script_path palette_path
  script_path="${NOCTALIA_TEMPLATE_APPLY_PATH:-/etc/xdg/quickshell/noctalia-shell/Scripts/bash/template-apply.sh}"
  palette_path="$TARGET_HOME/.cache/noctalia/starship-palette.toml"

  [[ -x "$script_path" ]] || return 0
  [[ -f "$palette_path" ]] || return 0

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: apply Noctalia Starship palette via %s\n' "$script_path"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" "$script_path" starship || log_warn "Could not apply Noctalia Starship palette"
}

update_noctalia_settings() {
  local settings_file="$TARGET_HOME/.config/noctalia/settings.json"
  if [[ ! -f "$settings_file" ]]; then
    install_user_file_if_changed "$ROOT_DIR/templates/noctalia/settings.json" "$settings_file"
  fi

  local native_plan aur_plan flatpak_plan enable_user_theming
  native_plan="$(package_file_for_backend "$(native_backend_for_distro "$DISTRO")")"
  aur_plan="$(package_file_for_backend aur)"
  flatpak_plan="$(package_file_for_backend flatpak)"
  enable_user_theming=false
  if user_templates_available_for_plan "$native_plan" "$aur_plan"; then
    enable_user_theming=true
  fi

  local -a template_ids=("gtk" "qt" "kcolorscheme")
  local -a managed_template_ids=("niri" "gtk" "qt" "kcolorscheme" "ghostty" "starship" "btop" "yazi" "code" "pywalfox" "zenBrowser")
  if vscode_theming_available_for_plan "$native_plan" "$aur_plan"; then
    template_ids+=("code")
  fi

  local template_id
  while IFS= read -r template_id; do
    [[ -n "$template_id" ]] || continue
    append_unique template_ids "$template_id"
  done < <(noctalia_installed_template_ids "$native_plan" "$aur_plan" "$flatpak_plan")

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
        terminalCommand: "ghostty -e"
      }) |
      .templates = ((.templates // {}) + {
        activeTemplates: ($user_templates + $active_templates),
        enableUserTheming: $enable_user_theming
      })
    ' \
    "$settings_file" >"$temp_file"
  chmod 0644 "$temp_file"

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
      zen-copr|zen-aur)
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
    if ! python3 -m pip --version >/dev/null 2>&1; then
      run_cmd_as_root dnf install -y python3-pip || {
        log_warn "Could not install python3-pip; skipping Pywalfox native messaging host"
        install_firefox_pywalfox_extension_policy
        ensure_firefox_profile_compat_for_pywalfox
        return 0
      }
    fi
    if ! run_cmd_as_root python3 -m pip install --upgrade pywalfox; then
      log_warn "Could not install Pywalfox with pip; skipping native messaging host"
      install_firefox_pywalfox_extension_policy
      ensure_firefox_profile_compat_for_pywalfox
      return 0
    fi
  fi

  run_cmd_as_user "$TARGET_USER" bash -lc 'pywalfox install' || log_warn "Could not install Pywalfox native messaging host"
  install_firefox_pywalfox_extension_policy
  ensure_firefox_profile_compat_for_pywalfox

  if ! pywalfox_firefox_extension_installed; then
    log_warn "Pywalfox extension policy was installed; restart Firefox to let it install the browser add-on"
  fi
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

configure_xdg_terminal_defaults() {
  local terminals_file="$TARGET_HOME/.config/xdg-terminals.list"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: write Ghostty terminal defaults to %s\n' "$terminals_file"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" sh -c '
    terminals_file="$1"
    mkdir -p "$(dirname "$terminals_file")"
    cat >"$terminals_file" <<EOF
# Terminal emulator preference order for xdg-terminal-exec
# The first found and valid terminal will be used
com.mitchellh.ghostty.desktop
Alacritty.desktop
kitty.desktop
org.gnome.Console.desktop
org.gnome.Terminal.desktop
EOF
  ' sh "$terminals_file"
}

configure_default_applications() {
  local text_editor_desktop="nvim.desktop"
  local -a text_mime_types=(
    text/plain
    text/english
    text/markdown
    text/x-makefile
    text/x-c++hdr
    text/x-c++src
    text/x-chdr
    text/x-csrc
    text/x-java
    text/x-moc
    text/x-pascal
    text/x-python
    text/x-tcl
    text/x-tex
    text/x-c
    text/x-c++
    text/xml
    application/json
    application/x-shellscript
    application/xml
  )
  local mime_type

  run_cmd_as_user "$TARGET_USER" xdg-mime default org.gnome.Nautilus.desktop inode/directory || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default org.gnome.Evince.desktop application/pdf || true
  for mime_type in "${text_mime_types[@]}"; do
    run_cmd_as_user "$TARGET_USER" xdg-mime default "$text_editor_desktop" "$mime_type" || true
  done
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/png || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/jpeg || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/gif || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/webp || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/bmp || true
  run_cmd_as_user "$TARGET_USER" xdg-mime default imv.desktop image/tiff || true

  configure_xdg_terminal_defaults
}

zen_profile_dirs() {
  local root profile_path
  for root in "$TARGET_HOME/.config/zen" "$TARGET_HOME/.zen"; do
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
  run_cmd_as_user "$TARGET_USER" systemctl --user daemon-reload || true
  run_cmd_as_user "$TARGET_USER" xdg-user-dirs-update || true
  configure_default_applications
  run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3 || true
  run_cmd_as_user "$TARGET_USER" gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
  patch_noctalia_starship_template_apply_if_needed
  install_fedora_jetbrains_mono_nerd_font
  install_noctalia_wallpaper_state
  install_starship_config
  install_niri_noctalia_seed_if_missing
  install_qt_theme_config
  if [[ -x "$TARGET_HOME/.local/bin/noctalia-sync-icon-theme" ]]; then
    run_cmd_as_user "$TARGET_USER" env HOME="$TARGET_HOME" "$TARGET_HOME/.local/bin/noctalia-sync-icon-theme" || true
  fi
  apply_noctalia_starship_palette_if_available
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
