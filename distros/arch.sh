#!/usr/bin/env bash
set -Eeuo pipefail

detect_aur_helper() {
  if [[ -n "${AUR_HELPER:-}" ]]; then
    printf '%s\n' "$AUR_HELPER"
    return 0
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

distro_name() {
  printf 'arch\n'
}

distro_preflight() {
  return 0
}

distro_bootstrap_tools() {
  mapfile -t packages < <(manifest_entries "$ROOT_DIR/packages/arch/official/bootstrap.pkgs")
  distro_install_official_packages "${packages[@]:-}"
}

enable_arch_multilib() {
  if grep -Eq '^\[multilib\]' /etc/pacman.conf 2>/dev/null; then
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: append multilib section to /etc/pacman.conf and run pacman -Syu\n'
    return 0
  fi
  sudo cp /etc/pacman.conf "/etc/pacman.conf.zz-linux-setup.$(timestamp).bak"
  sudo awk '
    BEGIN { print_multilib=1 }
    { print }
    END {
      if (print_multilib) {
        print ""
        print "[multilib]"
        print "Include = /etc/pacman.d/mirrorlist"
      }
    }
  ' /etc/pacman.conf | sudo tee /etc/pacman.conf >/dev/null
  sudo pacman -Syu --noconfirm
}

distro_enable_sources() {
  local source_id="$1"
  load_source_descriptor arch "$source_id" || die "Unknown Arch source: $source_id"
  case "$SOURCE_KIND" in
    aur)
      if [[ "$DRY_RUN" -eq 1 ]]; then
        AUR_HELPER="${AUR_HELPER:-<missing>}"
        return 0
      fi
      AUR_HELPER="$(detect_aur_helper || true)"
      [[ -n "$AUR_HELPER" ]] || die "AUR packages were selected but no supported AUR helper was found. Install paru or yay, then rerun."
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

distro_install_official_packages() {
  local -a packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  run_cmd sudo pacman -Syu --needed "${packages[@]}"
}

distro_install_copr_packages() {
  if [[ "$#" -gt 0 ]]; then
    die "COPR packages are not supported on Arch"
  fi
}

distro_install_terra_packages() {
  if [[ "$#" -gt 0 ]]; then
    die "Terra packages are not supported on Arch"
  fi
}

distro_install_rpmfusion_packages() {
  if [[ "$#" -gt 0 ]]; then
    die "RPM Fusion packages are not supported on Arch"
  fi
}

distro_install_vendor_packages() {
  if [[ "$#" -gt 0 ]]; then
    die "Vendor RPM packages are not supported on Arch"
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
  AUR_HELPER="$(detect_aur_helper || true)"
  [[ -n "$AUR_HELPER" ]] || die "AUR packages were selected but no supported AUR helper was found. Install paru or yay, then rerun."
  "$AUR_HELPER" -S --needed "${packages[@]}"
}

distro_install_flatpaks() {
  local app_id
  for app_id in "$@"; do
    [[ -n "$app_id" ]] || continue
    flatpak_install_or_update "$app_id" flathub
  done
}

distro_preview_plan() {
  local -a packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  run_cmd sudo pacman -Syu --needed --print "${packages[@]}"
}

distro_package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

distro_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

distro_service_exists() {
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  systemctl list-unit-files "${1}.service" --no-legend >/dev/null 2>&1
}

distro_enable_service() {
  run_cmd sudo systemctl enable "$1"
}

distro_enable_service_now() {
  run_cmd sudo systemctl enable --now "$1"
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
      have_cmd flatpak && flatpak remotes --columns=name 2>/dev/null | grep -Fx flathub >/dev/null 2>&1
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
  printf 'Reboot, open Plasma Login Manager, and choose the Niri session.\n'
}
