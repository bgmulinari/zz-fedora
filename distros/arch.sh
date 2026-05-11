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

bootstrap_arch_aur_helper() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: bootstrap yay-bin from AUR\n'
    AUR_HELPER="${AUR_HELPER:-yay}"
    return 0
  fi

  local build_dir target_group
  build_dir="$(mktemp -d "$CACHE_DIR/yay-bin.XXXXXX")"
  target_group="$(id -gn "$TARGET_USER")"
  run_cmd_as_root chown "$TARGET_USER:$target_group" "$build_dir"
  run_cmd_as_user "$TARGET_USER" git clone https://aur.archlinux.org/yay-bin.git "$build_dir"
  run_cmd_as_user "$TARGET_USER" bash -lc 'cd "$1" && makepkg -si --needed --noconfirm' bash "$build_dir"
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
  run_cmd_as_root pacman -Syu --noconfirm
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
  run_cmd_as_root pacman -Syu --needed --noconfirm "${packages[@]}"
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
    printf 'DRY-RUN: %s -S --needed' "${helper_preview:-<missing-aur-helper>}"
    printf ' %q' "${packages[@]}"
    printf '\n'
    return 0
  fi
  ensure_arch_aur_helper
  run_cmd_as_user "$TARGET_USER" "$AUR_HELPER" -S --needed "${packages[@]}"
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
