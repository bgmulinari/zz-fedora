#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  TEMPLATE="$ROOT_DIR/dotfiles/dms/.config/matugen/templates/strata-theme.toml"
  FALLBACK="$ROOT_DIR/templates/strata/dms.toml"
  THEME="$TARGET_HOME/.config/strata/themes/dms.toml"
  SETTINGS="$TARGET_HOME/.config/strata/settings.toml"
  STYLE="$TARGET_HOME/.config/strata/style.css"
  SYNC_HELPER="$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-strata-theme"
  run_cmd_as_user() {
    shift
    "$@"
  }
}

# Every role gets its own color, so a key wired to the wrong role shows up.
write_dms_palette() {
  local mode="$1" role index=0
  mkdir -p "$TARGET_HOME/.cache/dms"
  {
    printf '{"mode":"%s","colors":{"%s":{' "$mode" "$mode"
    for role in $(grep -o 'colors\.[a-z_]*\.default' "$TEMPLATE" | cut -d. -f2 | sort -u); do
      index=$((index + 1))
      printf '"%s":"#1122%02x",' "$role" "$index"
    done
    printf '"unused":"#000000"}}}\n'
  } >"$TARGET_HOME/.cache/dms/dms-colors.json"
}

theme_keys() {
  grep -o '^[a-z_]* =' "$1"
}

@test "Strata plans its COPR, theme action, and managed configuration" {
  source_modules
  build_test_plan "desktop=strata"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "strata"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "strata-theme"
  assert_plan_has "$PLAN_DIR/config/components.list" "strata"
  assert_plan_has "$PLAN_DIR/sources/copr.list" "copr:@lgse/strata"
}

@test "Strata theme is wired through the matugen drop-in and its sync helper" {
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.config/matugen/dms/configs/zz-strata-theme.toml\tproduct-link'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.local/bin/zz-sync-strata-theme\tproduct-link'
  assert_file_contains "$ROOT_DIR/dotfiles/dms/.config/matugen/dms/configs/zz-strata-theme.toml" \
    "output_path = '~/.cache/dms/strata-theme.toml'"
  [[ -x "$SYNC_HELPER" ]]
  /usr/bin/python3 -c '
import sys, tomllib
settings = tomllib.load(open(sys.argv[1], "rb"))
assert settings == {"mode": "theme", "theme": "dms"}, settings
' "$ROOT_DIR/templates/strata/settings.toml"
}

@test "sync helper publishes the render and leaves only the theme behind" {
  mkdir -p "$TEST_ROOT/cache/dms"
  printf 'name = "DMS"\n' >"$TEST_ROOT/cache/dms/strata-theme.toml"

  HOME="$TARGET_HOME" XDG_CACHE_HOME="$TEST_ROOT/cache" XDG_CONFIG_HOME="$TARGET_HOME/.config" "$SYNC_HELPER"

  assert_equal 'name = "DMS"' "$(<"$THEME")"
  assert_equal "dms.toml" "$(ls "$(dirname "$THEME")")"
}

@test "sync helper does not touch an unchanged theme or publish a missing render" {
  run env HOME="$TARGET_HOME" XDG_CACHE_HOME="$TEST_ROOT/cache" XDG_CONFIG_HOME="$TARGET_HOME/.config" "$SYNC_HELPER"
  [ "$status" -eq 0 ]
  [ ! -e "$THEME" ]

  mkdir -p "$TEST_ROOT/cache/dms"
  printf 'name = "DMS"\n' >"$TEST_ROOT/cache/dms/strata-theme.toml"
  HOME="$TARGET_HOME" XDG_CACHE_HOME="$TEST_ROOT/cache" XDG_CONFIG_HOME="$TARGET_HOME/.config" "$SYNC_HELPER"
  touch -d '2000-01-01' "$THEME"
  HOME="$TARGET_HOME" XDG_CACHE_HOME="$TEST_ROOT/cache" XDG_CONFIG_HOME="$TARGET_HOME/.config" "$SYNC_HELPER"
  assert_equal "2000" "$(date -r "$THEME" +%Y)"
}

@test "Strata fallback seed sets exactly the keys the template sets" {
  assert_equal "$(theme_keys "$TEMPLATE")" "$(theme_keys "$FALLBACK")"
  /usr/bin/python3 -c '
import re, sys, tomllib
theme = tomllib.load(open(sys.argv[1], "rb"))
assert theme.pop("name") == "DMS"
assert all(re.fullmatch("#[0-9a-f]{6}", value) for value in theme.values()), theme
' "$FALLBACK"
}

@test "action writes the fallback theme before DMS has rendered" {
  mkdir -p "$TARGET_HOME/.cache/dms"
  printf '{}\n' >"$TARGET_HOME/.cache/dms/dms-colors.json"

  install_strata_theme

  cmp "$FALLBACK" "$THEME"
  cmp "$ROOT_DIR/templates/strata/settings.toml" "$SETTINGS"
  run verify_custom_action strata-theme
  [ "$status" -eq 0 ]
}

@test "action keeps the theme in an existing Strata settings file" {
  mkdir -p "$(dirname "$SETTINGS")"
  printf 'mode = "theme"\ntheme = "nord"\n' >"$SETTINGS"

  install_strata_theme

  [ -f "$THEME" ]
  assert_equal $'mode = "theme"\ntheme = "nord"' "$(<"$SETTINGS")"
}

@test "action writes a stylesheet stub that imports the product glass rules" {
  install_strata_theme

  local import
  import="$(grep -o '^@import url("file://[^"]*");$' "$STYLE")"
  assert_equal "@import url(\"file://$ROOT_DIR/dotfiles/strata/glass.css\");" "$import"
  [ -f "$ROOT_DIR/dotfiles/strata/glass.css" ]
  # GTK ignores an @import that follows any rule.
  assert_equal "$import" "$(grep -v '^ \|^/\*' "$STYLE")"
}

@test "action keeps a stylesheet the user already has" {
  mkdir -p "$(dirname "$STYLE")"
  printf '.sidebar { color: red; }\n' >"$STYLE"

  install_strata_theme

  assert_equal '.sidebar { color: red; }' "$(<"$STYLE")"
}

@test "glass rules keep every translucent layer on the window alone" {
  local glass="$ROOT_DIR/dotfiles/strata/glass.css"
  # Translucent theme colors would also reach menus and popovers, which niri
  # does not blur; only these rules may add alpha.
  refute_file_contains "$FALLBACK" 'e6"'
  assert_equal 1 "$(grep -c 'alpha(@strata_bg' "$glass")"
  assert_file_contains "$ROOT_DIR/templates/niri/dms-windowrules.kdl" \
    'match app-id="^io\\.github\\.lgse\\.Strata$"'
}

@test "action selects nothing when the theme could not be published" {
  run_cmd_as_user() {
    shift
    [[ "$*" == *zz-sync-strata-theme* ]] && return 1
    "$@"
  }

  run install_strata_theme

  [ "$status" -ne 0 ]
  [ ! -e "$SETTINGS" ]
  [ ! -e "$STYLE" ]
}

@test "action renders the current DMS palette on a desktop that already has one" {
  write_dms_palette light

  install_strata_theme

  /usr/bin/python3 -c '
import json, re, sys, tomllib
template = open(sys.argv[1]).read()
colors = json.load(open(sys.argv[2]))["colors"]["light"]
theme = tomllib.load(open(sys.argv[3], "rb"))
for key, role in re.findall(r"^(\w+) = \"\{\{colors\.(\w+)\.default\.hex\}\}\"$", template, re.M):
    assert theme[key] == colors[role], (key, role, theme[key])
' "$TEMPLATE" "$TARGET_HOME/.cache/dms/dms-colors.json" "$THEME"
  refute_file_contains "$THEME" "{{"
  run verify_custom_action strata-theme
  [ "$status" -eq 0 ]
}

@test "skipping user configuration leaves Strata on its own theme" {
  SKIP_USER_CONFIG=1

  install_strata_theme

  [ ! -e "$THEME" ]
  [ ! -e "$SETTINGS" ]
  [ ! -e "$STYLE" ]
  run verify_custom_action strata-theme
  [ "$status" -eq 0 ]
}

@test "verification fails while the theme is missing" {
  run verify_custom_action strata-theme
  [ "$status" -ne 0 ]
}
