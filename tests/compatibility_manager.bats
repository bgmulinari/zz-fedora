#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "Proton manager safely discovers, selects, launches and installs builds" {
  run "$SYSTEM_PYTHON" "$ROOT_DIR/tests/support/compatibility_manager_test.py"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "gaming manager plans dependencies, product link and default visibility" {
  build_test_plan "gaming=compatibility-manager"
  assert_plan_has "$PLAN_DIR/bundles.list" "gaming-compatibility-manager"
  assert_plan_has "$PLAN_DIR/config/components.list" "dms-plugin-compatibility-manager"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/DankMaterialShell/plugins/CompatibilityManager"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.local/share/applications/proton-manager.desktop"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "python3"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "dms"
  run default_choice_ids gaming
  [ "$status" -eq 0 ]
  assert_contains "$output" "compatibility-manager"
  run dms_plugin_settings_seed_json
  [ "$status" -eq 0 ]
  assert_equal true "$(jq -r '.protonManager.enabled' <<<"$output")"
  run dms_settings_seed_json
  [ "$status" -eq 0 ]
  [[ "$output" != *protonManager* ]]
}

@test "unselected gaming manager is omitted from plugin and bar seeds" {
  build_test_plan
  run dms_plugin_settings_seed_json
  [ "$status" -eq 0 ]
  assert_equal null "$(jq -r '.protonManager' <<<"$output")"
  run dms_settings_seed_json
  [ "$status" -eq 0 ]
  [[ "$output" != *protonManager* ]]
}

@test "Proton manager manifest and Python dependency agree with its surface" {
  local dir="$ROOT_DIR/dotfiles/dms/.config/DankMaterialShell/plugins/CompatibilityManager"
  "$SYSTEM_PYTHON" "$ROOT_DIR/tests/support/dms_plugin.py" "$dir"
  assert_equal python3 "$(jq -r '.dependencies[]' "$dir/plugin.json")"
  assert_file_contains "$dir/Manager.qml" '"/usr/bin/python3"'
  assert_file_contains "$dir/StartupCheck.qml" '"/usr/bin/python3"'
  assert_equal daemon "$(jq -r '.type' "$dir/plugin.json")"
  assert_file_contains "$dir/Manager.qml" 'function toggle()'
  assert_file_contains "$dir/Manager.qml" 'DankFloatingWindow {'
  assert_file_contains "$dir/Manager.qml" 'FloatingWindowControls {'
  assert_file_contains "$dir/Manager.qml" 'toplevel.activate()'
  local entry="$ROOT_DIR/dotfiles/dms/.config/DankMaterialShell/plugins/CompatibilityManager/proton-manager.desktop"
  assert_file_contains "$entry" 'Type=Application'
  assert_file_contains "$entry" 'Exec=dms ipc call plugins toggle protonManager'
  assert_file_contains "$entry" 'Categories=Game;'
}
