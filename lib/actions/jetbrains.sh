#!/usr/bin/env bash
set -Eeuo pipefail

# JetBrains Toolbox custom action.

jetbrains_toolbox_autostart_file() {
  printf '%s\n' "$TARGET_HOME/.config/autostart/jetbrains-toolbox.desktop"
}

disable_jetbrains_toolbox_autostart() {
  local autostart_file
  autostart_file="$(jetbrains_toolbox_autostart_file)"
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

verify_jetbrains_toolbox() {
  [[ -x "$TARGET_HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" ]] \
    && [[ ! -e "$(jetbrains_toolbox_autostart_file)" ]]
}

register_action "jetbrains-toolbox" install_jetbrains_toolbox verify_jetbrains_toolbox
