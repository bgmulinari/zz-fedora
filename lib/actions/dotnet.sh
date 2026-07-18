#!/usr/bin/env bash
set -Eeuo pipefail

# .NET SDK channel and global tool custom actions. The install-script pins
# and channel-selection algorithm are shared with `zz update` via
# lib/dotnet.sh.

DOTNET_TOOLS=(
  csharp-ls
  dotnet-ef
  dotnet-repl
  ilspycmd
  linux-dev-certs
  powershell
  volo.abp.studio.cli
)

install_dotnet_sdks() {
  local install_dir="$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install active .NET SDK channels -> %s\n' "$install_dir"
    return 0
  fi

  local metadata install_script channel failed=0
  log_progress "Downloading .NET release metadata and installer"
  metadata="$(mktemp "$CACHE_DIR/dotnet-releases.XXXXXX")"
  install_script="$(mktemp "$CACHE_DIR/dotnet-install.XXXXXX")"
  if ! run_cmd curl -fsSL "$DOTNET_RELEASES_INDEX_URL" -o "$metadata" \
    || ! run_cmd curl -fsSL "$DOTNET_INSTALL_SCRIPT_URL" -o "$install_script" \
    || ! printf '%s  %s\n' "$DOTNET_INSTALL_SHA256" "$install_script" | sha256sum -c -; then
    rm -f "$metadata" "$install_script"
    return 1
  fi
  run_cmd chmod 0755 "$install_script"

  local -a channels=()
  while IFS= read -r channel; do
    [[ -n "$channel" ]] && channels+=("$channel")
  done < <(dotnet_selected_channels "$metadata" || true)

  if [[ "${#channels[@]}" -eq 0 ]]; then
    rm -f "$metadata" "$install_script"
    log_warn "No active .NET SDK channels were found in Microsoft release metadata."
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

verify_dotnet_sdk() {
  [[ -x "$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME/dotnet" ]]
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

verify_dotnet_tools() {
  local dotnet_bin="$TARGET_HOME/$DOTNET_INSTALL_DIR_NAME/dotnet"
  [[ -x "$dotnet_bin" ]] || return 1
  local tool installed_tools
  installed_tools="$(run_cmd_as_user "$TARGET_USER" "$dotnet_bin" tool list -g 2>/dev/null || true)"
  for tool in "${DOTNET_TOOLS[@]}"; do
    awk -v wanted="${tool,,}" 'NR > 2 && tolower($1) == wanted {found=1} END {exit !found}' <<<"$installed_tools" || return 1
  done
}

register_action "dotnet-sdk" install_dotnet_sdks verify_dotnet_sdk
register_action "dotnet-tools" install_dotnet_tools verify_dotnet_tools
