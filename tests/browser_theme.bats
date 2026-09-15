#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "every browser choice plans its theme integration" {
  source_modules
  local browser
  for browser in zen chromium chrome brave helium; do
    build_test_plan "browser=$browser"
    assert_plan_has "$PLAN_DIR/actions/actions.list" "browser-theme:$browser"
  done
  build_test_plan "browser=firefox"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "firefox-theme"
}

@test "Firefox initializes available colors and hands off native messaging even before DMS renders" {
  run "$SYSTEM_PYTHON" "$ROOT_DIR/tests/support/firefox_theme_host.py"
  [ "$status" -eq 0 ]
}

@test "browser setup can refresh a session before managed links are deployed" {
  WAYLAND_DISPLAY=wayland-test
  browser_theme_policy_dir() { printf '%s/policies\n' "$TEST_ROOT"; }
  run_cmd_as_root() { :; }
  install_file_if_changed() { :; }
  write_root_file() { mkdir -p "$(dirname "$2")"; cat > "$2"; }
  run_cmd_as_user() {
    shift
    if [[ "$1" == env ]]; then
      # Execute the source hook in a session with no running browser profiles.
      shift
      local cache="$1"
      shift
      env "$cache" PATH="$TEST_ROOT/bin:$PATH" "$@"
    else
      "$@"
    fi
  }
  mkdir -p "$TEST_ROOT/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_ROOT/bin/sudo"
  chmod +x "$TEST_ROOT/bin/sudo"
  install_browser_theme helium
  [ ! -e "$TARGET_HOME/.local/bin/zz-sync-browser-theme" ]
  assert_equal '#1e1e2e' "$(jq -r .BrowserThemeColor "$TEST_ROOT/policies/zz-theme.json")"
}

@test "Zen gets a registered default profile with DMS CSS before first launch" {
  run install_browser_theme zen
  [ "$status" -eq 0 ]
  run verify_custom_action browser-theme:zen
  [ "$status" -eq 0 ]
  assert_file_contains "$TARGET_HOME/.config/zen/profiles.ini" "Default=1"
  assert_file_contains "$TARGET_HOME/.config/zen/zz.default/compatibility.ini" "LastPlatformDir=/opt/zen"
  assert_file_contains "$TARGET_HOME/.config/zen/zz.default/chrome/userChrome.css" "DankMaterialShell/zen.css"
  assert_file_contains "$TARGET_HOME/.config/zen/zz.default/user.js" 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
}

@test "Zen configures registered profiles with arbitrary names and preserves custom CSS and preferences" {
  mkdir -p "$TARGET_HOME/.config/zen/unusual name/chrome" "$TARGET_HOME/external/chrome"
  cat > "$TARGET_HOME/.config/zen/profiles.ini" <<EOF
[Profile0]
Path=unusual name
IsRelative=1
[Profile1]
Path=$TARGET_HOME/external
IsRelative=0
EOF
  local profile="$TARGET_HOME/.config/zen/unusual name"
  printf 'body { color: red; }\n' > "$profile/chrome/userChrome.css"
  printf 'user_pref("test.pref", 17);\nuser_pref("toolkit.legacyUserProfileCustomizations.stylesheets", false);\n' > "$profile/user.js"
  install_browser_theme zen
  verify_custom_action browser-theme:zen
  assert_file_contains "$profile/chrome/userChrome.css" 'body { color: red; }'
  assert_file_contains "$profile/user.js" 'user_pref("test.pref", 17);'
  assert_file_contains "$TARGET_HOME/external/chrome/userChrome.css" 'DankMaterialShell/zen.css'
  local before after
  before="$(find "$TARGET_HOME" -type f -exec sha256sum {} + | sort)"
  install_browser_theme zen
  after="$(find "$TARGET_HOME" -type f -exec sha256sum {} + | sort)"
  assert_equal "$before" "$after"
}

@test "browser policy writer updates only its own file and rejects invalid arguments" {
  source "$ROOT_DIR/dotfiles/browser-theme/browser-theme-policy"
  mkdir -p "$TEST_ROOT/policies"
  printf '{"HomepageLocation":"https://example.com"}\n' > "$TEST_ROOT/policies/other.json"
  browser_policy_write "$TEST_ROOT/policies" 1e1e2e
  assert_equal '#1e1e2e' "$(jq -r .BrowserThemeColor "$TEST_ROOT/policies/zz-theme.json")"
  browser_policy_write "$TEST_ROOT/policies" eff1f5
  assert_equal '#eff1f5' "$(jq -r .BrowserThemeColor "$TEST_ROOT/policies/zz-theme.json")"
  assert_file_contains "$TEST_ROOT/policies/other.json" 'https://example.com'
  run browser_policy_main 'ffffff extra'
  [ "$status" -ne 0 ]
  run browser_policy_main '../etc'
  [ "$status" -ne 0 ]
  ln -s "$TEST_ROOT/policies/other.json" "$TEST_ROOT/link"
  run browser_policy_trusted_path "$TEST_ROOT/link"
  [ "$status" -ne 0 ]
}

@test "browser setup seeds policy from DMS without editing running browser profiles" {
  local browser
  browser_theme_policy_dir() { printf '%s/%s\n' "$TEST_ROOT/policies" "$1"; }
  run_cmd_as_root() { printf '%s\n' "$*" >> "$TEST_ROOT/root-commands"; }
  install_file_if_changed() { printf '%s\n' "$*" >> "$TEST_ROOT/root-installs"; }
  write_root_file() { mkdir -p "$(dirname "$2")"; cat > "$2"; }
  mkdir -p "$TARGET_HOME/.cache/wal" "$TARGET_HOME/.config/net.imput.helium"
  printf '{"colors":{"color0":"#123456"}}' > "$TARGET_HOME/.cache/wal/dank-pywalfox.json"
  ln -s "host-$$" "$TARGET_HOME/.config/net.imput.helium/SingletonLock"
  unset DISPLAY WAYLAND_DISPLAY
  for browser in chromium chrome brave helium; do
    install_browser_theme "$browser"
    assert_equal '#123456' "$(jq -r .BrowserThemeColor "$TEST_ROOT/policies/$browser/zz-theme.json")"
  done
  assert_file_contains "$TEST_ROOT/root-installs" '/usr/lib/zz/browser-theme-policy 0644'
  assert_file_contains "$TEST_ROOT/root-installs" '/etc/sudoers.d/zz-browser-theme 0440'
}

@test "browser installation uses the most recently generated DMS palette" {
  local palette="$TARGET_HOME/.cache/DankMaterialShell/browser-theme.color"
  local wal_palette="$TARGET_HOME/.cache/wal/dank-pywalfox.json"
  mkdir -p "$(dirname "$palette")" "$(dirname "$wal_palette")"
  printf '#112233\n' > "$palette"
  printf '{"colors":{"color0":"#445566"}}\n' > "$wal_palette"
  touch -t 202001010000 "$palette"
  touch -t 202001020000 "$wal_palette"
  assert_equal '#445566' "$(browser_theme_current_color)"
  touch -t 202001030000 "$palette"
  assert_equal '#112233' "$(browser_theme_current_color)"
  printf 'invalid json\n' > "$wal_palette"
  run browser_theme_current_color
  [ "$status" -ne 0 ]
}

@test "DMS post-hook writes policy before refreshing only running browsers" {
  source "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-browser-theme"
  mkdir -p "$XDG_CACHE_HOME/DankMaterialShell"
  printf '#AABBCC\n' > "$XDG_CACHE_HOME/DankMaterialShell/browser-theme.color"
  mkdir -p "$XDG_CONFIG_HOME/net.imput.helium"
  ln -s "host-$$" "$XDG_CONFIG_HOME/net.imput.helium/SingletonLock"
  sudo() { printf 'policy %s\n' "$*" >> "$TEST_ROOT/refresh.log"; }
  pgrep() { [[ "${*: -1}" == helium ]]; }
  helium() { printf 'helium %s\n' "$*" >> "$TEST_ROOT/refresh.log"; }
  sync_browser_theme
  assert_equal $'policy -n /usr/bin/bash /usr/lib/zz/browser-theme-policy aabbcc\nhelium --refresh-platform-policy --no-startup-window' "$(cat "$TEST_ROOT/refresh.log")"
  rm "$XDG_CONFIG_HOME/net.imput.helium/SingletonLock"
  : > "$TEST_ROOT/refresh.log"
  sync_browser_theme
  assert_equal 'policy -n /usr/bin/bash /usr/lib/zz/browser-theme-policy aabbcc' "$(cat "$TEST_ROOT/refresh.log")"
  sudo() { return 1; }
  : > "$TEST_ROOT/refresh.log"
  run sync_browser_theme
  [ "$status" -ne 0 ]
  [ ! -s "$TEST_ROOT/refresh.log" ]
}

@test "browser theme dry runs do not create profiles or policies" {
  run verify_custom_action browser-theme:zen
  [ "$status" -ne 0 ]
  DRY_RUN=1
  install_browser_theme zen
  install_browser_theme helium
  [ ! -e "$TARGET_HOME/.config" ]
  [ ! -e "$TARGET_HOME/.cache" ]
}
