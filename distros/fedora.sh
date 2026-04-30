#!/usr/bin/env bash
set -Eeuo pipefail

distro_name() {
  printf 'fedora\n'
}

distro_preflight() {
  return 0
}

distro_enable_sources() {
  local source_id="$1"
  load_source_descriptor fedora "$source_id" || die "Unknown Fedora source: $source_id"
  local fedora_release=""
  if [[ "$DRY_RUN" -eq 0 ]]; then
    fedora_release="$(rpm -E %fedora)"
  else
    fedora_release="<fedora-release>"
  fi
  case "$SOURCE_KIND" in
    copr)
      if ! distro_repo_enabled "$SOURCE_ID"; then
        run_cmd_as_root dnf copr enable -y "$SOURCE_PROJECT"
      fi
      ;;
    terra)
      if ! distro_repo_enabled "$SOURCE_ID"; then
        run_cmd_as_root dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
      fi
      ;;
    rpmfusion)
      if ! distro_repo_enabled "$SOURCE_ID"; then
        case "$SOURCE_ID" in
          rpmfusion-free)
            run_cmd_as_root dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_release}.noarch.rpm"
            ;;
          rpmfusion-nonfree)
            run_cmd_as_root dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_release}.noarch.rpm"
            ;;
        esac
      fi
      ;;
    vendor)
      if ! distro_repo_enabled "$SOURCE_ID"; then
        case "$SOURCE_ID" in
          vendor:brave)
            run_cmd_as_root dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            ;;
          vendor:google-chrome)
            local repo_file
            repo_file="$(mktemp "$CACHE_DIR/google-chrome.repo.XXXXXX")"
            cat >"$repo_file" <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
            if [[ "$DRY_RUN" -eq 1 ]]; then
              printf 'DRY-RUN: install %s -> /etc/yum.repos.d/google-chrome.repo\n' "$repo_file"
            else
              run_cmd_as_root install -Dm0644 "$repo_file" /etc/yum.repos.d/google-chrome.repo
            fi
            rm -f "$repo_file"
            ;;
          vendor:vscode)
            local repo_file
            repo_file="$(mktemp "$CACHE_DIR/vscode.repo.XXXXXX")"
            cat >"$repo_file" <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
            if [[ "$DRY_RUN" -eq 1 ]]; then
              printf 'DRY-RUN: install %s -> /etc/yum.repos.d/vscode.repo\n' "$repo_file"
            else
              run_cmd_as_root install -Dm0644 "$repo_file" /etc/yum.repos.d/vscode.repo
            fi
            rm -f "$repo_file"
            ;;
          vendor:claude-desktop)
            run_cmd_as_root curl -fsSL https://aaddrick.github.io/claude-desktop-debian/rpm/claude-desktop.repo -o /etc/yum.repos.d/claude-desktop.repo
            ;;
        esac
      fi
      ;;
    cisco-openh264)
      run_cmd_as_root dnf config-manager setopt fedora-cisco-openh264.enabled=1
      ;;
    flatpak)
      if [[ "$SOURCE_ID" == "flathub" ]]; then
        flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      fi
      ;;
    official)
      ;;
    *)
      die "Unsupported Fedora source kind: $SOURCE_KIND"
      ;;
  esac
}

distro_install_dnf_packages() {
  local -a packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  if [[ "$INSTALL_WEAK_DEPS" -eq 1 ]]; then
    run_cmd_as_root dnf install -y "${packages[@]}"
  else
    run_cmd_as_root dnf install -y --setopt=install_weak_deps=False "${packages[@]}"
  fi
}

distro_install_aur_packages() {
  if [[ "$#" -gt 0 ]]; then
    die "AUR packages are not supported on Fedora"
  fi
}

distro_install_pacman_packages() {
  if [[ "$#" -gt 0 ]]; then
    die "Pacman packages are not supported on Fedora"
  fi
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
  if [[ "$INSTALL_WEAK_DEPS" -eq 1 ]]; then
    run_cmd_as_root dnf install --assumeno "${packages[@]}"
  else
    run_cmd_as_root dnf install --assumeno --setopt=install_weak_deps=False "${packages[@]}"
  fi
}

distro_package_installed() {
  rpm -q "$1" >/dev/null 2>&1
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
    copr:*)
      dnf copr list 2>/dev/null | grep -F "${repo_id#copr:}" >/dev/null 2>&1
      ;;
    terra)
      dnf repolist 2>/dev/null | grep -E '^terra' >/dev/null 2>&1
      ;;
    rpmfusion-free)
      dnf repolist 2>/dev/null | grep -F 'rpmfusion-free' >/dev/null 2>&1
      ;;
    rpmfusion-nonfree)
      dnf repolist 2>/dev/null | grep -F 'rpmfusion-nonfree' >/dev/null 2>&1
      ;;
    vendor:brave)
      [[ -f /etc/yum.repos.d/brave-browser.repo ]]
      ;;
    vendor:google-chrome)
      [[ -f /etc/yum.repos.d/google-chrome.repo ]]
      ;;
    vendor:vscode)
      [[ -f /etc/yum.repos.d/vscode.repo ]]
      ;;
    vendor:claude-desktop)
      [[ -f /etc/yum.repos.d/claude-desktop.repo ]]
      ;;
    docker-ce)
      dnf repolist 2>/dev/null | grep -F 'docker-ce' >/dev/null 2>&1
      ;;
    cisco-openh264)
      dnf repolist --enabled 2>/dev/null | grep -F 'fedora-cisco-openh264' >/dev/null 2>&1
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
  run_cmd_as_root dnf repoquery --whatprovides "$1"
}

distro_post_install_notes() {
  printf 'Reboot, open SDDM, and choose the Niri session.\n'
}
