#!/usr/bin/env bash
set -Eeuo pipefail

CLAUDE_DESKTOP_PREFLIGHT_REPOSITORY_ID="claude-desktop-unofficial-preflight"
CLAUDE_DESKTOP_REPOSITORY_BASEURL='https://pkg.claude-desktop-debian.dev/rpm/$basearch'
CLAUDE_DESKTOP_GPG_KEY_URL="https://pkg.claude-desktop-debian.dev/KEY.gpg"
CLAUDE_DESKTOP_REPOSITORY_FILE="/etc/yum.repos.d/claude-desktop-unofficial.repo"
CLAUDE_DESKTOP_PACKAGE_NAME="claude-desktop-unofficial"
CLAUDE_DESKTOP_PACKAGE_ARCHITECTURE="x86_64"

fedora_release_file_is_supported() {
  local os_release_file="$1"
  [[ -f "$os_release_file" ]] || return 1
  local id
  id="$(awk -F= '$1=="ID"{gsub(/"/, "", $2); print tolower($2)}' "$os_release_file")"
  [[ "$id" == "fedora" ]]
}

fedora_release_is_supported() {
  local release="$1"
  [[ "$release" =~ ^[0-9]+$ ]] || return 1
  [[ "$MINIMUM_FEDORA_RELEASE" =~ ^[0-9]+$ ]] || return 1
  ((10#$release >= 10#$MINIMUM_FEDORA_RELEASE))
}

require_fedora() {
  fedora_release_file_is_supported /etc/os-release || die "ZZ Fedora requires Fedora Linux"
  local release architecture
  release="$(awk -F= '$1=="VERSION_ID"{gsub(/"/, "", $2); print $2}' /etc/os-release)"
  architecture="$(uname -m)"
  fedora_release_is_supported "$release" || die "Unsupported Fedora release: ${release:-unknown}. Minimum supported: $MINIMUM_FEDORA_RELEASE"
  array_contains "$architecture" "${SUPPORTED_ARCHITECTURES[@]}" || die "Unsupported architecture: ${architecture:-unknown}. Supported: $(join_by ', ' "${SUPPORTED_ARCHITECTURES[@]}")"
}

claude_desktop_repository_package_metadata() {
  dnf --assumeyes --quiet \
    --repofrompath="$CLAUDE_DESKTOP_PREFLIGHT_REPOSITORY_ID,$CLAUDE_DESKTOP_REPOSITORY_BASEURL" \
    --setopt="$CLAUDE_DESKTOP_PREFLIGHT_REPOSITORY_ID.gpgcheck=1" \
    --setopt="$CLAUDE_DESKTOP_PREFLIGHT_REPOSITORY_ID.repo_gpgcheck=1" \
    --setopt="$CLAUDE_DESKTOP_PREFLIGHT_REPOSITORY_ID.gpgkey=$CLAUDE_DESKTOP_GPG_KEY_URL" \
    --repo="$CLAUDE_DESKTOP_PREFLIGHT_REPOSITORY_ID" \
    repoquery \
    --available \
    --latest-limit=1 \
    --arch="$CLAUDE_DESKTOP_PACKAGE_ARCHITECTURE" \
    --qf '%{name}|%{arch}|%{version}|%{release}|%{sourcerpm}' \
    "$CLAUDE_DESKTOP_PACKAGE_NAME.$CLAUDE_DESKTOP_PACKAGE_ARCHITECTURE"
}

verify_claude_desktop_repository_package() {
  local architecture="${1:-}"
  local package_spec="$CLAUDE_DESKTOP_PACKAGE_NAME.$CLAUDE_DESKTOP_PACKAGE_ARCHITECTURE"

  [[ -n "$architecture" ]] || architecture="$(uname -m)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: verify exact repository package %s\n' "$package_spec"
    return 0
  fi
  if [[ "$architecture" != "$CLAUDE_DESKTOP_PACKAGE_ARCHITECTURE" ]]; then
    log_error "Claude Desktop package compatibility requires $CLAUDE_DESKTOP_PACKAGE_ARCHITECTURE; detected ${architecture:-unknown}."
    return 1
  fi

  local metadata package_name package_architecture package_version package_release source_rpm
  if ! metadata="$(claude_desktop_repository_package_metadata)" || [[ -z "$metadata" || "$metadata" == *$'\n'* ]]; then
    log_error "Claude Desktop repository does not expose exactly one package for $package_spec."
    return 1
  fi
  IFS='|' read -r package_name package_architecture package_version package_release source_rpm <<<"$metadata"

  if [[ "$package_name" != "$CLAUDE_DESKTOP_PACKAGE_NAME" \
    || "$package_architecture" != "$CLAUDE_DESKTOP_PACKAGE_ARCHITECTURE" \
    || "$source_rpm" != "$package_name-$package_version-$package_release.src.rpm" ]]; then
    log_error "Claude Desktop repository returned an unexpected package identity: $metadata"
    return 1
  fi

  log_info "Verified exact Claude Desktop repository package: $package_name-$package_version-$package_release.$package_architecture"
}

configure_claude_desktop_repository() {
  run_cmd_as_root rpm --import "$CLAUDE_DESKTOP_GPG_KEY_URL" || return 1
  if ! verify_claude_desktop_repository_package; then
    if [[ "$DRY_RUN" -eq 0 ]]; then
      run_cmd_as_root rm -f "$CLAUDE_DESKTOP_REPOSITORY_FILE" || return 1
    fi
    return 1
  fi

  log_progress "Adding Claude Desktop repository"
  write_root_file 0644 "$CLAUDE_DESKTOP_REPOSITORY_FILE" <<'EOF'
[claude-desktop-unofficial]
name=Claude Desktop (unofficial packaging) for Fedora/RHEL
baseurl=https://pkg.claude-desktop-debian.dev/rpm/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkg.claude-desktop-debian.dev/KEY.gpg
metadata_expire=1h
EOF
}

# The dnf repo id the copr plugin derives for an enabled "owner/project".
fedora_copr_repo_id() {
  local project="$1"
  printf 'copr:copr.fedorainfracloud.org:%s\n' "${project//\//:}"
}

# A COPR can expose another project as an enabled runtime dependency. Dnf
# gives those sections a `coprdep:` id, but they still serve the dependency
# project's packages and must receive the same ownership exclusions.
fedora_copr_repo_ids() {
  local project="$1"
  local suffix=":${project//\//:}"
  dnf repolist --enabled 2>/dev/null | awk -v suffix="$suffix" '
    $1 ~ /^copr(dep)?:/ &&
      length($1) >= length(suffix) &&
      substr($1, length($1) - length(suffix) + 1) == suffix {
      print $1
    }
  '
}

# Apply the source descriptor's excludepkgs list (compiled from the
# catalog TOML) to the dnf repo the source enables, so repository
# ownership rules live next to the source definition instead of being
# hard-coded per source id here.
fedora_apply_source_excludepkgs() {
  local repo_id="$1"
  [[ -n "${SOURCE_EXCLUDEPKGS:-}" ]] || return 0
  run_cmd_as_root dnf config-manager setopt "${repo_id}.excludepkgs=${SOURCE_EXCLUDEPKGS}"
}

fedora_apply_copr_source_excludepkgs() {
  local project="$1"
  [[ -n "${SOURCE_EXCLUDEPKGS:-}" ]] || return 0
  local direct_repo_id repo_id direct_seen=0
  direct_repo_id="$(fedora_copr_repo_id "$project")"
  while IFS= read -r repo_id; do
    [[ -n "$repo_id" ]] || continue
    [[ "$repo_id" == "$direct_repo_id" ]] && direct_seen=1
    fedora_apply_source_excludepkgs "$repo_id" || return 1
  done < <(fedora_copr_repo_ids "$project")
  if [[ "$direct_seen" -eq 0 ]]; then
    fedora_apply_source_excludepkgs "$direct_repo_id"
  fi
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
      fedora_apply_copr_source_excludepkgs "$SOURCE_PROJECT"
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
      # terra-release ships gpgcheck=1 and repo_gpgcheck=1, and Terra signs
      # its repomd.xml with the same RPM-GPG-KEY-terra<release> key that
      # terra-gpg-keys installs, so both package and metadata verification
      # stay exactly as the repository configures them from here on.
      fedora_apply_source_excludepkgs terra
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
      case "$SOURCE_ID" in
        vendor:claude-desktop)
          configure_claude_desktop_repository || return 1
          ;;
        *)
          if fedora_repo_enabled "$SOURCE_ID"; then
            return 0
          fi
          case "$SOURCE_ID" in
            vendor:brave)
              log_progress "Adding Brave browser repository"
              run_cmd_as_root dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
              ;;
            vendor:google-chrome)
              run_cmd_as_root bash -c 'rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null'
              log_progress "Adding Google Chrome repository"
              write_root_file 0644 /etc/default/google-chrome <<'EOF'
repo_add_once="false"
EOF
              write_root_file 0644 /etc/yum.repos.d/google-chrome.repo <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
              ;;
            vendor:vscode)
              log_progress "Adding Visual Studio Code repository"
              write_root_file 0644 /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
              ;;
          esac
          ;;
      esac
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

fedora_group_installed() {
  local group_spec="$1"
  local group_id="${group_spec#@}"
  group_id="${group_id#^}"

  LC_ALL=C dnf --cacheonly --disable-repo='*' group info --installed --hidden "$group_id" 2>/dev/null |
    awk -F: -v wanted="$group_id" '
      $1 ~ /^[[:space:]]*Id[[:space:]]*$/ {
        value = $2
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        if (value == wanted) {
          found_id = 1
        }
      }
      $1 ~ /^[[:space:]]*Installed[[:space:]]*$/ {
        value = $2
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        if (value == "yes") {
          installed = 1
        }
      }
      END { exit found_id && installed ? 0 : 1 }
    '
}

# The package name of a dnf spec, with any architecture suffix dropped.
rpm_spec_name() {
  local package_spec="$1"
  case "$package_spec" in
    *.noarch|*.x86_64|*.aarch64|*.i386|*.i486|*.i586|*.i686|*.ppc64le|*.s390x)
      printf '%s\n' "${package_spec%.*}"
      ;;
    *)
      printf '%s\n' "$package_spec"
      ;;
  esac
}

fedora_package_installed() {
  local package_spec="$1"
  case "$package_spec" in
    @*)
      fedora_group_installed "$package_spec"
      ;;
    *)
      rpm -q "$package_spec" >/dev/null 2>&1 && return 0
      # An arch-qualified spec names one package exactly; a bare name may
      # also be a virtual provide.
      [[ "$(rpm_spec_name "$package_spec")" == "$package_spec" ]] || return 1
      rpm -q --whatprovides "$package_spec" >/dev/null 2>&1
      ;;
  esac
}

fedora_service_exists() {
  systemd_unit_file_exists "$1"
}

fedora_enable_services_now() {
  local -a service_names=("$@")
  [[ "${#service_names[@]}" -gt 0 ]] || return 0
  if [[ "${ZZ_INSTALLER_DEFER_START_SERVICES:-0}" -eq 1 ]]; then
    log_progress "Enabling system services for first boot: ${service_names[*]}"
    run_cmd_as_root systemctl enable "${service_names[@]}"
    return 0
  fi
  log_progress "Enabling and starting system services: ${service_names[*]}"
  run_cmd_as_root systemctl enable --now "${service_names[@]}"
}

# An "owner/project" COPR counts as enabled only when dnf lists its exact
# repo id among the enabled repositories: `dnf copr list` also shows
# disabled projects, and a substring match would accept a project whose
# name merely starts with the wanted one (atim/starship-git for
# atim/starship). The header row dnf5 prints ("repo id ...") never equals
# a real id.
fedora_copr_repo_enabled() {
  local project="$1"
  local wanted
  wanted="$(fedora_copr_repo_id "$project")"
  dnf repolist --enabled 2>/dev/null | awk -v wanted="$wanted" '
    $1 == wanted { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

fedora_repo_enabled() {
  local repo_id="$1"
  case "$repo_id" in
    copr:*)
      fedora_copr_repo_enabled "${repo_id#copr:}"
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
      [[ -f "$CLAUDE_DESKTOP_REPOSITORY_FILE" ]]
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
