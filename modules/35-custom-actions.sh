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
  local local_bin dotnet_root dotnet_tools brew_bin
  printf -v local_bin '%q' "$TARGET_HOME/.local/bin"
  printf -v dotnet_root '%q' "$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME"
  printf -v dotnet_tools '%q' "$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME/tools"
  printf -v brew_bin '%q' "$BREW_PREFIX/bin"
  run_cmd_as_user "$TARGET_USER" bash -lc "export PATH=$local_bin:$dotnet_root:$dotnet_tools:$brew_bin:\"\$PATH\"; $script"
}

install_homebrew_if_needed() {
  if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Homebrew -> %s\n' "$BREW_PREFIX"
    return 0
  fi

  run_cmd_as_root mkdir -p "$BREW_PREFIX"
  run_cmd_as_root chown -R "$TARGET_USER:$TARGET_USER" /home/linuxbrew
  run_user_login_shell 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
}

install_brew_package() {
  local package="$1"
  install_homebrew_if_needed
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: brew install %s\n' "$package"
    return 0
  fi
  run_user_login_shell "brew list '$package' >/dev/null 2>&1 || brew install '$package'"
  run_user_login_shell "if brew list openssl@3 >/dev/null 2>&1 || brew list openssl >/dev/null 2>&1; then brew postinstall ca-certificates; fi"
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

  local toolbox_dir_q toolbox_bin_q symlink_q
  printf -v toolbox_dir_q '%q' "$toolbox_dir"
  printf -v toolbox_bin_q '%q' "$toolbox_bin"
  printf -v symlink_q '%q' "$symlink"

  run_user_login_shell "
    set -Eeuo pipefail
    api='https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release'
    api_response=\$(mktemp)
    trap 'rm -f \"\$api_response\"' EXIT
    curl -fsSL \"\$api\" -o \"\$api_response\"
    download_url=\$(jq -r 'to_entries[0].value[0].downloads.linux.link // empty' \"\$api_response\")
    version=\$(jq -r 'to_entries[0].value[0].version // empty' \"\$api_response\")
    if [[ -z \"\$download_url\" ]]; then
      echo 'Failed to parse JetBrains Toolbox Linux download URL from API response' >&2
      exit 1
    fi
    echo \"JetBrains Toolbox version: \${version:-unknown}\"
    echo \"JetBrains Toolbox download: \$download_url\"
    mkdir -p $toolbox_dir_q \"\$(dirname $symlink_q)\"
    curl -fsSL \"\$download_url\" | tar -xzf - -C $toolbox_dir_q --strip-components=1
    [[ -x $toolbox_bin_q ]]
    ln -sfn $toolbox_bin_q $symlink_q
    nohup $toolbox_bin_q >/dev/null 2>&1 &
  " || return 1

  [[ -x "$toolbox_bin" ]] || {
    log_warn "JetBrains Toolbox installer completed without creating $toolbox_bin."
    return 1
  }
  [[ -L "$symlink" || -x "$symlink" ]] || {
    log_warn "JetBrains Toolbox installer completed without creating $symlink."
    return 1
  }
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
  run_cmd_as_root dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine || true
  if ! distro_repo_enabled docker-ce; then
    run_cmd_as_root dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
  fi
  run_cmd_as_root dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  configure_docker_post_install
}

configure_docker_post_install() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd_as_root systemctl enable --now docker
    run_cmd_as_root usermod -aG docker "$TARGET_USER"
    return 0
  fi

  run_cmd_as_root systemctl daemon-reload
  run_cmd_as_root systemctl enable --now docker
  if ! id -nG "$TARGET_USER" | grep -qw docker; then
    run_cmd_as_root usermod -aG docker "$TARGET_USER"
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

  local metadata install_script floor channel_lines channel release_type failed=0
  metadata="$(mktemp "$CACHE_DIR/dotnet-releases.XXXXXX")"
  install_script="$(mktemp "$CACHE_DIR/dotnet-install.XXXXXX")"
  run_cmd curl -fsSL https://dotnetcli.azureedge.net/dotnet/release-metadata/releases-index.json -o "$metadata"
  run_cmd curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$install_script"
  run_cmd chmod 0755 "$install_script"

  channel_lines="$(dotnet_channel_versions "$metadata" || true)"
  if [[ -z "$channel_lines" ]]; then
    rm -f "$metadata" "$install_script"
    log_warn "No active .NET SDK channels were found in Microsoft release metadata."
    return 1
  fi

  floor="$(awk -F'\t' '$2 == "lts" {count++; if (count == 2) {print $1; exit}}' <<<"$channel_lines")"
  [[ -n "$floor" ]] || floor="$(tail -n1 <<<"$channel_lines" | cut -f1)"

  local -a channels=()
  while IFS=$'\t' read -r channel release_type; do
    [[ -n "$channel" ]] || continue
    if version_ge "$channel" "$floor"; then
      channels+=("$channel")
    fi
  done <<<"$channel_lines"

  if [[ "${#channels[@]}" -eq 0 ]]; then
    rm -f "$metadata" "$install_script"
    log_warn "No .NET SDK channels matched the active-channel selection floor."
    return 1
  fi

  log_info "Installing .NET SDK channels: $(join_by ', ' "${channels[@]}")"
  for channel in "${channels[@]}"; do
    if ! run_cmd_as_user "$TARGET_USER" bash "$install_script" --channel "$channel" --install-dir "$install_dir"; then
      failed=1
      log_warn "Failed to install .NET SDK channel: $channel"
    fi
  done
  rm -f "$metadata" "$install_script"

  if [[ ! -x "$install_dir/dotnet" ]]; then
    log_warn ".NET SDK installer completed without creating $install_dir/dotnet."
    return 1
  fi
  [[ "$failed" -eq 0 ]]
}

install_dotnet_tools() {
  local dotnet_bin="$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME/dotnet"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install .NET global tools: %s\n' "${DOTNET_TOOLS[*]}"
    return 0
  fi

  if [[ ! -x "$dotnet_bin" ]]; then
    log_warn ".NET SDK is not available at $dotnet_bin; running SDK install before installing tools."
    install_dotnet_sdks
  fi
  if [[ ! -x "$dotnet_bin" ]]; then
    log_warn ".NET SDK is still not available at $dotnet_bin; cannot install .NET global tools."
    return 1
  fi

  local tool failed=0
  for tool in "${DOTNET_TOOLS[@]}"; do
    if run_cmd_as_user "$TARGET_USER" "$dotnet_bin" tool update -g "$tool" || run_cmd_as_user "$TARGET_USER" "$dotnet_bin" tool install -g "$tool"; then
      continue
    fi
    failed=1
    log_warn "Failed to install .NET tool: $tool"
  done
  [[ "$failed" -eq 0 ]]
}

install_fedora_ms_fonts() {
  [[ "$DISTRO" == "fedora" ]] || return 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Microsoft core fonts RPM\n'
    return 0
  fi
  rpm -q msttcore-fonts-installer >/dev/null 2>&1 && return 0
  run_cmd_as_root dnf install -y curl cabextract fontconfig mkfontscale xorg-x11-font-utils xset
  local xset_wrapper_dir
  xset_wrapper_dir="$(mktemp -d "$CACHE_DIR/ms-fonts-xset.XXXXXX")"
  printf '#!/usr/bin/env sh\nexit 0\n' >"$xset_wrapper_dir/xset"
  chmod 0755 "$xset_wrapper_dir/xset"
  if ! run_cmd_as_root env "PATH=$xset_wrapper_dir:$PATH" rpm -i --nodigest --nosignature https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm; then
    rm -rf "$xset_wrapper_dir"
    return 1
  fi
  rm -rf "$xset_wrapper_dir"
}

install_fedora_build_tools() {
  [[ "$DISTRO" == "fedora" ]] || return 0
  run_cmd_as_root dnf group install -y development-tools
}

install_fedora_media_codecs() {
  [[ "$DISTRO" == "fedora" ]] || return 0
  run_cmd_as_root dnf swap -y ffmpeg-free ffmpeg --allowerasing
  run_cmd_as_root dnf install -y 'gstreamer1-plugins-bad-*' 'gstreamer1-plugins-good-*' gstreamer1-plugins-base gstreamer1-plugin-openh264 gstreamer1-libav 'lame*' --exclude=gstreamer1-plugins-bad-free-devel
  run_cmd_as_root dnf group install -y multimedia
  run_cmd_as_root dnf group install -y sound-and-video
  run_cmd_as_root dnf install -y ffmpeg-libs libva libva-utils openh264 gstreamer1-plugin-openh264 mozilla-openh264
  run_cmd_as_root dnf config-manager setopt fedora-cisco-openh264.enabled=1
}

run_custom_action() {
  local action="$1"
  case "$action" in
    brew:*) install_brew_package "${action#brew:}" ;;
    claude-code) install_claude_code ;;
    jetbrains-toolbox) install_jetbrains_toolbox ;;
    devtunnel) install_devtunnel ;;
    docker-fedora) install_fedora_docker ;;
    docker-post-install) configure_docker_post_install ;;
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
    append_warning "Optional custom action failed and was skipped: $action"
  done < <(read_plan_file "$PLAN_DIR/actions/actions.list")
}
