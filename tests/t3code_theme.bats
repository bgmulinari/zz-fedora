#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
  SYNC_HELPER="$ROOT_DIR/dotfiles/dms/.local/bin/zz-sync-t3code-theme"
  TEMPLATE="$ROOT_DIR/dotfiles/dms/.config/matugen/templates/t3code-theme.json"
  PUBLISHED="$TARGET_HOME/.t3/userdata/themes/dms.json"
  SETTINGS="$TARGET_HOME/.t3/userdata/settings.json"
  COMMAND_LOG="$TEST_ROOT/t3code-commands"
  : >"$COMMAND_LOG"
}

# Runs file installs and the sync helper for real, and records the T3 Code CLI,
# which answers `theme show` with T3_THEME_SHOW and that command's exit status.
stub_user_commands() {
  T3_THEME_SHOW="Environment theme: not set."
  T3_THEME_SHOW_STATUS=0
  run_cmd_as_user() {
    shift
    if [[ "$*" == *"$T3CODE_APP"* ]]; then
      printf '%s\n' "$*" >>"$COMMAND_LOG"
      if [[ "$*" == *"theme show"* ]]; then
        printf '%s\n' "$T3_THEME_SHOW"
        return "$T3_THEME_SHOW_STATUS"
      fi
      return 0
    fi
    "$@"
  }
}

write_dms_palette() {
  local mode="$1" role
  mkdir -p "$TARGET_HOME/.cache/DankMaterialShell"
  {
    printf '{"mode":"%s","colors":{"%s":{' "$mode" "$mode"
    for role in $(grep -o 'colors\.[a-z_]*\.default' "$TEMPLATE" | cut -d. -f2 | sort -u); do
      printf '"%s":"#112233",' "$role"
    done
    printf '"unused":"#000000"}}}\n'
  } >"$TARGET_HOME/.cache/DankMaterialShell/dms-colors.json"
}

@test "T3 Code plans its theme action and managed links" {
  source_modules
  build_test_plan "ai=t3code"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "t3code"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "t3code-theme"
  assert_plan_has "$PLAN_DIR/config/components.list" "t3code-theme"
}

@test "T3 Code theme is wired through the matugen drop-in" {
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.config/matugen/dms/configs/zz-t3code-theme.toml\tproduct-link'
  assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
    $'~/.local/bin/zz-sync-t3code-theme\tproduct-link'
  assert_file_contains "$ROOT_DIR/dotfiles/dms/.config/matugen/dms/configs/zz-t3code-theme.toml" \
    "output_path = '~/.cache/DankMaterialShell/t3code-theme.json'"
  [[ -x "$SYNC_HELPER" ]]
}

@test "T3 Code fallback seed sets exactly the roles the template sets" {
  local seed="$ROOT_DIR/templates/t3code/dms.json"
  assert_equal "$(jq -S 'paths(scalars) | tostring' "$TEMPLATE")" "$(jq -S 'paths(scalars) | tostring' "$seed")"
  jq -e '.appearance == "dark" and ([.canvas, .accent, .colors[]] | all(test("^#[0-9a-f]{6}$")))' "$seed"
}

@test "sync helper publishes the render and leaves only the theme behind" {
  mkdir -p "$TEST_ROOT/cache/DankMaterialShell"
  printf '{"name":"DMS"}\n' >"$TEST_ROOT/cache/DankMaterialShell/t3code-theme.json"

  HOME="$TARGET_HOME" XDG_CACHE_HOME="$TEST_ROOT/cache" "$SYNC_HELPER"

  assert_equal '{"name":"DMS"}' "$(<"$PUBLISHED")"
  assert_equal "dms.json" "$(ls "$(dirname "$PUBLISHED")")"
}

@test "sync helper does not touch an unchanged theme or publish a missing render" {
  run env HOME="$TARGET_HOME" XDG_CACHE_HOME="$TEST_ROOT/cache" "$SYNC_HELPER"
  [ "$status" -eq 0 ]
  [ ! -e "$PUBLISHED" ]

  mkdir -p "$TEST_ROOT/cache/DankMaterialShell"
  printf '{"name":"DMS"}\n' >"$TEST_ROOT/cache/DankMaterialShell/t3code-theme.json"
  HOME="$TARGET_HOME" XDG_CACHE_HOME="$TEST_ROOT/cache" "$SYNC_HELPER"
  touch -d '2000-01-01' "$PUBLISHED"
  HOME="$TARGET_HOME" XDG_CACHE_HOME="$TEST_ROOT/cache" "$SYNC_HELPER"
  assert_equal "2000" "$(date -r "$PUBLISHED" +%Y)"
}

@test "action publishes the fallback before DMS has rendered and selects the theme" {
  stub_user_commands
  mkdir -p "$TARGET_HOME/.cache/DankMaterialShell"
  printf '{}\n' >"$TARGET_HOME/.cache/DankMaterialShell/dms-colors.json"

  install_t3code_theme

  cmp "$ROOT_DIR/templates/t3code/dms.json" "$PUBLISHED"
  assert_file_contains "$COMMAND_LOG" "ELECTRON_RUN_AS_NODE=1 /usr/bin/t3code"
  assert_file_contains "$COMMAND_LOG" "theme set dms --base-dir $TARGET_HOME/.t3"
  run verify_custom_action t3code-theme
  [ "$status" -eq 0 ]
}

@test "action renders the current DMS palette on a desktop that already has one" {
  stub_user_commands
  write_dms_palette light

  install_t3code_theme

  jq -e '.appearance == "light" and .canvas == "#112233" and .colors.terminalSelection == "#112233"' "$PUBLISHED"
  refute_file_contains "$PUBLISHED" "{{"
}

@test "action keeps an environment theme that is already set" {
  stub_user_commands
  T3_THEME_SHOW=$'Environment theme: "nightfall".\n\nPublished themes: dms, nightfall.'

  install_t3code_theme

  [ -f "$PUBLISHED" ]
  refute_file_contains "$COMMAND_LOG" "theme set"
}

@test "action selects nothing when T3 Code cannot read its settings" {
  stub_user_commands
  T3_THEME_SHOW_STATUS=1

  run install_t3code_theme

  [ "$status" -ne 0 ]
  refute_file_contains "$COMMAND_LOG" "theme set"
}

@test "action reads a settings file with comments through T3 Code's own parser" {
  [[ -x "$T3CODE_APP" ]] || skip "T3 Code is not installed"
  run_cmd_as_user() {
    shift
    "$@"
  }
  mkdir -p "$(dirname "$SETTINGS")"
  printf '{\n  // Chosen by hand.\n  "defaultTheme": "dms",\n}\n' >"$SETTINGS"
  local before
  before="$(<"$SETTINGS")"

  install_t3code_theme

  assert_equal "$before" "$(<"$SETTINGS")"
}

@test "skipping user configuration leaves T3 Code on its own theme" {
  stub_user_commands
  SKIP_USER_CONFIG=1

  install_t3code_theme

  [ ! -e "$PUBLISHED" ]
  [ ! -s "$COMMAND_LOG" ]
  run verify_custom_action t3code-theme
  [ "$status" -eq 0 ]
}

@test "verification fails while the theme is not published" {
  run verify_custom_action t3code-theme
  [ "$status" -ne 0 ]
}
