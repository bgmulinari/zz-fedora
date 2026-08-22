#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  source_modules
}

@test "every catalog action item resolves to a registered installer and verifier" {
  catalog_ensure_loaded
  local bundle_id step_index step_backend _step_sources action found_any=0
  while IFS= read -r bundle_id; do
    [[ -n "$bundle_id" ]] || continue
    while IFS=$'\t' read -r step_index step_backend _step_sources; do
      [[ -n "$step_index" && "$step_backend" == "action" ]] || continue
      while IFS= read -r action; do
        [[ -n "$action" ]] || continue
        found_any=1
        split_action_id "$action"
        [[ -n "${ACTION_INSTALL_FN[$ACTION_DISPATCH_ID]:-}" ]] || {
          printf 'bundle %s declares action %s with no registered installer\n' "$bundle_id" "$action" >&2
          return 1
        }
        [[ -n "${ACTION_VERIFY_FN[$ACTION_DISPATCH_ID]:-}" ]] || {
          printf 'bundle %s declares action %s with no registered verifier\n' "$bundle_id" "$action" >&2
          return 1
        }
        declare -F "${ACTION_INSTALL_FN[$ACTION_DISPATCH_ID]}" >/dev/null || {
          printf 'action %s registers undefined install function %s\n' "$action" "${ACTION_INSTALL_FN[$ACTION_DISPATCH_ID]}" >&2
          return 1
        }
        declare -F "${ACTION_VERIFY_FN[$ACTION_DISPATCH_ID]}" >/dev/null || {
          printf 'action %s registers undefined verify function %s\n' "$action" "${ACTION_VERIFY_FN[$ACTION_DISPATCH_ID]}" >&2
          return 1
        }
      done < <(bundle_step_items "$bundle_id" "$step_index")
    done < <(bundle_steps "$bundle_id")
  done < <(list_bundle_ids)
  [[ "$found_any" -eq 1 ]] || {
    printf 'expected the catalog to declare at least one custom action\n' >&2
    return 1
  }
}

@test "every base-planned action registers a non-empty verifier" {
  local base_action_plan="$TEST_ROOT/base-actions.list"
  build_base_package_plan_for_backend action "$base_action_plan"

  [[ -s "$base_action_plan" ]] || {
    printf 'expected base bundles to plan at least one custom action\n' >&2
    return 1
  }
  local action
  while IFS= read -r action; do
    [[ -n "$action" ]] || continue
    split_action_id "$action"
    [[ -n "${ACTION_VERIFY_FN[$ACTION_DISPATCH_ID]:-}" ]] || {
      printf 'base-planned action %s has no registered verify function\n' "$action" >&2
      return 1
    }
  done < <(read_plan_file "$base_action_plan")
}

@test "desktop cursor theme action installs and verifies the pinned compiled payload" {
  local fixture_commit="0123456789abcdef0123456789abcdef01234567"
  local fixture_theme="Qogir"
  local fixture_root="$TEST_ROOT/Qogir-icon-theme-$fixture_commit"
  local fixture_archive="$TEST_ROOT/cursor-theme.tar.gz"
  local theme_dir real_mktemp

  setup_fake_bin
  real_mktemp="$(command -v mktemp)"
  write_fake_command mktemp <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$TEST_ROOT/cursor-mktemp.log"
exec "$real_mktemp" "\$@"
EOF
  PATH="$FAKE_BIN:$PATH"

  mkdir -p "$fixture_root/src/cursors/dist/cursors"
  printf 'fixture license\n' >"$fixture_root/src/cursors/LICENSE"
  printf '[Icon Theme]\nName=Qogir Cursors\n' \
    >"$fixture_root/src/cursors/dist/index.theme"
  printf 'compiled cursor\n' \
    >"$fixture_root/src/cursors/dist/cursors/default"
  ln -s default "$fixture_root/src/cursors/dist/cursors/left_ptr"
  tar -czf "$fixture_archive" -C "$TEST_ROOT" "$(basename "$fixture_root")"

  DESKTOP_CURSOR_THEME_COMMIT="$fixture_commit"
  DESKTOP_CURSOR_THEME_ARCHIVE_SHA256="$(sha256sum "$fixture_archive" | awk '{print $1}')"
  DESKTOP_CURSOR_THEME_ARCHIVE_URL="file://$fixture_archive"
  DRY_RUN=0

  run install_desktop_cursor_theme
  [ "$status" -eq 0 ]

  theme_dir="$(desktop_cursor_theme_dir)"
  [[ -s "$theme_dir/LICENSE" ]]
  [[ -s "$theme_dir/zz-niri.kdl" ]]
  [[ -s "$theme_dir/cursors/default" ]]
  [[ -L "$theme_dir/cursors/left_ptr" ]]
  assert_file_contains "$theme_dir/zz-niri.kdl" "    xcursor-theme \"$fixture_theme\""
  assert_file_contains "$theme_dir/zz-niri.kdl" '    xcursor-size 24'
  assert_file_contains "$TEST_ROOT/cursor-mktemp.log" \
    "-d $TARGET_HOME/.local/share/icons/.zz-cursor-theme.XXXXXX"
  [[ -z "$(find "$TARGET_HOME/.local/share/icons" -maxdepth 1 -name '.zz-cursor-theme.*' -print -quit)" ]]
  assert_equal "$fixture_commit" "$(<"$theme_dir/.zz-source-commit")"
  run desktop_cursor_theme_installed
  [ "$status" -eq 0 ]

  printf 'different-commit\n' >"$theme_dir/.zz-source-commit"
  run desktop_cursor_theme_installed
  [ "$status" -ne 0 ]
}

@test "managed Niri cursor config appears only with the installed theme payload" {
  local theme_name
  theme_name="$(desktop_cursor_theme_name)"

  assert_file_contains "$ROOT_DIR/dotfiles/niri/.config/niri/defaults.kdl" \
    "include optional=true \"~/.local/share/icons/$theme_name/zz-niri.kdl\""
  assert_file_contains "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-zz-desktop.conf" \
    "XCURSOR_THEME=$theme_name"
  refute_file_contains "$ROOT_DIR/dotfiles/niri/.config/niri/cfg/misc.kdl" \
    'xcursor-theme'
}

@test "desktop cursor theme action preserves an unmanaged dangling destination symlink" {
  local theme_dir
  theme_dir="$(desktop_cursor_theme_dir)"
  mkdir -p "${theme_dir%/*}"
  ln -s missing-user-theme "$theme_dir"

  run install_desktop_cursor_theme

  [ "$status" -ne 0 ]
  assert_contains "$output" "Cursor theme destination already exists and is not installer-managed"
  [[ -L "$theme_dir" ]]
  assert_equal "missing-user-theme" "$(readlink "$theme_dir")"
}

@test "desktop cursor theme action restores the previous managed payload when activation fails" {
  local fixture_commit="0123456789abcdef0123456789abcdef01234567"
  local fixture_root="$TEST_ROOT/Qogir-icon-theme-$fixture_commit"
  local fixture_archive="$TEST_ROOT/cursor-theme-rollback.tar.gz"
  local theme_dir real_mv

  mkdir -p "$fixture_root/src/cursors/dist/cursors"
  printf 'fixture license\n' >"$fixture_root/src/cursors/LICENSE"
  printf '[Icon Theme]\nName=Qogir Cursors\n' \
    >"$fixture_root/src/cursors/dist/index.theme"
  printf 'compiled cursor\n' \
    >"$fixture_root/src/cursors/dist/cursors/default"
  ln -s default "$fixture_root/src/cursors/dist/cursors/left_ptr"
  tar -czf "$fixture_archive" -C "$TEST_ROOT" "$(basename "$fixture_root")"

  DESKTOP_CURSOR_THEME_COMMIT="$fixture_commit"
  DESKTOP_CURSOR_THEME_ARCHIVE_SHA256="$(sha256sum "$fixture_archive" | awk '{print $1}')"
  DESKTOP_CURSOR_THEME_ARCHIVE_URL="file://$fixture_archive"
  DRY_RUN=0

  theme_dir="$(desktop_cursor_theme_dir)"
  mkdir -p "$theme_dir"
  printf 'previous payload\n' >"$theme_dir/previous"
  printf 'previous-commit\n' >"$theme_dir/.zz-source-commit"

  setup_fake_bin
  real_mv="$(command -v mv)"
  write_fake_command mv <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
count=0
[[ ! -f "$TEST_ROOT/mv-count" ]] || count="\$(<"$TEST_ROOT/mv-count")"
count=\$((count + 1))
printf '%s\n' "\$count" >"$TEST_ROOT/mv-count"
if [[ "\$count" -eq 2 ]]; then
  exit 42
fi
exec "$real_mv" "\$@"
EOF
  PATH="$FAKE_BIN:$PATH"

  run install_desktop_cursor_theme
  [ "$status" -ne 0 ]
  assert_file_contains "$theme_dir/previous" "previous payload"
  assert_equal "previous-commit" "$(<"$theme_dir/.zz-source-commit")"
  [[ -z "$(find "$TARGET_HOME/.local/share/icons" -maxdepth 1 -name '.zz-cursor-theme.*' -print -quit)" ]]
}

@test "unregistered custom actions fail dispatch with a fatal error" {
  run run_custom_action no-such-action
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown custom action: no-such-action"
}

@test "Claude Code installer retries transient download failures" {
  DRY_RUN=0
  TARGET_USER="claude-user"
  command_log="$TEST_ROOT/claude-code-commands.log"
  run_cmd() {
    printf '%s\n' "$*" >>"$command_log"
    case "$1" in
      curl)
        touch "${@: -1}"
        ;;
      chmod)
        "$@"
        ;;
    esac
  }
  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$*" >>"$command_log"
    mkdir -p "$TARGET_HOME/.local/bin"
    touch "$TARGET_HOME/.local/bin/claude"
    chmod +x "$TARGET_HOME/.local/bin/claude"
  }

  run install_claude_code

  [ "$status" -eq 0 ]
  run verify_claude_code
  [ "$status" -eq 0 ]
  assert_file_contains "$command_log" \
    "curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 15 https://claude.ai/install.sh -o $CACHE_DIR/claude-install."
  assert_file_contains "$command_log" "claude-user:bash $CACHE_DIR/claude-install."
}

@test "Visual Studio Code extension action installs the DMS theme once for the target user" {
  DRY_RUN=0
  TARGET_USER="code-user"
  extension_marker="$TEST_ROOT/dms-extension-installed"
  command_log="$TEST_ROOT/vscode-extension-commands.log"
  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$*" >>"$command_log"
    case "$*" in
      "code --list-extensions")
        [[ -f "$extension_marker" ]] && printf 'danklinux.dms-theme\n'
        ;;
      "code --install-extension danklinux.dms-theme")
        touch "$extension_marker"
        ;;
    esac
  }

  run run_custom_action vscode-extension:danklinux.dms-theme
  [ "$status" -eq 0 ]
  run verify_custom_action vscode-extension:danklinux.dms-theme
  [ "$status" -eq 0 ]
  run run_custom_action vscode-extension:danklinux.dms-theme
  [ "$status" -eq 0 ]

  assert_equal "1" "$(grep -Fc 'code-user:code --install-extension danklinux.dms-theme' "$command_log")"
  assert_file_contains "$command_log" "code-user:code --list-extensions"
}
@test "Firefox theme action installs the Pywalfox host and user-disableable extension policy" {
  DRY_RUN=0
  TARGET_USER="firefox-user"
  TARGET_HOME="$TEST_ROOT/firefox-home"
  ZZ_FIREFOX_POLICIES_FILE="$TEST_ROOT/firefox-policy/policies.json"
  command_log="$TEST_ROOT/firefox-theme-commands.log"
  pywalfox_bin="$TARGET_HOME/.local/bin/pywalfox"
  mkdir -p "$TARGET_HOME" "$(dirname "$ZZ_FIREFOX_POLICIES_FILE")" "$(dirname "$pywalfox_bin")"
  printf '{"policies":{"DisableTelemetry":true}}\n' >"$ZZ_FIREFOX_POLICIES_FILE"

  run_cmd_as_user() {
    local user="$1"
    shift
    printf '%s:%s\n' "$user" "$*" >>"$command_log"
    if [[ "$*" == "env HOME=$TARGET_HOME $SYSTEM_PYTHON -m pywalfox install" ]]; then
      printf '#!/usr/bin/env bash\n' >"$pywalfox_bin"
      chmod +x "$pywalfox_bin"
      mkdir -p "$TARGET_HOME/.mozilla/native-messaging-hosts"
      jq -n \
        --arg executable "$pywalfox_bin" \
        --arg extension_id "$FIREFOX_THEME_EXTENSION_ID" \
        '{path: $executable, allowed_extensions: [$extension_id]}' \
        >"$TARGET_HOME/.mozilla/native-messaging-hosts/pywalfox.json"
      return 0
    fi
    case "$1" in
      mkdir|ln) "$@" ;;
      *) return 0 ;;
    esac
  }

  run install_firefox_theme
  [ "$status" -eq 0 ]
  run verify_custom_action firefox-theme
  [ "$status" -eq 0 ]

  assert_file_contains "$command_log" \
    "firefox-user:env HOME=$TARGET_HOME $SYSTEM_PYTHON -m pip install --user --quiet pywalfox"
  assert_file_contains "$command_log" \
    "firefox-user:env HOME=$TARGET_HOME $SYSTEM_PYTHON -m pywalfox install"
  # The wal colors bridge points Pywalfox at the DMS template output.
  [ -L "$TARGET_HOME/.cache/wal/colors.json" ]
  assert_equal "$TARGET_HOME/.cache/wal/dank-pywalfox.json" "$(readlink "$TARGET_HOME/.cache/wal/colors.json")"
  jq -e '.policies.DisableTelemetry == true' "$ZZ_FIREFOX_POLICIES_FILE" >/dev/null
  jq -e '.policies.ExtensionSettings["pywalfox@frewacom.org"].installation_mode == "normal_installed"' "$ZZ_FIREFOX_POLICIES_FILE" >/dev/null
  jq -e '.policies.ExtensionSettings["pywalfox@frewacom.org"].install_url == "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"' "$ZZ_FIREFOX_POLICIES_FILE" >/dev/null
}
@test "Firefox theme wal bridge backs up a user-owned pywal palette before linking" {
  DRY_RUN=0
  TARGET_USER="firefox-user"
  TARGET_HOME="$TEST_ROOT/firefox-wal-home"
  mkdir -p "$TARGET_HOME/.cache/wal"
  printf '{"user":"palette"}\n' >"$TARGET_HOME/.cache/wal/colors.json"

  run_cmd_as_user() {
    shift
    case "$1" in
      mkdir|cp|ln) "$@" ;;
      *) return 0 ;;
    esac
  }

  run_without_bats_debug_trap install_firefox_theme_wal_link

  [ -L "$TARGET_HOME/.cache/wal/colors.json" ]
  assert_equal "$TARGET_HOME/.cache/wal/dank-pywalfox.json" "$(readlink "$TARGET_HOME/.cache/wal/colors.json")"
  local backup_file
  backup_file="$(find "$STATE_DIR/backups" -type f -path "*$TARGET_HOME/.cache/wal/colors.json*" | head -n 1)"
  [ -n "$backup_file" ]
  assert_file_contains "$backup_file" '{"user":"palette"}'
}
@test "Firefox theme verification accepts any Pywalfox-owned host and replaces a foreign one" {
  DRY_RUN=0
  TARGET_HOME="$TEST_ROOT/firefox-host-home"
  ZZ_FIREFOX_POLICIES_FILE="$TEST_ROOT/firefox-host-policy/policies.json"
  manifest="$TARGET_HOME/.mozilla/native-messaging-hosts/pywalfox.json"
  mkdir -p "$(dirname "$manifest")" "$(dirname "$ZZ_FIREFOX_POLICIES_FILE")" \
    "$TARGET_HOME/.local/bin" "$TARGET_HOME/.cache/wal" "$TEST_ROOT/session-prefix/bin"
  ln -sfn "$TARGET_HOME/.cache/wal/dank-pywalfox.json" "$TARGET_HOME/.cache/wal/colors.json"
  jq -n \
    --arg extension_id "$FIREFOX_THEME_EXTENSION_ID" \
    --arg extension_url "$FIREFOX_THEME_EXTENSION_URL" \
    '{policies: {ExtensionSettings: {($extension_id): {
      installation_mode: "normal_installed",
      install_url: $extension_url
    }}}}' >"$ZZ_FIREFOX_POLICIES_FILE"

  write_manifest_host() {
    jq -n \
      --arg executable "$1" \
      --arg extension_id "$FIREFOX_THEME_EXTENSION_ID" \
      '{path: $executable, allowed_extensions: [$extension_id]}' >"$manifest"
  }

  # Pywalfox rewrites its own manifest from whichever install is running, so
  # a host outside the installer's resolution stays converged.
  session_bin="$TEST_ROOT/session-prefix/bin/pywalfox"
  printf '#!/usr/bin/env bash\n' >"$session_bin"
  chmod +x "$session_bin"
  write_manifest_host "$session_bin"
  run verify_custom_action firefox-theme
  [ "$status" -eq 0 ]

  # A host Pywalfox does not own is not converged, so the action reinstalls it.
  foreign_bin="$TARGET_HOME/.local/bin/some-other-host"
  printf '#!/usr/bin/env bash\n' >"$foreign_bin"
  chmod +x "$foreign_bin"
  write_manifest_host "$foreign_bin"
  run verify_custom_action firefox-theme
  [ "$status" -ne 0 ]

  # A manifest naming a host that is no longer installed is not converged.
  write_manifest_host "$TEST_ROOT/session-prefix/bin/pywalfox-removed"
  run verify_custom_action firefox-theme
  [ "$status" -ne 0 ]
}
@test "Firefox theme policy installation uses root only where the destination needs it" {
  DRY_RUN=0
  ZZ_FIREFOX_POLICIES_FILE="$TEST_ROOT/writable-policy/policies.json"
  command_log="$TEST_ROOT/firefox-policy-commands.log"
  mkdir -p "$(dirname "$ZZ_FIREFOX_POLICIES_FILE")"
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$command_log"
  }

  run install_firefox_theme_policy
  [ "$status" -eq 0 ]
  [[ ! -e "$command_log" ]]
  jq -e '.policies.ExtensionSettings["pywalfox@frewacom.org"].installation_mode == "normal_installed"' \
    "$ZZ_FIREFOX_POLICIES_FILE" >/dev/null

  # An override pointing at a path the caller cannot write still escalates.
  ZZ_FIREFOX_POLICIES_FILE="/etc/zz-firefox-policy-test/policies.json"
  run install_firefox_theme_policy
  [ "$status" -eq 0 ]
  assert_file_contains "$command_log" "root:mkdir -p /etc/zz-firefox-policy-test"
}
@test "pinned Git checkout is verified as its target user" {
  DRY_RUN=0
  TARGET_USER="checkout-user"
  destination="$TEST_ROOT/checkout"
  commit="d2379b2701df66a36b217a7707e77f8029a99814"
  command_log="$TEST_ROOT/checkout-commands.log"
  mkdir -p "$destination/.git"

  run_cmd_as_user() {
    printf '%s\n' "$*" >>"$command_log"
    if [[ "$*" == *" rev-parse HEAD" ]]; then
      printf '%s\n' "$commit"
    fi
  }
  git() {
    printf 'unexpected root Git invocation\n' >&2
    return 1
  }

  run install_pinned_git_checkout "Oh My Zsh" "https://example.invalid/ohmyzsh.git" "$commit" "$destination"

  [ "$status" -eq 0 ]
  assert_file_contains "$command_log" "checkout-user git -C $destination fetch --depth=1 origin $commit"
  assert_file_contains "$command_log" "checkout-user git -C $destination checkout --detach $commit"
  assert_file_contains "$command_log" "checkout-user git -C $destination rev-parse HEAD"
  refute_contains "$output" "unexpected root Git invocation"
}
@test "media codec action installs the curated hardware-neutral package set" {
  DRY_RUN=0
  command_log="$TEST_ROOT/media-codec-commands.log"
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
  }

  run install_media_codecs

  [ "$status" -eq 0 ]
  expected_commands="$(cat <<'EOF'
dnf swap -y ffmpeg-free ffmpeg --allowerasing
dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver
dnf -y mark group multimedia pipewire-codec-aptx
dnf install -y mozilla-openh264
EOF
)"
  assert_equal "$expected_commands" "$(<"$command_log")"
}
@test "media codec action stops and reports a failed DNF transaction" {
  DRY_RUN=0
  command_log="$TEST_ROOT/media-codec-failure-commands.log"
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
    [[ "$*" != "dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver" ]]
  }

  run install_media_codecs

  [ "$status" -eq 1 ]
  assert_equal "$(cat <<'EOF'
dnf swap -y ffmpeg-free ffmpeg --allowerasing
dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver
EOF
)" "$(<"$command_log")"
}
@test "media codec action stops when aptX group ownership cannot be recorded" {
  DRY_RUN=0
  command_log="$TEST_ROOT/media-codec-aptx-failure-commands.log"
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
    [[ "$*" != "dnf -y mark group multimedia pipewire-codec-aptx" ]]
  }

  run install_media_codecs

  [ "$status" -eq 1 ]
  assert_equal "$(cat <<'EOF'
dnf swap -y ffmpeg-free ffmpeg --allowerasing
dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin --exclude=libva-intel-media-driver
dnf -y mark group multimedia pipewire-codec-aptx
EOF
)" "$(<"$command_log")"
}
@test "media codec verification checks exact Fedora package names" {
  DRY_RUN=0
  rpm_log="$TEST_ROOT/media-codec-rpm.log"
  rpm() {
    printf '%s\n' "$*" >"$rpm_log"
  }

  run verify_custom_action media-codecs

  [ "$status" -eq 0 ]
  assert_equal \
    "-q ffmpeg ffmpeg-libs gstreamer1-plugin-libav gstreamer1-plugin-openh264 gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly pipewire-codec-aptx mozilla-openh264" \
    "$(<"$rpm_log")"
}
@test "Docker action lets the engine select CLI and containerd dependencies" {
  DRY_RUN=0
  command_log="$TEST_ROOT/docker-commands.log"
  fedora_repo_enabled() {
    return 0
  }
  run_cmd_as_root() {
    printf '%s\n' "$*" >>"$command_log"
  }

  run install_docker

  [ "$status" -eq 0 ]
  assert_file_contains "$command_log" "dnf install -y docker-ce docker-buildx-plugin docker-compose-plugin"
  refute_file_contains "$command_log" "docker-ce-cli"
  refute_file_contains "$command_log" "containerd.io"
}
@test "Docker verification checks the complete dependency-selected result" {
  DRY_RUN=0
  rpm_log="$TEST_ROOT/docker-rpm.log"
  rpm() {
    printf '%s\n' "$*" >"$rpm_log"
  }

  run verify_custom_action docker

  [ "$status" -eq 0 ]
  assert_equal \
    "-q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" \
    "$(<"$rpm_log")"
}
@test "Discord action installs the validated official x86_64 RPM" {
  DRY_RUN=0
  command_log="$TEST_ROOT/discord-commands.log"
  rpm() {
    if [[ "${1:-}" == "-q" ]]; then
      return 1
    fi
    if [[ "${1:-}" == "-qp" ]]; then
      printf 'discord\tx86_64\n'
      return 0
    fi
    return 1
  }
  run_cmd() {
    printf 'download:%s\n' "$*" >>"$command_log"
    touch "${@: -1}"
  }
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$command_log"
  }

  run install_discord

  [ "$status" -eq 0 ]
  assert_file_contains "$command_log" "download:curl -fsSL $DISCORD_RPM_URL -o $CACHE_DIR/discord."
  assert_file_contains "$command_log" "root:dnf install -y $CACHE_DIR/discord."
}
@test "Discord action rejects a download with unexpected RPM metadata" {
  DRY_RUN=0
  command_log="$TEST_ROOT/discord-invalid-commands.log"
  rpm() {
    if [[ "${1:-}" == "-q" ]]; then
      return 1
    fi
    if [[ "${1:-}" == "-qp" ]]; then
      printf 'unexpected\tx86_64\n'
      return 0
    fi
    return 1
  }
  run_cmd() {
    printf 'download:%s\n' "$*" >>"$command_log"
    touch "${@: -1}"
  }
  run_cmd_as_root() {
    printf 'unexpected root command: %s\n' "$*" >>"$command_log"
  }

  run install_discord

  [ "$status" -eq 1 ]
  assert_contains "$output" "expected discord.x86_64 RPM"
}
@test "JetBrains Toolbox install removes the vendor login autostart entry" {
  DRY_RUN=0
  command_log="$TEST_ROOT/toolbox-install-command.log"
  toolbox_bin="$TARGET_HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
  toolbox_link="$TARGET_HOME/.local/bin/jetbrains-toolbox"
  application_file="$TARGET_HOME/.local/share/applications/jetbrains-toolbox.desktop"
  autostart_file="$TARGET_HOME/.config/autostart/jetbrains-toolbox.desktop"

  run_user_login_shell() {
    printf '%s\n' "$1" >"$command_log"
    mkdir -p "$(dirname "$toolbox_bin")" "$(dirname "$toolbox_link")" \
      "$(dirname "$application_file")" "$(dirname "$autostart_file")"
    touch "$toolbox_bin" "$application_file"
    chmod +x "$toolbox_bin"
    ln -s "$toolbox_bin" "$toolbox_link"
    (sleep 0.2 && touch "$autostart_file") &
  }

  run install_jetbrains_toolbox

  [ "$status" -eq 0 ]
  [[ -x "$toolbox_bin" ]]
  [[ ! -e "$autostart_file" ]]
  assert_file_contains "$command_log" "nohup"
}
@test "JetBrains Toolbox install rerun removes an existing login autostart entry" {
  DRY_RUN=0
  toolbox_bin="$TARGET_HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
  autostart_file="$TARGET_HOME/.config/autostart/jetbrains-toolbox.desktop"
  mkdir -p "$(dirname "$toolbox_bin")" "$(dirname "$autostart_file")"
  touch "$toolbox_bin" "$autostart_file"
  chmod +x "$toolbox_bin"
  run_user_login_shell() {
    printf 'unexpected Toolbox relaunch\n' >&2
    return 1
  }

  run install_jetbrains_toolbox

  [ "$status" -eq 0 ]
  [[ ! -e "$autostart_file" ]]
  refute_contains "$output" "unexpected Toolbox relaunch"
}

# Boot splash fixtures: point the action's path globals at TEST_ROOT so the
# real probe logic runs against synthetic kernels, images, and dracut config.
boot_splash_test_fixture() {
  BOOT_SPLASH_MODULES_ROOT="$TEST_ROOT/lib-modules"
  BOOT_SPLASH_BOOT_DIR="$TEST_ROOT/boot"
  BOOT_SPLASH_DRACUT_CONF="$TEST_ROOT/dracut.conf"
  BOOT_SPLASH_DRACUT_CONF_DIR="$TEST_ROOT/dracut.conf.d"
  BOOT_SPLASH_INITRAMFS_STATE=""
  PLAN_DIR="$TEST_ROOT/plan"
  mkdir -p "$BOOT_SPLASH_MODULES_ROOT" "$BOOT_SPLASH_BOOT_DIR" \
    "$BOOT_SPLASH_DRACUT_CONF_DIR" "$PLAN_DIR"
}

boot_splash_test_add_kernel() {
  local version="$1"
  local with_image="${2:-1}"
  mkdir -p "$BOOT_SPLASH_MODULES_ROOT/$version"
  touch "$BOOT_SPLASH_BOOT_DIR/vmlinuz-$version"
  if [[ "$with_image" -eq 1 ]]; then
    touch "$BOOT_SPLASH_BOOT_DIR/initramfs-$version.img"
  fi
}

# Emits a listing large enough to overflow a pipe buffer with the plymouthd
# match near the top — the shape that used to SIGPIPE a grep -q consumer.
boot_splash_test_lsinitrd_with_plymouth() {
  lsinitrd() {
    printf 'usr/sbin/plymouthd\n'
    seq 1 100000
  }
}

boot_splash_test_lsinitrd_without_plymouth() {
  lsinitrd() {
    seq 1 100000
  }
}

@test "boot splash initramfs state detects ready, stale, and unsupported layouts" {
  boot_splash_test_fixture

  boot_splash_refresh_initramfs_state
  assert_equal "unsupported" "$BOOT_SPLASH_INITRAMFS_STATE"

  boot_splash_test_add_kernel "6.1.0-100.fc44.x86_64"
  boot_splash_test_lsinitrd_with_plymouth
  boot_splash_refresh_initramfs_state
  assert_equal "ready" "$BOOT_SPLASH_INITRAMFS_STATE"

  boot_splash_test_lsinitrd_without_plymouth
  boot_splash_refresh_initramfs_state
  assert_equal "stale" "$BOOT_SPLASH_INITRAMFS_STATE"

  boot_splash_test_lsinitrd_with_plymouth
  boot_splash_test_add_kernel "6.2.0-200.fc44.x86_64" 0
  boot_splash_refresh_initramfs_state
  assert_equal "stale" "$BOOT_SPLASH_INITRAMFS_STATE"

  mkdir -p "$BOOT_SPLASH_MODULES_ROOT/5.9.9-leftover-no-vmlinuz"
  touch "$BOOT_SPLASH_BOOT_DIR/initramfs-6.2.0-200.fc44.x86_64.img"
  boot_splash_refresh_initramfs_state
  assert_equal "ready" "$BOOT_SPLASH_INITRAMFS_STATE"
}

@test "boot splash kernel argument check requires rhgb and quiet on every kernel entry" {
  grubby_fixture="$TEST_ROOT/grubby-info"
  grubby() {
    cat "$grubby_fixture"
  }

  cat >"$grubby_fixture" <<'EOF'
index=0
kernel="/boot/vmlinuz-6.1.0-100.fc44.x86_64"
args="ro rootflags=subvol=root rhgb quiet"
index=1
kernel="/boot/vmlinuz-0-rescue"
args="ro rootflags=subvol=root rhgb quiet"
EOF
  run boot_splash_kernel_args_configured
  [ "$status" -eq 0 ]

  cat >"$grubby_fixture" <<'EOF'
index=0
kernel="/boot/vmlinuz-6.1.0-100.fc44.x86_64"
args="ro rootflags=subvol=root rhgb quiet"
index=1
kernel="/boot/vmlinuz-0-rescue"
args="ro rootflags=subvol=root"
EOF
  run boot_splash_kernel_args_configured
  [ "$status" -ne 0 ]

  : >"$grubby_fixture"
  run boot_splash_kernel_args_configured
  [ "$status" -ne 0 ]
}

@test "boot splash install adds kernel arguments and rebuilds the initramfs when needed" {
  DRY_RUN=0
  boot_splash_test_fixture
  boot_splash_test_add_kernel "6.1.0-100.fc44.x86_64"
  lsinitrd() {
    if [[ -f "$TEST_ROOT/initramfs-has-plymouth" ]]; then
      printf 'usr/sbin/plymouthd\n'
    fi
    seq 1 50000
  }
  have_cmd() { return 0; }
  boot_splash_kernel_args_configured() { [[ -f "$TEST_ROOT/args-configured" ]]; }
  command_log="$TEST_ROOT/boot-splash-commands.log"
  : >"$command_log"
  run_cmd_as_root() {
    printf 'root:%s\n' "$*" >>"$command_log"
    if [[ "$1" == "grubby" ]]; then
      touch "$TEST_ROOT/args-configured"
    fi
    if [[ "$1" == "dracut" ]]; then
      touch "$TEST_ROOT/initramfs-has-plymouth"
    fi
    return 0
  }

  run install_boot_splash
  [ "$status" -eq 0 ]

  assert_file_contains "$command_log" "root:grubby --update-kernel=ALL --args=rhgb quiet"
  assert_file_contains "$command_log" "root:dracut -f --regenerate-all"
  [[ ! -f "$PLAN_DIR/system-skips.tsv" ]]
}

@test "boot splash install changes nothing when the system is already configured" {
  DRY_RUN=0
  boot_splash_test_fixture
  boot_splash_test_add_kernel "6.1.0-100.fc44.x86_64"
  boot_splash_test_lsinitrd_with_plymouth
  have_cmd() { return 0; }
  boot_splash_kernel_args_configured() { return 0; }
  command_log="$TEST_ROOT/boot-splash-commands.log"
  : >"$command_log"
  run_cmd_as_root() { printf 'root:%s\n' "$*" >>"$command_log"; }

  run install_boot_splash
  [ "$status" -eq 0 ]

  [[ ! -s "$command_log" ]]
}

@test "boot splash install records a system skip when dracut omits plymouth" {
  DRY_RUN=0
  boot_splash_test_fixture
  printf 'omit_dracutmodules+=" plymouth "\n' >"$BOOT_SPLASH_DRACUT_CONF_DIR/90-no-splash.conf"
  run_cmd_as_root() {
    printf 'unexpected root command: %s\n' "$*" >&2
    return 1
  }

  run install_boot_splash
  [ "$status" -eq 0 ]

  assert_file_contains "$PLAN_DIR/system-skips.tsv" "dracut configuration omits the plymouth module"

  run verify_boot_splash
  [ "$status" -eq 0 ]
}

@test "boot splash install records a system skip when no initramfs layout exists" {
  DRY_RUN=0
  boot_splash_test_fixture
  have_cmd() { return 0; }
  run_cmd_as_root() {
    printf 'unexpected root command: %s\n' "$*" >&2
    return 1
  }

  run install_boot_splash
  [ "$status" -eq 0 ]

  assert_file_contains "$PLAN_DIR/system-skips.tsv" "no standard initramfs layout"
}

@test "boot splash install dry-run reports planned work without touching the system" {
  DRY_RUN=1
  boot_splash_test_fixture
  run_cmd_as_root() {
    printf 'unexpected root command: %s\n' "$*" >&2
    return 1
  }

  run install_boot_splash
  [ "$status" -eq 0 ]

  assert_contains "$output" "DRY-RUN: ensure boot splash kernel arguments: rhgb quiet"
  assert_contains "$output" "DRY-RUN: rebuild the initramfs when it lacks the Plymouth boot splash"
}

@test "boot splash verify requires kernel arguments and a Plymouth initramfs" {
  boot_splash_test_fixture
  boot_splash_test_add_kernel "6.1.0-100.fc44.x86_64"
  boot_splash_test_lsinitrd_with_plymouth
  boot_splash_kernel_args_configured() { return 0; }

  run verify_boot_splash
  [ "$status" -eq 0 ]

  boot_splash_kernel_args_configured() { return 1; }
  run verify_boot_splash
  [ "$status" -ne 0 ]

  boot_splash_kernel_args_configured() { return 0; }
  boot_splash_test_lsinitrd_without_plymouth
  run verify_boot_splash
  [ "$status" -ne 0 ]
}
