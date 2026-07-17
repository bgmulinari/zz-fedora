#!/usr/bin/env bash
set -Eeuo pipefail

# Nerd Font custom actions.

jetbrains_mono_nerd_font_dir() {
  printf '%s\n' "$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerdFont"
}

jetbrains_mono_nerd_font_installed() {
  local font_dir
  font_dir="$(jetbrains_mono_nerd_font_dir)"
  [[ -d "$font_dir" ]] || return 1
  find "$font_dir" -maxdepth 1 -type f -name 'JetBrainsMonoNerdFont*.ttf' -print -quit 2>/dev/null | grep -q .
}

install_jetbrains_mono_nerd_font() {
  local version="3.4.0"
  local checksum="76f05ff3ace48a464a6ca57977998784ff7bdbb65a6d915d7e401cd3927c493c"
  local font_dir download_url
  font_dir="$(jetbrains_mono_nerd_font_dir)"
  download_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v${version}/JetBrainsMono.zip"

  if jetbrains_mono_nerd_font_installed; then
    log_info "JetBrains Mono Nerd Font already installed at $font_dir"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install JetBrains Mono Nerd Font v%s -> %s\n' "$version" "$font_dir"
    printf 'DRY-RUN: verify sha256 %s\n' "$checksum"
    return 0
  fi

  log_progress "Installing JetBrains Mono Nerd Font"
  run_cmd_as_user "$TARGET_USER" mkdir -p "$font_dir"
  run_cmd_as_user "$TARGET_USER" bash -c "
    set -Eeuo pipefail
    tmp_zip=\$(mktemp --suffix=.zip)
    trap 'rm -f \"\$tmp_zip\"' EXIT
    curl -fsSL '$download_url' -o \"\$tmp_zip\"
    printf '%s  %s\n' '$checksum' \"\$tmp_zip\" | sha256sum -c -
    unzip -o \"\$tmp_zip\" -d '$font_dir'
    find '$font_dir' -maxdepth 1 -type f ! -name '*.ttf' ! -name '*.otf' -delete
    fc-cache -f '$font_dir'
  "
  jetbrains_mono_nerd_font_installed || die "JetBrains Mono Nerd Font action completed but no font files were found in $font_dir."
}

register_action "jetbrains-mono-nerd-font" install_jetbrains_mono_nerd_font jetbrains_mono_nerd_font_installed
