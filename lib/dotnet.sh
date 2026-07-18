#!/usr/bin/env bash
set -Eeuo pipefail

# Shared .NET SDK contract: the pinned dotnet-install script revision and the
# active-channel selection algorithm. Both the installer custom action
# (lib/actions/dotnet.sh) and the post-install updater (bin/zz.d/update)
# source this file so install and update behavior cannot drift.

# shellcheck disable=SC2034  # Consumed by lib/actions/dotnet.sh and bin/zz.d/update.
DOTNET_INSTALL_DIR_NAME=".dotnet"
DOTNET_INSTALL_COMMIT="4a37a9f9d1a061fc389d6515100336db4e51710e"
# shellcheck disable=SC2034  # Consumed by lib/actions/dotnet.sh and bin/zz.d/update.
DOTNET_INSTALL_SHA256="082f7685e156738a1b2e2ed8381a621870d4ce8e8c59278034556f05c186eb2e"
# shellcheck disable=SC2034  # Consumed by lib/actions/dotnet.sh and bin/zz.d/update.
DOTNET_RELEASES_INDEX_URL="https://dotnetcli.azureedge.net/dotnet/release-metadata/releases-index.json"
# shellcheck disable=SC2034  # Consumed by lib/actions/dotnet.sh and bin/zz.d/update.
DOTNET_INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/dotnet/install-scripts/$DOTNET_INSTALL_COMMIT/src/dotnet-install.sh"

version_ge() {
  local version="$1"
  local floor="$2"
  [[ "$(printf '%s\n%s\n' "$floor" "$version" | sort -V | head -n1)" == "$floor" ]]
}

# Print "channel-version<TAB>release-type" rows for the channels Microsoft
# still supports, newest first.
dotnet_channel_lines() {
  local metadata_file="$1"
  jq -r '
    .["releases-index"][]
    | select(.["support-phase"] == "active" or .["support-phase"] == "maintenance")
    | [.["channel-version"], .["release-type"]]
    | @tsv
  ' "$metadata_file" | sort -Vr
}

# Print the channel versions to install: every supported channel at or above
# the floor, where the floor is the second-newest LTS channel (or the oldest
# supported channel when fewer than two LTS channels exist).
dotnet_selected_channels() {
  local metadata_file="$1"
  local channel_lines floor channel
  channel_lines="$(dotnet_channel_lines "$metadata_file" || true)"
  [[ -n "$channel_lines" ]] || return 1

  floor="$(awk -F'\t' '$2 == "lts" {count++; if (count == 2) {print $1; exit}}' <<<"$channel_lines")"
  [[ -n "$floor" ]] || floor="$(tail -n1 <<<"$channel_lines" | cut -f1)"

  while IFS=$'\t' read -r channel _; do
    [[ -n "$channel" ]] || continue
    if version_ge "$channel" "$floor"; then
      printf '%s\n' "$channel"
    fi
  done <<<"$channel_lines"
}
