#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "DMS component plans registry theme installation at first login" {
  build_test_plan

  assert_plan_has \
    "$PLAN_DIR/files/managed-files.list" \
    "~/.config/dms/themes/catppuccin/theme.json"
}

@test "icon-theme sync selects the hue-nearest Yaru variant for GTK only" {
  local home="$TEST_ROOT/icon-sync-home"
  mkdir -p "$home/.cache/dms" \
    "$home/.local/share/icons/Yaru" \
    "$home/.local/share/icons/Yaru-blue" \
    "$home/.local/share/icons/Yaru-red" \
    "$home/.local/share/icons/Yaru-yellow"
  printf '#e01b24\n' >"$home/.cache/dms/icon-theme-accent"
  setup_fake_bin
  make_fake_gsettings
  make_fake_command dms
  make_fake_command kwriteconfig6

  run env PATH="$FAKE_BIN:$PATH" HOME="$home" XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_DIRS="$home/.local/share" \
    "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-icon-theme"

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "gsettings set org.gnome.desktop.interface icon-theme Yaru-red"
  # Qt and KDE keep the seeded Breeze icon theme.
  [[ ! -e "$home/.config/qt6ct/qt6ct.conf" ]]
  [[ ! -e "$home/.config/kdeglobals" ]]
  ! grep -q "kwriteconfig6" "$COMMAND_LOG"
}

@test "icon-theme sync fails when the write is not saved" {
  local home="$TEST_ROOT/icon-sync-unsaved-home"
  mkdir -p "$home/.cache/dms" "$home/.local/share/icons/Yaru-red"
  printf '#e01b24\n' >"$home/.cache/dms/icon-theme-accent"
  setup_fake_bin
  make_fake_gsettings
  : >"$FAKE_BIN/.gsettings-write-fails"

  run env PATH="$FAKE_BIN:$PATH" HOME="$home" XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_DIRS="$home/.local/share" \
    "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-icon-theme"

  [ "$status" -ne 0 ]
}

@test "icon-theme sync keeps an existing settings.ini value in step" {
  local home="$TEST_ROOT/icon-sync-ini-home"
  mkdir -p "$home/.cache/dms" "$home/.local/share/icons/Yaru-red" \
    "$home/.config/gtk-3.0" "$home/.config/gtk-4.0"
  printf '#e01b24\n' >"$home/.cache/dms/icon-theme-accent"
  printf '[Settings]\ngtk-icon-theme-name=Papirus\ngtk-theme-name=adw-gtk3\n' \
    >"$home/.config/gtk-3.0/settings.ini"
  printf '[Settings]\ngtk-theme-name=adw-gtk3\n' >"$home/.config/gtk-4.0/settings.ini"
  setup_fake_bin
  make_fake_gsettings

  run env PATH="$FAKE_BIN:$PATH" HOME="$home" XDG_CACHE_HOME="$home/.cache" \
    XDG_CONFIG_HOME="$home/.config" XDG_DATA_DIRS="$home/.local/share" \
    "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-icon-theme"

  [ "$status" -eq 0 ]
  assert_file_contains "$home/.config/gtk-3.0/settings.ini" "gtk-icon-theme-name=Yaru-red"
  assert_file_contains "$home/.config/gtk-3.0/settings.ini" "gtk-theme-name=adw-gtk3"
  refute_file_contains "$home/.config/gtk-4.0/settings.ini" "gtk-icon-theme-name"
}

@test "icon-theme sync falls back to a neutral variant for low-chroma accents" {
  local home="$TEST_ROOT/icon-sync-gray-home"
  mkdir -p "$home/.cache/dms" \
    "$home/.local/share/icons/Yaru" \
    "$home/.local/share/icons/Yaru-dark" \
    "$home/.local/share/icons/Yaru-blue"
  printf '#808080\n' >"$home/.cache/dms/icon-theme-accent"
  setup_fake_bin
  make_fake_gsettings
  make_fake_command dms
  make_fake_command kwriteconfig6

  run env PATH="$FAKE_BIN:$PATH" HOME="$home" XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_DIRS="$home/.local/share" \
    "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-icon-theme"

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "gsettings set org.gnome.desktop.interface icon-theme Yaru-dark"
}

@test "DMS component links the icon sync helper and matugen drop-in" {
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.local/bin/zz-sync-icon-theme\tproduct-link\tbackup-before-link\tdotfiles/dms/.local/bin/zz-sync-icon-theme'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.config/matugen/dms/configs/zz-icon-theme.toml\tproduct-link'
  [[ -x "$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-icon-theme" ]]
  assert_file_contains "$ROOT_DIR/dotfiles/dms/.config/matugen/dms/configs/zz-icon-theme.toml" \
    "post_hook = 'sh -c \"command -v zz-sync-icon-theme"
}

@test "btop theme is wired through the matugen drop-in with a matching fallback" {
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.config/btop/themes/dank.theme\tseed-if-missing\tpreserve\ttemplates/btop/dank.theme'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.config/matugen/dms/configs/zz-btop.toml\tproduct-link'
  assert_file_contains "$ROOT_DIR/dotfiles/dms/.config/matugen/dms/configs/zz-btop.toml" \
    "output_path = '~/.config/btop/themes/dank.theme'"
  assert_file_contains "$ROOT_DIR/dotfiles/btop/.config/btop/btop.conf" 'color_theme = "dank"'

  # The static fallback must carry exactly the keys the matugen template
  # renders, so the seed-to-generated handoff never changes theme shape.
  local template_keys fallback_keys
  template_keys="$(grep -o '^theme\[[a-z_]*\]' "$ROOT_DIR/dotfiles/dms/.config/matugen/templates/btop.theme" | sort)"
  fallback_keys="$(grep -o '^theme\[[a-z_]*\]' "$ROOT_DIR/templates/btop/dank.theme" | sort)"
  [ -n "$template_keys" ]
  assert_equal "$template_keys" "$fallback_keys"

  # Every fallback value is a concrete color or an empty gradient stop.
  run grep -Ev '^(#|$)|^theme\[[a-z_]+\]="(#[0-9a-fA-F]{6})?"$' "$ROOT_DIR/templates/btop/dank.theme"
  [ "$status" -ne 0 ]
}

@test "DMS settings seed selects the registry theme with blue accents in both modes" {
  local seed
  seed="$(dms_settings_seed_json)"

  assert_equal "registry" "$(jq -r '.currentThemeCategory' <<<"$seed")"
  assert_equal "custom" "$(jq -r '.currentThemeName' <<<"$seed")"
  assert_equal "$TARGET_HOME/.config/dms/themes/catppuccin/theme.json" \
    "$(jq -r '.customThemeFile' <<<"$seed")"
  assert_equal "mocha" "$(jq -r '.registryThemeVariants.catppuccin.dark.flavor' <<<"$seed")"
  assert_equal "blue" "$(jq -r '.registryThemeVariants.catppuccin.dark.accent' <<<"$seed")"
  assert_equal "latte" "$(jq -r '.registryThemeVariants.catppuccin.light.flavor' <<<"$seed")"
  assert_equal "blue" "$(jq -r '.registryThemeVariants.catppuccin.light.accent' <<<"$seed")"
}

@test "registry theme download uses the Browse Themes backend and retries safely" {
  "$SYSTEM_PYTHON" "$ROOT_DIR/tests/support/dms_registry_theme.py" "$ROOT_DIR"
}

@test "registry theme checkpoint retries failures and restarts DMS only after installation" {
  build_test_plan
  DRY_RUN=0
  local count_file="$TEST_ROOT/registry-count"
  run_cmd_as_user() {
    shift
    if [[ "$1" == "$SYSTEM_PYTHON" ]]; then
      printf 'request\n' >>"$count_file"
      [[ -f "$TEST_ROOT/network-ready" ]] || return 1
      printf 'installed\n'
    else
      printf '%s\n' "$*" >>"$TEST_ROOT/restarts"
    fi
  }
  run run_first_run_action_once dms-registry-theme install_dms_registry_theme
  [ "$status" -ne 0 ]
  [[ ! -f "$(first_run_action_marker dms-registry-theme)" ]]
  touch "$TEST_ROOT/network-ready"
  run_first_run_action_once dms-registry-theme install_dms_registry_theme
  [[ -f "$(first_run_action_marker dms-registry-theme)" ]]
  run_first_run_action_once dms-registry-theme install_dms_registry_theme
  assert_equal "2" "$(wc -l <"$count_file")"
  assert_equal "systemctl --user restart dms.service" "$(cat "$TEST_ROOT/restarts")"
}
