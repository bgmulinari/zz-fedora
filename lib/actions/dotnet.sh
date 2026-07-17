#!/usr/bin/env bash
set -Eeuo pipefail

# .NET SDK channel and global tool custom actions.

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
