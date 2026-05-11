#!/usr/bin/env bash
set -Eeuo pipefail

detect_aur_helper() {
  if [[ -n "${AUR_HELPER:-}" ]]; then
    printf '%s\n' "$AUR_HELPER"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 0 && -n "${TARGET_USER:-}" && ( "$EUID" -eq 0 || "${USER:-}" != "$TARGET_USER" ) ]]; then
    local user_helper
    user_helper="$(run_cmd_as_user "$TARGET_USER" bash -lc 'if command -v paru >/dev/null 2>&1; then command -v paru; elif command -v yay >/dev/null 2>&1; then command -v yay; fi')"
    if [[ -n "$user_helper" ]]; then
      printf '%s\n' "$user_helper"
      return 0
    fi
  fi
  if command -v paru >/dev/null 2>&1; then
    printf 'paru\n'
    return 0
  fi
  if command -v yay >/dev/null 2>&1; then
    printf 'yay\n'
    return 0
  fi
  return 1
}

arch_pacman_keyring_ready() {
  [[ -s /etc/pacman.d/gnupg/pubring.gpg ]] || return 1
  run_cmd_as_root pacman-key --list-keys >/dev/null 2>&1
}

arch_prepare_pacman_keyring() {
  [[ "$DRY_RUN" -eq 0 ]] || return 0
  arch_pacman_keyring_ready && return 0
  run_cmd_as_root pacman-key --init || return 1
  run_cmd_as_root pacman-key --populate archlinux
}

arch_clean_unsigned_package_cache() {
  local cache_dir="${PACMAN_CACHE_DIR:-/var/cache/pacman/pkg}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: remove cached pacman packages without detached signatures from %s\n' "$cache_dir"
    return 0
  fi

  run_cmd_as_root bash -c '
    set -Eeuo pipefail
    cache_dir="$1"
    [[ -d "$cache_dir" ]] || exit 0
    find "$cache_dir" -maxdepth 1 -type f \
      \( -name "*.pkg.tar.zst" -o -name "*.pkg.tar.xz" -o -name "*.pkg.tar.gz" \) \
      ! -name "*.sig" -print0 |
      while IFS= read -r -d "" package_file; do
        [[ -f "$package_file.sig" ]] || rm -f "$package_file"
      done
  ' bash "$cache_dir"
}

arch_pacman_config_for_install() {
  local source_conf="${PACMAN_CONFIG:-/etc/pacman.conf}"
  local temp_conf
  temp_conf="$(mktemp "$CACHE_DIR/pacman-install.XXXXXX")"
  awk '
    BEGIN { inserted = 0 }
    /^\[core\]/ && !inserted {
      print "DisableSandboxFilesystem"
      print "DisableSandboxSyscalls"
      inserted = 1
    }
    { print }
    END {
      if (!inserted) {
        print "DisableSandboxFilesystem"
        print "DisableSandboxSyscalls"
      }
    }
  ' "$source_conf" >"$temp_conf"
  printf '%s\n' "$temp_conf"
}

arch_run_pacman_sync_install() {
  local pacman_config
  arch_prepare_pacman_keyring || return 1
  arch_clean_unsigned_package_cache || return 1
  pacman_config="$(arch_pacman_config_for_install)"
  local status=0
  run_cmd_as_root pacman --config "$pacman_config" -Syu --needed --noconfirm "$@" || status=$?
  rm -f "$pacman_config"
  return "$status"
}

bootstrap_arch_aur_helper() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: bootstrap yay-bin from AUR\n'
    AUR_HELPER="${AUR_HELPER:-yay}"
    return 0
  fi

  local build_dir detail_log target_group
  build_dir="$(mktemp -d "$CACHE_DIR/yay-bin.XXXXXX")"
  detail_log="$LOG_DIR/aur-helper-$(timestamp).log"
  target_group="$(id -gn "$TARGET_USER")"
  run_cmd_as_root chown "$TARGET_USER:$target_group" "$build_dir" || return 1
  if ! {
    run_cmd_as_user "$TARGET_USER" git clone https://aur.archlinux.org/yay-bin.git "$build_dir"
    run_cmd_as_user "$TARGET_USER" bash -lc 'cd "$1" && makepkg -si --needed --noconfirm' bash "$build_dir"
  } >"$detail_log" 2>&1; then
    cat "$detail_log" >&2
    return 1
  fi
  log_info "AUR helper bootstrap details: $detail_log"
  AUR_HELPER="$(detect_aur_helper || true)"
  [[ -n "$AUR_HELPER" ]] || die "AUR helper bootstrap completed but no supported helper was found."
}

ensure_arch_aur_helper() {
  AUR_HELPER="$(detect_aur_helper || true)"
  [[ -n "$AUR_HELPER" ]] && return 0
  bootstrap_arch_aur_helper
}

distro_name() {
  printf 'arch\n'
}

distro_preflight() {
  return 0
}

enable_arch_multilib() {
  if grep -Eq '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: append multilib section to /etc/pacman.conf and run pacman -Syu\n'
    return 0
  fi
  local temp_conf
  temp_conf="$(mktemp "$CACHE_DIR/pacman.conf.XXXXXX")"
  awk '
    BEGIN { print_multilib=1 }
    { print }
    END {
      if (print_multilib) {
        print ""
        print "[multilib]"
        print "Include = /etc/pacman.d/mirrorlist"
      }
    }
  ' /etc/pacman.conf >"$temp_conf"
  run_cmd_as_root cp /etc/pacman.conf "/etc/pacman.conf.zz-linux-setup.$(timestamp).bak"
  run_cmd_as_root install -m 0644 "$temp_conf" /etc/pacman.conf
  rm -f "$temp_conf"
  arch_run_pacman_sync_install
}

distro_enable_sources() {
  local source_id="$1"
  load_source_descriptor arch "$source_id" || die "Unknown Arch source: $source_id"
  case "$SOURCE_KIND" in
    aur)
      ensure_arch_aur_helper
      ;;
    multilib)
      enable_arch_multilib
      ;;
    flatpak)
      if [[ "$SOURCE_ID" == "flathub" ]]; then
        flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      fi
      ;;
    official)
      ;;
    *)
      die "Unsupported Arch source kind: $SOURCE_KIND"
      ;;
  esac
}

distro_install_pacman_packages() {
  local -a packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  if [[ "$DRY_RUN" -eq 0 ]]; then
    local -a missing_packages=()
    local package_name
    for package_name in "${packages[@]}"; do
      if ! pacman -Q "$package_name" >/dev/null 2>&1; then
        missing_packages+=("$package_name")
      fi
    done
    packages=("${missing_packages[@]}")
    [[ "${#packages[@]}" -gt 0 ]] || return 0
  fi
  arch_run_pacman_sync_install "${packages[@]}"
}

distro_install_dnf_packages() {
  if [[ "$#" -gt 0 ]]; then
    die "DNF packages are not supported on Arch"
  fi
}

distro_install_aur_packages() {
  local -a packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    local helper_preview
    helper_preview="$(detect_aur_helper || true)"
    printf 'DRY-RUN: %s -S --needed --noconfirm' "${helper_preview:-<missing-aur-helper>}"
    printf ' %q' "${packages[@]}"
    printf '\n'
    return 0
  fi
  ensure_arch_aur_helper
  local detail_log
  detail_log="$LOG_DIR/aur-packages-$(timestamp).log"
  if ! run_cmd_as_user "$TARGET_USER" "$AUR_HELPER" -S --needed --noconfirm "${packages[@]}" >"$detail_log" 2>&1; then
    cat "$detail_log" >&2
    return 1
  fi
  log_info "AUR package install details: $detail_log"
}

distro_install_flatpaks() {
  flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
  local app_id
  for app_id in "$@"; do
    [[ -n "$app_id" ]] || continue
    flatpak_install_or_update "$app_id" flathub
  done
}

distro_preview_plan() {
  local -a packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  run_cmd_as_root pacman -Syu --needed --print "${packages[@]}"
}

distro_package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

distro_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

distro_service_exists() {
  systemd_unit_file_exists "$1"
}

distro_enable_service() {
  run_cmd_as_root systemctl enable "$1"
}

distro_enable_service_now() {
  run_cmd_as_root systemctl enable --now "$1"
}

distro_repo_enabled() {
  local repo_id="$1"
  case "$repo_id" in
    aur)
      detect_aur_helper >/dev/null 2>&1
      ;;
    multilib)
      grep -Eq '^\[multilib\]' /etc/pacman.conf 2>/dev/null
      ;;
    flathub)
      flatpak_remote_usable flathub
      ;;
    *)
      return 1
      ;;
  esac
}

distro_repoquery_provides() {
  run_cmd pacman -Qs "$1"
}

distro_post_install_notes() {
  printf 'Reboot, open SDDM, and choose the Niri session.\n'
}
