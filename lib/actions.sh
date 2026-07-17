#!/usr/bin/env bash
set -Eeuo pipefail

BREW_PREFIX="/home/linuxbrew/.linuxbrew"
HOMEBREW_INSTALL_COMMIT="c7952e40b7957268f61643152f4db725379b292e"
HOMEBREW_INSTALL_SHA256="99287f194a8b3c9e6b0203a11a5fa54518be57209343e6bb954dec4635796d9d"
DOTNET_INSTALL_DIR_NAME=".dotnet"
DOTNET_INSTALL_COMMIT="4a37a9f9d1a061fc389d6515100336db4e51710e"
DOTNET_INSTALL_SHA256="082f7685e156738a1b2e2ed8381a621870d4ce8e8c59278034556f05c186eb2e"
DOTNET_TOOLS=(
  csharp-ls
  dotnet-ef
  dotnet-repl
  ilspycmd
  linux-dev-certs
  powershell
  volo.abp.studio.cli
)
DISCORD_RPM_URL="https://discord.com/api/download?platform=linux&format=rpm"
NOCTALIA_GREETER_FEDORA_COPR_REPO="copr:copr.fedorainfracloud.org:lionheartp:Hyprland"
NOCTALIA_GREETER_PACKAGE="noctalia-greeter"
NOCTALIA_GREETER_USER="greeter"
NOCTALIA_GREETER_STATE_DIR="/var/lib/noctalia-greeter"
NOCTALIA_GREETER_SESSION_BIN="/usr/bin/noctalia-greeter-session"
NOCTALIA_GREETD_CONFIG="/etc/greetd/config.toml"
PYWALFOX_EXTENSION_ID="pywalfox@frewacom.org"
PYWALFOX_EXTENSION_URL="https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"

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

  log_progress "Installing Homebrew"
  run_cmd_as_root mkdir -p "$BREW_PREFIX"
  run_cmd_as_root chown -R "$TARGET_USER:$TARGET_USER" /home/linuxbrew
  local install_script install_script_q
  install_script="$(mktemp "$CACHE_DIR/homebrew-install.XXXXXX")"
  if ! run_cmd curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/$HOMEBREW_INSTALL_COMMIT/install.sh" -o "$install_script" \
    || ! printf '%s  %s\n' "$HOMEBREW_INSTALL_SHA256" "$install_script" | sha256sum -c -; then
    rm -f "$install_script"
    return 1
  fi
  run_cmd chmod 0755 "$install_script"
  printf -v install_script_q '%q' "$install_script"
  run_user_login_shell "NONINTERACTIVE=1 /bin/bash $install_script_q"
  rm -f "$install_script"
}

install_brew_package() {
  local package="$1"
  log_progress "Installing Homebrew package: $package"
  install_homebrew_if_needed
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: brew install %s\n' "$package"
    return 0
  fi
  run_user_login_shell "brew list '$package' >/dev/null 2>&1 || brew install '$package'"
  run_user_login_shell "if brew list openssl@3 >/dev/null 2>&1 || brew list openssl >/dev/null 2>&1; then brew postinstall ca-certificates; fi"
}

install_npm_global_package() {
  local package="$1"
  log_progress "Installing npm global package: $package"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: npm install -g %s\n' "$package"
    return 0
  fi
  run_cmd_as_root npm install -g "$package"
}

vscode_extension_installed() {
  local extension="$1"
  local installed_extensions
  installed_extensions="$(run_cmd_as_user "$TARGET_USER" code --list-extensions 2>/dev/null)" || return 1
  grep -Fxi -- "$extension" <<<"$installed_extensions" >/dev/null 2>&1
}

install_vscode_extension() {
  local extension="$1"
  [[ -n "$extension" ]] || die "Visual Studio Code extension ID cannot be empty."

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Visual Studio Code extension for %s: %s\n' "$TARGET_USER" "$extension"
    return 0
  fi

  if vscode_extension_installed "$extension"; then
    log_info "Visual Studio Code extension is already installed: $extension"
    return 0
  fi

  log_progress "Installing Visual Studio Code extension: $extension"
  run_cmd_as_user "$TARGET_USER" code --install-extension "$extension"
}

pywalfox_bin() {
  printf '%s\n' "$TARGET_HOME/.local/bin/pywalfox"
}

pywalfox_native_manifest() {
  printf '%s\n' "$TARGET_HOME/.mozilla/native-messaging-hosts/pywalfox.json"
}

firefox_policies_file() {
  printf '%s\n' "${FIREFOX_POLICIES_FILE:-/etc/firefox/policies/policies.json}"
}

install_firefox_pywalfox_policy() {
  local policies_file temp_file
  policies_file="$(firefox_policies_file)"
  temp_file="$(mktemp "$CACHE_DIR/firefox-policies.XXXXXX")"

  if [[ -f "$policies_file" ]]; then
    if ! jq \
      --arg extension_id "$PYWALFOX_EXTENSION_ID" \
      --arg extension_url "$PYWALFOX_EXTENSION_URL" \
      '.policies = ((.policies // {}) + {
        ExtensionSettings: ((.policies.ExtensionSettings // {}) + {
          ($extension_id): {
            installation_mode: "normal_installed",
            install_url: $extension_url
          }
        })
      })' \
      "$policies_file" >"$temp_file"; then
      rm -f "$temp_file"
      return 1
    fi
  else
    jq -n \
      --arg extension_id "$PYWALFOX_EXTENSION_ID" \
      --arg extension_url "$PYWALFOX_EXTENSION_URL" \
      '{
        policies: {
          ExtensionSettings: {
            ($extension_id): {
              installation_mode: "normal_installed",
              install_url: $extension_url
            }
          }
        }
      }' >"$temp_file"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install Firefox Pywalfox extension policy -> %s\n' "$policies_file"
    rm -f "$temp_file"
    return 0
  fi

  if [[ -n "${FIREFOX_POLICIES_FILE:-}" ]]; then
    run_cmd mkdir -p "$(dirname "$policies_file")"
    run_cmd install -m 0644 "$temp_file" "$policies_file"
  else
    run_cmd_as_root mkdir -p "$(dirname "$policies_file")"
    run_cmd_as_root install -m 0644 "$temp_file" "$policies_file"
  fi
  rm -f "$temp_file"
}

install_pywalfox() {
  local executable
  executable="$(pywalfox_bin)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install or upgrade Pywalfox with pipx for %s\n' "$TARGET_USER"
    printf 'DRY-RUN: register Pywalfox native messaging host -> %s\n' "$(pywalfox_native_manifest)"
    install_firefox_pywalfox_policy
    return 0
  fi

  log_progress "Installing Pywalfox native messaging host"
  run_user_login_shell "pipx upgrade pywalfox || pipx install --force pywalfox" || return 1
  [[ -x "$executable" ]] || {
    log_warn "Pywalfox installation did not create $executable."
    return 1
  }
  run_cmd_as_user "$TARGET_USER" "$executable" install --executable "$executable" || return 1
  install_firefox_pywalfox_policy
}

pywalfox_installed() {
  local executable manifest policies_file
  executable="$(pywalfox_bin)"
  manifest="$(pywalfox_native_manifest)"
  policies_file="$(firefox_policies_file)"

  [[ -x "$executable" && -f "$manifest" && -f "$policies_file" ]] || return 1
  jq -e \
    --arg executable "$executable" \
    --arg extension_id "$PYWALFOX_EXTENSION_ID" \
    '(.path == $executable)
      and ((((.allowed_extensions // []) | index($extension_id))) != null)' \
    "$manifest" >/dev/null 2>&1 || return 1
  jq -e \
    --arg extension_id "$PYWALFOX_EXTENSION_ID" \
    --arg extension_url "$PYWALFOX_EXTENSION_URL" \
    '(.policies.ExtensionSettings[$extension_id].installation_mode == "normal_installed")
      and (.policies.ExtensionSettings[$extension_id].install_url == $extension_url)' \
    "$policies_file" >/dev/null 2>&1
}

install_claude_code() {
  local claude_bin="$TARGET_HOME/.local/bin/claude"
  [[ -x "$claude_bin" ]] && return 0
  log_progress "Installing Claude Code"
  local install_script
  install_script="$(mktemp "$CACHE_DIR/claude-install.XXXXXX")"
  if ! run_cmd curl -fsSL https://claude.ai/install.sh -o "$install_script"; then
    rm -f "$install_script"
    return 1
  fi
  run_cmd chmod 0755 "$install_script"
  run_cmd_as_user "$TARGET_USER" bash "$install_script"
  rm -f "$install_script"
}

jetbrains_toolbox_autostart_file() {
  printf '%s\n' "$TARGET_HOME/.config/autostart/jetbrains-toolbox.desktop"
}

disable_jetbrains_toolbox_autostart() {
  local autostart_file
  autostart_file="$(jetbrains_toolbox_autostart_file)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: remove JetBrains Toolbox autostart entry -> %s\n' "$autostart_file"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" rm -f "$autostart_file"
}

wait_for_jetbrains_toolbox_autostart() {
  local autostart_file attempt
  autostart_file="$(jetbrains_toolbox_autostart_file)"

  for ((attempt = 0; attempt < 100; attempt++)); do
    [[ -e "$autostart_file" ]] && return 0
    sleep 0.1
  done
}

install_jetbrains_toolbox() {
  local toolbox_dir="$TARGET_HOME/.local/share/JetBrains/Toolbox"
  local toolbox_bin="$toolbox_dir/bin/jetbrains-toolbox"
  local symlink="$TARGET_HOME/.local/bin/jetbrains-toolbox"
  if [[ -x "$toolbox_bin" ]]; then
    disable_jetbrains_toolbox_autostart
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install JetBrains Toolbox -> %s\n' "$toolbox_dir"
    disable_jetbrains_toolbox_autostart
    return 0
  fi

  log_progress "Installing JetBrains Toolbox"
  local toolbox_dir_q toolbox_bin_q symlink_q
  printf -v toolbox_dir_q '%q' "$toolbox_dir"
  printf -v toolbox_bin_q '%q' "$toolbox_bin"
  printf -v symlink_q '%q' "$symlink"

  run_user_login_shell "
    set -Eeuo pipefail
    api='https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release'
    api_response=\$(mktemp)
    archive=\$(mktemp --suffix=.tar.gz)
    checksum_file=\$(mktemp)
    trap 'rm -f \"\$api_response\" \"\$archive\" \"\$checksum_file\"' EXIT
    curl -fsSL \"\$api\" -o \"\$api_response\"
    download_url=\$(jq -r 'to_entries[0].value[0].downloads.linux.link // empty' \"\$api_response\")
    checksum_url=\$(jq -r 'to_entries[0].value[0].downloads.linux.checksumLink // empty' \"\$api_response\")
    version=\$(jq -r 'to_entries[0].value[0].version // empty' \"\$api_response\")
    if [[ -z \"\$download_url\" || -z \"\$checksum_url\" ]]; then
      echo 'Failed to parse JetBrains Toolbox Linux download or checksum URL from API response' >&2
      exit 1
    fi
    echo \"JetBrains Toolbox version: \${version:-unknown}\"
    echo \"JetBrains Toolbox download: \$download_url\"
    mkdir -p $toolbox_dir_q \"\$(dirname $symlink_q)\"
    curl -fsSL \"\$download_url\" -o \"\$archive\"
    curl -fsSL \"\$checksum_url\" -o \"\$checksum_file\"
    expected_checksum=\$(awk 'NF {print \$1; exit}' \"\$checksum_file\")
    [[ \"\$expected_checksum\" =~ ^[A-Fa-f0-9]{64}$ ]]
    printf '%s  %s\n' \"\$expected_checksum\" \"\$archive\" | sha256sum -c -
    tar -xzf \"\$archive\" -C $toolbox_dir_q --strip-components=1
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
  wait_for_jetbrains_toolbox_autostart
  disable_jetbrains_toolbox_autostart
}

install_devtunnel() {
  local devtunnel_bin="$TARGET_HOME/.local/bin/devtunnel"
  [[ -x "$devtunnel_bin" ]] && return 0
  log_progress "Installing Microsoft devtunnel CLI"
  local downloaded_bin
  downloaded_bin="$(mktemp "$CACHE_DIR/devtunnel.XXXXXX")"
  run_cmd_as_user "$TARGET_USER" mkdir -p "$TARGET_HOME/.local/bin"
  if ! run_cmd curl -fsSL https://aka.ms/TunnelsCliDownload/linux-x64 -o "$downloaded_bin"; then
    rm -f "$downloaded_bin"
    return 1
  fi
  run_cmd chmod 0644 "$downloaded_bin"
  run_cmd_as_user "$TARGET_USER" install -m 0755 "$downloaded_bin" "$devtunnel_bin"
  rm -f "$downloaded_bin"
}

discord_official_rpm_installed() {
  rpm -q discord >/dev/null 2>&1 && [[ -x /usr/bin/discord ]]
}

install_discord() {
  if discord_official_rpm_installed; then
    log_info "Discord RPM is already installed"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install official Discord RPM from %s\n' "$DISCORD_RPM_URL"
    return 0
  fi

  log_progress "Installing the official Discord RPM"
  local downloaded_rpm rpm_identity
  downloaded_rpm="$(mktemp --suffix=.rpm "$CACHE_DIR/discord.XXXXXX")"
  if ! run_cmd curl -fsSL "$DISCORD_RPM_URL" -o "$downloaded_rpm"; then
    rm -f "$downloaded_rpm"
    return 1
  fi

  rpm_identity="$(rpm -qp --qf $'%{NAME}\t%{ARCH}\n' "$downloaded_rpm" 2>/dev/null || true)"
  if [[ "$rpm_identity" != $'discord\tx86_64' ]]; then
    log_warn "Discord download did not contain the expected discord.x86_64 RPM."
    rm -f "$downloaded_rpm"
    return 1
  fi

  if ! run_cmd_as_root dnf install -y "$downloaded_rpm"; then
    rm -f "$downloaded_rpm"
    return 1
  fi
  rm -f "$downloaded_rpm"
}

install_fedora_docker() {
  log_progress "Removing conflicting Docker packages"
  run_cmd_as_root dnf remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine || true
  if ! fedora_repo_enabled docker-ce; then
    log_progress "Adding Docker CE repository"
    run_cmd_as_root dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
  fi
  log_progress "Installing Docker Engine packages"
  run_cmd_as_root dnf install -y docker-ce docker-buildx-plugin docker-compose-plugin
}

configure_docker_post_install() {
  log_progress "Configuring Docker service and user group"
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

  local metadata install_script floor channel_lines channel failed=0
  log_progress "Downloading .NET release metadata and installer"
  metadata="$(mktemp "$CACHE_DIR/dotnet-releases.XXXXXX")"
  install_script="$(mktemp "$CACHE_DIR/dotnet-install.XXXXXX")"
  if ! run_cmd curl -fsSL https://dotnetcli.azureedge.net/dotnet/release-metadata/releases-index.json -o "$metadata" \
    || ! run_cmd curl -fsSL "https://raw.githubusercontent.com/dotnet/install-scripts/$DOTNET_INSTALL_COMMIT/src/dotnet-install.sh" -o "$install_script" \
    || ! printf '%s  %s\n' "$DOTNET_INSTALL_SHA256" "$install_script" | sha256sum -c -; then
    rm -f "$metadata" "$install_script"
    return 1
  fi
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
  while IFS=$'\t' read -r channel _; do
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
    log_progress "Installing .NET SDK channel: $channel"
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
    log_progress "Installing .NET global tool: $tool"
    if run_cmd_as_user "$TARGET_USER" "$dotnet_bin" tool update -g "$tool" || run_cmd_as_user "$TARGET_USER" "$dotnet_bin" tool install -g "$tool"; then
      continue
    fi
    failed=1
    log_warn "Failed to install .NET tool: $tool"
  done
  [[ "$failed" -eq 0 ]]
}

jetbrains_mono_nerd_font_dir() {
  printf '%s\n' "$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerdFont"
}

jetbrains_mono_nerd_font_installed() {
  local font_dir
  font_dir="$(jetbrains_mono_nerd_font_dir)"
  [[ -d "$font_dir" ]] || return 1
  find "$font_dir" -maxdepth 1 -type f -name 'JetBrainsMonoNerdFont*.ttf' -print -quit 2>/dev/null | grep -q .
}

install_fedora_jetbrains_mono_nerd_font() {

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

noctalia_greeter_action_skipped() {
  local skip_file="$PLAN_DIR/system-skips.tsv"
  [[ -f "$skip_file" ]] || return 1
  awk -F'\t' '$1 == "action" && $2 == "noctalia-greeter" { found = 1 } END { exit !found }' "$skip_file"
}

install_fedora_noctalia_greeter_package() {
  log_progress "Installing greetd for Noctalia Greeter"
  package_install_idempotent "$(native_backend)" greetd || return 1

  log_progress "Installing or syncing Noctalia Greeter"
  if rpm -q "$NOCTALIA_GREETER_PACKAGE" >/dev/null 2>&1; then
    run_cmd_as_root dnf distro-sync -y --allowerasing --from-repo "$NOCTALIA_GREETER_FEDORA_COPR_REPO" "$NOCTALIA_GREETER_PACKAGE"
  else
    run_cmd_as_root dnf install -y --allowerasing --from-repo "$NOCTALIA_GREETER_FEDORA_COPR_REPO" "$NOCTALIA_GREETER_PACKAGE"
  fi
}

noctalia_greetd_config_content() {
  cat <<EOF
[terminal]
vt = 1

[default_session]
command = "$NOCTALIA_GREETER_SESSION_BIN"
user = "$NOCTALIA_GREETER_USER"
EOF
}

install_noctalia_greetd_config() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: write %s for %s\n' "$NOCTALIA_GREETD_CONFIG" "$NOCTALIA_GREETER_SESSION_BIN"
    return 0
  fi

  log_progress "Writing Noctalia Greeter greetd configuration"
  local config_tmp backup_path
  config_tmp="$(mktemp "$CACHE_DIR/greetd-config.XXXXXX")"
  noctalia_greetd_config_content >"$config_tmp"

  run_cmd_as_root mkdir -p "$(dirname "$NOCTALIA_GREETD_CONFIG")"
  if [[ -f "$NOCTALIA_GREETD_CONFIG" ]] && cmp -s "$config_tmp" "$NOCTALIA_GREETD_CONFIG"; then
    rm -f "$config_tmp"
    return 0
  fi
  if [[ -f "$NOCTALIA_GREETD_CONFIG" ]]; then
    backup_path="${NOCTALIA_GREETD_CONFIG}.bak.noctalia.$(date +%Y%m%d%H%M%S)"
    run_cmd_as_root cp -a "$NOCTALIA_GREETD_CONFIG" "$backup_path"
  fi

  run_cmd_as_root install -m 0644 "$config_tmp" "$NOCTALIA_GREETD_CONFIG"
  rm -f "$config_tmp"
}

find_noctalia_greeter_pam_runtime_module() {
  local module dir
  for module in pam_systemd.so pam_elogind.so; do
    for dir in /usr/lib/security /usr/lib64/security /lib/security /lib64/security; do
      if [[ -f "$dir/$module" ]]; then
        printf '%s\n' "$module"
        return 0
      fi
    done
  done
  return 1
}

configure_noctalia_greetd_pam() {
  local pam_file="/etc/pam.d/greetd"
  local pam_module pam_line pam_tmp backup_path last_session

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: ensure %s has a pam_systemd.so or pam_elogind.so session line\n' "$pam_file"
    return 0
  fi

  log_progress "Configuring greetd PAM session support"
  [[ -f "$pam_file" ]] || {
    log_warn "$pam_file was not found after installing greetd; skipping Noctalia Greeter PAM session patch."
    return 0
  }

  pam_module="$(find_noctalia_greeter_pam_runtime_module || true)"
  [[ -n "$pam_module" ]] || {
    log_warn "No pam_systemd.so or pam_elogind.so found; leaving $pam_file unchanged."
    return 0
  }

  grep -q -F "$pam_module" "$pam_file" && return 0

  pam_line="session    required     $pam_module"
  pam_tmp="$(mktemp "$CACHE_DIR/greetd-pam.XXXXXX")"
  if grep -q -E '^[[:space:]]*session[[:space:]]+' "$pam_file"; then
    last_session="$(grep -n -E '^[[:space:]]*session[[:space:]]+' "$pam_file" | tail -n 1 | awk -F: '{print $1}')"
    awk -v line="$pam_line" -v last="$last_session" '{ print $0; if (NR == last) print line }' "$pam_file" >"$pam_tmp"
  else
    cp "$pam_file" "$pam_tmp"
    printf '\n%s\n' "$pam_line" >>"$pam_tmp"
  fi

  backup_path="${pam_file}.bak.noctalia.$(date +%Y%m%d%H%M%S)"
  run_cmd_as_root cp "$pam_file" "$backup_path"
  run_cmd_as_root install -m 0644 "$pam_tmp" "$pam_file"
  rm -f "$pam_tmp"
}

ensure_noctalia_greeter_user() {
  log_progress "Ensuring Noctalia Greeter system user exists"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_cmd_as_root useradd -r -s /usr/bin/nologin -d "$NOCTALIA_GREETER_STATE_DIR" "$NOCTALIA_GREETER_USER"
    return 0
  fi

  id -u "$NOCTALIA_GREETER_USER" >/dev/null 2>&1 && return 0
  run_cmd_as_root useradd -r -s /usr/bin/nologin -d "$NOCTALIA_GREETER_STATE_DIR" "$NOCTALIA_GREETER_USER"
}

prepare_noctalia_greeter_paths() {
  log_progress "Preparing Noctalia Greeter state and log paths"
  run_cmd_as_root mkdir -p "$NOCTALIA_GREETER_STATE_DIR"
  run_cmd_as_root chmod 0755 "$NOCTALIA_GREETER_STATE_DIR"
  run_cmd_as_root chown "$NOCTALIA_GREETER_USER:" "$NOCTALIA_GREETER_STATE_DIR"
  run_cmd_as_root touch \
    /var/log/noctalia-greeter.log \
    "$NOCTALIA_GREETER_STATE_DIR/greeter.log" \
    /tmp/noctalia-greeter.log
  run_cmd_as_root chown "$NOCTALIA_GREETER_USER:" \
    /var/log/noctalia-greeter.log \
    "$NOCTALIA_GREETER_STATE_DIR/greeter.log" \
    /tmp/noctalia-greeter.log
  run_cmd_as_root chmod 0664 \
    /var/log/noctalia-greeter.log \
    "$NOCTALIA_GREETER_STATE_DIR/greeter.log" \
    /tmp/noctalia-greeter.log
}

install_fedora_noctalia_greeter() {

  local existing_display_manager=""
  existing_display_manager="$(detect_enabled_display_manager || true)"
  if [[ -n "$existing_display_manager" ]]; then
    log_info "Existing display manager detected ($existing_display_manager); skipping Noctalia Greeter package and service setup."
    record_system_skip action noctalia-greeter "existing display manager: $existing_display_manager"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install greetd and Noctalia Greeter package %s from %s\n' "$NOCTALIA_GREETER_PACKAGE" "$NOCTALIA_GREETER_FEDORA_COPR_REPO"
    ensure_noctalia_greeter_user
    install_noctalia_greetd_config
    configure_noctalia_greetd_pam
    prepare_noctalia_greeter_paths
    printf 'DRY-RUN: initialize %s/greeter.toml with noctalia-greeter-apply-appearance --setup-system\n' "$NOCTALIA_GREETER_STATE_DIR"
    run_cmd_as_root systemctl daemon-reload
    run_cmd_as_root systemctl set-default graphical.target
    run_cmd_as_root systemctl enable --force greetd.service
    return 0
  fi

  log_progress "Installing Noctalia Greeter"
  install_fedora_noctalia_greeter_package || return 1

  command -v noctalia-greeter >/dev/null 2>&1 || die "Noctalia Greeter package installed, but noctalia-greeter is not on PATH."
  command -v noctalia-greeter-session >/dev/null 2>&1 || die "Noctalia Greeter package installed, but noctalia-greeter-session is not on PATH."
  command -v noctalia-greeter-compositor >/dev/null 2>&1 || die "Noctalia Greeter package installed, but noctalia-greeter-compositor is not on PATH."
  command -v noctalia-greeter-apply-appearance >/dev/null 2>&1 || die "Noctalia Greeter package installed, but noctalia-greeter-apply-appearance is not on PATH."

  run_cmd_as_root systemctl daemon-reload || return 1
  if ! fedora_service_exists greetd; then
    log_warn "greetd.service was not detected after Noctalia Greeter install; retrying direct greetd package install."
    package_install_idempotent "$(native_backend)" greetd || return 1
    run_cmd_as_root systemctl daemon-reload || return 1
  fi
  fedora_service_exists greetd || die "Noctalia Greeter requires greetd.service, but it is still unavailable after package installation."

  ensure_noctalia_greeter_user
  install_noctalia_greetd_config
  configure_noctalia_greetd_pam
  prepare_noctalia_greeter_paths
  log_progress "Initializing Noctalia Greeter appearance"
  run_cmd_as_root env "GREETER_USER=$NOCTALIA_GREETER_USER" noctalia-greeter-apply-appearance --setup-system || return 1

  log_progress "Enabling graphical login through greetd"
  run_cmd_as_root systemctl set-default graphical.target || return 1
  run_cmd_as_root systemctl enable --force greetd.service || return 1
  printf 'Noctalia Greeter is enabled through greetd. Reboot to start the graphical login.\n'
}

install_fedora_media_codecs() {
  log_progress "Replacing Fedora ffmpeg-free with RPM Fusion ffmpeg"
  run_cmd_as_root dnf swap -y ffmpeg-free ffmpeg --allowerasing || return 1
  log_progress "Installing the curated multimedia codec group"
  run_cmd_as_root dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver || return 1
  log_progress "Retaining Bluetooth aptX support as part of the multimedia group"
  run_cmd_as_root dnf -y mark group multimedia pipewire-codec-aptx || return 1
  log_progress "Installing Firefox OpenH264 integration"
  run_cmd_as_root dnf install -y mozilla-openh264 || return 1
}

run_custom_action() {
  local action="$1"
  log_progress "Running custom action: $action"
  case "$action" in
    brew:*) install_brew_package "${action#brew:}" ;;
    npm-global:*) install_npm_global_package "${action#npm-global:}" ;;
    vscode-extension:*) install_vscode_extension "${action#vscode-extension:}" ;;
    pywalfox) install_pywalfox ;;
    claude-code) install_claude_code ;;
    jetbrains-toolbox) install_jetbrains_toolbox ;;
    devtunnel) install_devtunnel ;;
    discord) install_discord ;;
    docker) install_fedora_docker ;;
    docker-post-install) configure_docker_post_install ;;
    dotnet-sdk) install_dotnet_sdks ;;
    dotnet-tools) install_dotnet_tools ;;
    jetbrains-mono-nerd-font) install_fedora_jetbrains_mono_nerd_font ;;
    noctalia-greeter) install_fedora_noctalia_greeter ;;
    media-codecs) install_fedora_media_codecs ;;
    media-hardware-acceleration) install_fedora_media_hardware_acceleration ;;
    *) die "Unknown custom action: $action" ;;
  esac
}

verify_custom_action() {
  local action="$1"
  [[ "$DRY_RUN" -eq 0 ]] || return 0
  case "$action" in
    brew:*)
      local brew_package_q
      printf -v brew_package_q '%q' "${action#brew:}"
      [[ -x "$BREW_PREFIX/bin/brew" ]] \
        && run_user_login_shell "brew list $brew_package_q >/dev/null 2>&1"
      ;;
    npm-global:*)
      npm list -g --depth=0 "${action#npm-global:}" >/dev/null 2>&1
      ;;
    vscode-extension:*)
      vscode_extension_installed "${action#vscode-extension:}"
      ;;
    pywalfox)
      pywalfox_installed
      ;;
    claude-code)
      [[ -x "$TARGET_HOME/.local/bin/claude" ]]
      ;;
    jetbrains-toolbox)
      [[ -x "$TARGET_HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" ]] \
        && [[ ! -e "$(jetbrains_toolbox_autostart_file)" ]]
      ;;
    devtunnel)
      [[ -x "$TARGET_HOME/.local/bin/devtunnel" ]]
      ;;
    discord)
      discord_official_rpm_installed
      ;;
    docker)
      rpm -q \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin >/dev/null 2>&1
      ;;
    docker-post-install)
      systemctl is-enabled docker.service >/dev/null 2>&1 \
        && id -nG "$TARGET_USER" | grep -qw docker
      ;;
    dotnet-sdk)
      [[ -x "$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME/dotnet" ]]
      ;;
    dotnet-tools)
      local dotnet_bin="$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME/dotnet"
      [[ -x "$dotnet_bin" ]] || return 1
      local tool installed_tools
      installed_tools="$(run_cmd_as_user "$TARGET_USER" "$dotnet_bin" tool list -g 2>/dev/null || true)"
      for tool in "${DOTNET_TOOLS[@]}"; do
        awk -v wanted="${tool,,}" 'NR > 2 && tolower($1) == wanted {found=1} END {exit !found}' <<<"$installed_tools" || return 1
      done
      ;;
    jetbrains-mono-nerd-font)
      jetbrains_mono_nerd_font_installed
      ;;
    noctalia-greeter)
      noctalia_greeter_action_skipped && return 0
      rpm -q "$NOCTALIA_GREETER_PACKAGE" >/dev/null 2>&1 \
        && command -v noctalia-greeter >/dev/null 2>&1 \
        && command -v noctalia-greeter-session >/dev/null 2>&1 \
        && systemctl is-enabled greetd >/dev/null 2>&1 \
        && grep -F "noctalia-greeter-session" "$NOCTALIA_GREETD_CONFIG" >/dev/null 2>&1
      ;;
    media-codecs)
      rpm -q \
        ffmpeg \
        ffmpeg-libs \
        gstreamer1-plugin-libav \
        gstreamer1-plugin-openh264 \
        gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly \
        pipewire-codec-aptx \
        mozilla-openh264 >/dev/null 2>&1
      ;;
    media-hardware-acceleration)
      verify_fedora_media_hardware_acceleration
      ;;
    *)
      return 0
      ;;
  esac
}

run_actions_from_plan_file() {
  local plan_file="$1"
  local mode="${2:-optional}"
  local label="${3:-custom actions}"
  [[ -f "$plan_file" ]] || return 0

  local action
  while IFS= read -r action; do
    [[ -n "$action" ]] || continue
    printf 'action: %s\n' "$action"
    log_progress "Starting $label action: $action"
    if run_custom_action "$action" && verify_custom_action "$action"; then
      log_progress "Completed $label action: $action"
      continue
    fi
    if [[ "$mode" == "required" ]]; then
      log_error "Required $label action failed verification: $action"
      return 1
    fi
    log_warn "Optional custom action failed and will be skipped for now: $action"
    append_warning "Optional custom action failed and was skipped: $action"
  done < <(read_plan_file "$plan_file")
}
