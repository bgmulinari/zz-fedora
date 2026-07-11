#!/usr/bin/env bash
set -Eeuo pipefail

fedora_release_file_is_supported() {
  local os_release_file="$1"
  [[ -f "$os_release_file" ]] || return 1
  local id
  id="$(awk -F= '$1=="ID"{gsub(/"/, "", $2); print tolower($2)}' "$os_release_file")"
  [[ "$id" == "fedora" ]]
}

require_fedora() {
  fedora_release_file_is_supported /etc/os-release || die "ZZ Fedora requires Fedora Linux"
  local release architecture
  release="$(awk -F= '$1=="VERSION_ID"{gsub(/"/, "", $2); print $2}' /etc/os-release)"
  architecture="$(uname -m)"
  array_contains "$release" "${SUPPORTED_FEDORA_RELEASES[@]}" || die "Unsupported Fedora release: ${release:-unknown}. Supported: $(join_by ', ' "${SUPPORTED_FEDORA_RELEASES[@]}")"
  array_contains "$architecture" "${SUPPORTED_ARCHITECTURES[@]}" || die "Unsupported architecture: ${architecture:-unknown}. Supported: $(join_by ', ' "${SUPPORTED_ARCHITECTURES[@]}")"
}

fedora_enable_sources() {
  local source_id="$1"
  load_source_descriptor "$source_id" || die "Unknown Fedora source: $source_id"
  local fedora_release=""
  if [[ "$DRY_RUN" -eq 0 ]]; then
    fedora_release="$(rpm -E %fedora)"
  else
    fedora_release="<fedora-release>"
  fi
  case "$SOURCE_KIND" in
    copr)
      if ! fedora_repo_enabled "$SOURCE_ID"; then
        log_progress "Enabling Fedora COPR source: $SOURCE_PROJECT"
        run_cmd_as_root dnf copr enable -y "$SOURCE_PROJECT"
      fi
      ;;
    terra)
      if ! fedora_repo_enabled "$SOURCE_ID"; then
        log_progress "Installing Terra repository bootstrap packages"
        run_cmd_as_root dnf install -y --nogpgcheck \
          --repofrompath 'terra-bootstrap,https://repos.fyralabs.com/terra$releasever' \
          --setopt=terra-bootstrap.gpgcheck=0 \
          --setopt=terra-bootstrap.repo_gpgcheck=0 \
          terra-gpg-keys \
          terra-release
        run_cmd_as_root rpm --import "/etc/pki/rpm-gpg/RPM-GPG-KEY-terra${fedora_release}"
      fi
      run_cmd_as_root dnf config-manager setopt terra.repo_gpgcheck=0
      run_cmd_as_root dnf config-manager setopt terra.excludepkgs=noctalia-greeter
      ;;
    rpmfusion)
      case "$SOURCE_ID" in
        rpmfusion-free)
          if ! fedora_repo_enabled "$SOURCE_ID"; then
            log_progress "Installing RPM Fusion free release package"
            run_cmd_as_root rpm --import https://download1.rpmfusion.org/free/fedora/RPM-GPG-KEY-rpmfusion-free-fedora-2020
            run_cmd_as_root dnf install -y --setopt=localpkg_gpgcheck=1 "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_release}.noarch.rpm"
          fi
          run_cmd_as_root dnf install -y rpmfusion-free-appstream-data
          ;;
        rpmfusion-nonfree)
          if ! fedora_repo_enabled "$SOURCE_ID"; then
            log_progress "Installing RPM Fusion nonfree release package"
            run_cmd_as_root rpm --import https://download1.rpmfusion.org/nonfree/fedora/RPM-GPG-KEY-rpmfusion-nonfree-fedora-2020
            run_cmd_as_root dnf install -y --setopt=localpkg_gpgcheck=1 "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_release}.noarch.rpm"
          fi
          run_cmd_as_root dnf install -y rpmfusion-nonfree-appstream-data
          ;;
      esac
      ;;
    vendor)
      if ! fedora_repo_enabled "$SOURCE_ID"; then
        case "$SOURCE_ID" in
          vendor:brave)
            log_progress "Adding Brave browser repository"
            run_cmd_as_root dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            ;;
          vendor:google-chrome)
            local defaults_file repo_file
            defaults_file="$(mktemp "$CACHE_DIR/google-chrome-defaults.XXXXXX")"
            repo_file="$(mktemp "$CACHE_DIR/google-chrome.repo.XXXXXX")"
            cat >"$defaults_file" <<'EOF'
repo_add_once="false"
EOF
            cat >"$repo_file" <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
            run_cmd_as_root bash -c 'rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null'
            log_progress "Adding Google Chrome repository"
            if [[ "$DRY_RUN" -eq 1 ]]; then
              printf 'DRY-RUN: install %s -> /etc/default/google-chrome\n' "$defaults_file"
              printf 'DRY-RUN: install %s -> /etc/yum.repos.d/google-chrome.repo\n' "$repo_file"
            else
              run_cmd_as_root install -Dm0644 "$defaults_file" /etc/default/google-chrome
              run_cmd_as_root install -Dm0644 "$repo_file" /etc/yum.repos.d/google-chrome.repo
            fi
            rm -f "$defaults_file" "$repo_file"
            ;;
          vendor:vscode)
            local repo_file
            repo_file="$(mktemp "$CACHE_DIR/vscode.repo.XXXXXX")"
            log_progress "Adding Visual Studio Code repository"
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
            local repo_file
            repo_file="$(mktemp "$CACHE_DIR/claude-desktop.repo.XXXXXX")"
            cat >"$repo_file" <<'EOF'
[claude-desktop]
name=Claude Desktop for Fedora/RHEL
baseurl=https://pkg.claude-desktop-debian.dev/rpm/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://pkg.claude-desktop-debian.dev/KEY.gpg
metadata_expire=1h
EOF
            run_cmd_as_root rpm --import https://pkg.claude-desktop-debian.dev/KEY.gpg
            log_progress "Adding Claude Desktop repository"
            if [[ "$DRY_RUN" -eq 1 ]]; then
              printf 'DRY-RUN: install %s -> /etc/yum.repos.d/claude-desktop.repo\n' "$repo_file"
            else
              run_cmd_as_root install -Dm0644 "$repo_file" /etc/yum.repos.d/claude-desktop.repo
            fi
            rm -f "$repo_file"
            ;;
        esac
      fi
      ;;
    cisco-openh264)
      log_progress "Enabling Cisco OpenH264 repository"
      run_cmd_as_root dnf config-manager setopt fedora-cisco-openh264.enabled=1
      ;;
    flatpak)
      if [[ "$SOURCE_ID" == "flathub" ]]; then
        flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      fi
      ;;
    official)
      ;;
    artifact)
      log_info "External artifact trust policy recorded: $SOURCE_ID ($SOURCE_GPG_POLICY)"
      ;;
    *)
      die "Unsupported Fedora source kind: $SOURCE_KIND"
      ;;
  esac
}

fedora_install_dnf_packages() {
  local -a packages=("$@")
  local -a install_args=(-y)
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  log_progress "Running DNF install transaction for ${#packages[@]} package entries"
  if [[ "$INSTALL_WEAK_DEPS" -eq 1 ]]; then
    run_cmd_as_root dnf install "${install_args[@]}" "${packages[@]}"
  else
    run_cmd_as_root dnf install "${install_args[@]}" --setopt=install_weak_deps=False "${packages[@]}"
  fi
}

fedora_apply_release_updates() {
  log_progress "Refreshing Fedora release metadata"
  run_cmd_as_root dnf makecache --refresh
  log_progress "Applying Fedora release updates"
  run_cmd_as_root dnf upgrade -y --refresh
}

fedora_install_flatpaks() {
  log_progress "Ensuring Flathub remote is ready"
  flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
  local app_id
  for app_id in "$@"; do
    [[ -n "$app_id" ]] || continue
    log_progress "Installing or updating Flatpak: $app_id"
    flatpak_install_or_update "$app_id" flathub
  done
}

fedora_preview_plan() {
  local -a packages=("$@")
  [[ "${#packages[@]}" -gt 0 ]] || return 0
  if [[ "$INSTALL_WEAK_DEPS" -eq 1 ]]; then
    run_cmd_as_root dnf install --assumeno "${packages[@]}"
  else
    run_cmd_as_root dnf install --assumeno --setopt=install_weak_deps=False "${packages[@]}"
  fi
}

fedora_package_installed() {
  rpm -q "$1" >/dev/null 2>&1 || rpm -q --whatprovides "$1" >/dev/null 2>&1
}

fedora_command_exists() {
  command -v "$1" >/dev/null 2>&1
}

fedora_service_exists() {
  systemd_unit_file_exists "$1"
}

fedora_enable_service() {
  log_progress "Enabling system service: $1"
  run_cmd_as_root systemctl enable "$1"
}

fedora_enable_service_now() {
  if [[ "${ZZ_INSTALLER_DEFER_START_SERVICES:-0}" -eq 1 ]]; then
    log_progress "Enabling system service for first boot: $1"
    run_cmd_as_root systemctl enable "$1"
    return 0
  fi
  log_progress "Enabling and starting system service: $1"
  run_cmd_as_root systemctl enable --now "$1"
}

fedora_repo_enabled() {
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
      flatpak_remote_usable flathub
      ;;
    *)
      return 1
      ;;
  esac
}

fedora_repoquery_provides() {
  run_cmd_as_root dnf repoquery --whatprovides "$1"
}

fedora_post_install_notes() {
  printf 'Reboot, open Noctalia Greeter, and choose the Niri session.\n'
}
