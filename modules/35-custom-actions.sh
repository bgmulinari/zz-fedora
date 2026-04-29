#!/usr/bin/env bash
set -Eeuo pipefail

BREW_PREFIX="/home/linuxbrew/.linuxbrew"
DOTNET_INSTALL_DIR_NAME=".dotnet"
DOTNET_TOOLS=(
  csharp-ls
  dotnet-ef
  dotnet-repl
  ilspycmd
  linux-dev-certs
  powershell
  volo.abp.studio.cli
)

action_plan_has() {
  local expected="$1"
  [[ -f "$PLAN_DIR/actions/actions.list" ]] || return 1
  grep -Fx "$expected" "$PLAN_DIR/actions/actions.list" >/dev/null 2>&1
}

run_user_login_shell() {
  local script="$1"
  run_cmd_as_user "$TARGET_USER" bash -lc "$script"
}

install_homebrew_if_needed() {
  if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Homebrew -> %s\n' "$BREW_PREFIX"
    return 0
  fi

  run_cmd sudo mkdir -p "$BREW_PREFIX"
  run_cmd sudo chown -R "$TARGET_USER:$TARGET_USER" /home/linuxbrew
  run_cmd_as_user "$TARGET_USER" bash -lc 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
}

install_brew_package() {
  local package="$1"
  install_homebrew_if_needed
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: brew install %s\n' "$package"
    return 0
  fi
  run_user_login_shell "export PATH='$BREW_PREFIX/bin':\"\$PATH\"; brew list '$package' >/dev/null 2>&1 || brew install '$package'"
}

install_claude_code() {
  local claude_bin="$TARGET_HOME/.local/bin/claude"
  [[ -x "$claude_bin" ]] && return 0
  run_cmd_as_user "$TARGET_USER" bash -lc 'curl -fsSL https://claude.ai/install.sh | bash'
}

install_jetbrains_toolbox() {
  local toolbox_dir="$TARGET_HOME/.local/share/JetBrains/Toolbox"
  local toolbox_bin="$toolbox_dir/bin/jetbrains-toolbox"
  local symlink="$TARGET_HOME/.local/bin/jetbrains-toolbox"
  [[ -x "$toolbox_bin" ]] && return 0

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install JetBrains Toolbox -> %s\n' "$toolbox_dir"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" bash -lc "
    set -Eeuo pipefail
    api='https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release'
    download_url=\$(curl -fsSL \"\$api\" | grep -Po '\"linux\":\\s*\\{[^}]*\"link\":\\s*\"\\K[^\"]+' | head -1)
    [[ -n \"\$download_url\" ]]
    mkdir -p '$toolbox_dir' '$TARGET_HOME/.local/bin'
    curl -fsSL \"\$download_url\" | tar -xzf - -C '$toolbox_dir' --strip-components=1
    ln -sfn '$toolbox_bin' '$symlink'
  "
}

install_devtunnel() {
  local devtunnel_bin="$TARGET_HOME/.local/bin/devtunnel"
  [[ -x "$devtunnel_bin" ]] && return 0
  run_cmd_as_user "$TARGET_USER" mkdir -p "$TARGET_HOME/.local/bin"
  run_cmd_as_user "$TARGET_USER" curl -fsSL https://aka.ms/TunnelsCliDownload/linux-x64 -o "$devtunnel_bin"
  run_cmd_as_user "$TARGET_USER" chmod +x "$devtunnel_bin"
}

install_fedora_docker() {
  [[ "$DISTRO" == "fedora" ]] || return 0
  run_cmd sudo dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine || true
  if ! distro_repo_enabled docker-ce; then
    run_cmd sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
  fi
  run_cmd sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  configure_docker_post_install
}

configure_docker_post_install() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: sudo systemctl enable --now docker\n'
    printf 'DRY-RUN: sudo usermod -aG docker %s\n' "$TARGET_USER"
    return 0
  fi

  run_cmd sudo systemctl daemon-reload
  run_cmd sudo systemctl enable --now docker
  if ! id -nG "$TARGET_USER" | grep -qw docker; then
    run_cmd sudo usermod -aG docker "$TARGET_USER"
  fi
}

dotnet_channel_versions() {
  local metadata_file="$1"
  jq -r '
    .["releases-index"][]
    | select(.["support-phase"] == "active" or .["support-phase"] == "maintenance")
    | [.["channel-version"], .["release-type"]]
    | @tsv
  ' "$metadata_file" | sort -Vr
}

version_ge() {
  local version="$1"
  local floor="$2"
  [[ "$(printf '%s\n%s\n' "$floor" "$version" | sort -V | head -n1)" == "$floor" ]]
}

install_dotnet_sdks() {
  local install_dir="$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install active .NET SDK channels -> %s\n' "$install_dir"
    return 0
  fi

  local metadata install_script floor channels channel release_type
  metadata="$(mktemp "$CACHE_DIR/dotnet-releases.XXXXXX")"
  install_script="$(mktemp "$CACHE_DIR/dotnet-install.XXXXXX")"
  curl -fsSL https://dotnetcli.azureedge.net/dotnet/release-metadata/releases-index.json -o "$metadata"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$install_script"
  chmod +x "$install_script"

  floor="$(dotnet_channel_versions "$metadata" | awk -F'\t' '$2 == "lts" {print $1; count++; if (count == 2) exit}' || true)"
  [[ -n "$floor" ]] || floor="$(dotnet_channel_versions "$metadata" | tail -n1 | cut -f1)"

  while IFS=$'\t' read -r channel release_type; do
    [[ -n "$channel" ]] || continue
    if version_ge "$channel" "$floor"; then
      run_cmd_as_user "$TARGET_USER" bash "$install_script" --channel "$channel" --install-dir "$install_dir"
    fi
  done < <(dotnet_channel_versions "$metadata")

  rm -f "$metadata" "$install_script"
}

install_dotnet_tools() {
  action_plan_has "dotnet-sdk" || install_dotnet_sdks
  local dotnet_bin="$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME/dotnet"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install .NET global tools: %s\n' "${DOTNET_TOOLS[*]}"
    return 0
  fi
  local tool
  for tool in "${DOTNET_TOOLS[@]}"; do
    run_cmd_as_user "$TARGET_USER" "$dotnet_bin" tool install -g "$tool" || log_warn "Failed to install .NET tool: $tool"
  done
}

install_fedora_ms_fonts() {
  [[ "$DISTRO" == "fedora" ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Microsoft core fonts RPM\n'
    return 0
  fi
  rpm -q msttcore-fonts-installer >/dev/null 2>&1 && return 0
  run_cmd sudo dnf install -y curl cabextract xorg-x11-font-utils fontconfig
  run_cmd sudo rpm -i --nodigest --nosignature https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
}

install_fedora_build_tools() {
  [[ "$DISTRO" == "fedora" ]] || return 0
  run_cmd sudo dnf group install -y development-tools
}

install_fedora_media_codecs() {
  [[ "$DISTRO" == "fedora" ]] || return 0
  run_cmd sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
  run_cmd sudo dnf install -y 'gstreamer1-plugins-bad-*' 'gstreamer1-plugins-good-*' gstreamer1-plugins-base gstreamer1-plugin-openh264 gstreamer1-libav 'lame*' --exclude=gstreamer1-plugins-bad-free-devel
  run_cmd sudo dnf group install -y multimedia
  run_cmd sudo dnf group install -y sound-and-video
  run_cmd sudo dnf install -y ffmpeg-libs libva libva-utils openh264 gstreamer1-plugin-openh264 mozilla-openh264
  run_cmd sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
}

run_custom_action() {
  local action="$1"
  case "$action" in
    brew:*) install_brew_package "${action#brew:}" ;;
    claude-code) install_claude_code ;;
    jetbrains-toolbox) install_jetbrains_toolbox ;;
    devtunnel) install_devtunnel ;;
    docker-fedora) install_fedora_docker ;;
    docker-arch) configure_docker_post_install ;;
    dotnet-sdk) install_dotnet_sdks ;;
    dotnet-tools) install_dotnet_tools ;;
    build-tools-fedora) install_fedora_build_tools ;;
    ms-fonts-fedora) install_fedora_ms_fonts ;;
    media-codecs-fedora) install_fedora_media_codecs ;;
    *) die "Unknown custom action: $action" ;;
  esac
}

module_35_custom_actions() {
  [[ -f "$PLAN_DIR/actions/actions.list" ]] || return 0
  local action
  while IFS= read -r action; do
    [[ -n "$action" ]] || continue
    printf 'action: %s\n' "$action"
    if run_custom_action "$action"; then
      continue
    fi
    log_warn "Optional custom action failed and will be skipped for now: $action"
  done < <(read_plan_file "$PLAN_DIR/actions/actions.list")
}
