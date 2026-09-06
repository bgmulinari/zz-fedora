#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

PLUGIN_ROOT_REL="dotfiles/dms/.config/DankMaterialShell/plugins"
AGENT_USAGE_REL="$PLUGIN_ROOT_REL/AgentUsage"
AGENT_USAGE_COMPONENT="dms-plugin-agent-usage"
ZZ_MENU_REL="$PLUGIN_ROOT_REL/ZzMenu"
ZZ_MENU_PATH="~/.config/DankMaterialShell/plugins/ZzMenu"
AGENT_USAGE_PATH="~/.config/DankMaterialShell/plugins/AgentUsage"
PLUGIN_SETTINGS_PATH="~/.config/DankMaterialShell/plugin_settings.json"

setup() {
  setup_test_env
  source_core
}

# Runs one plugin script inside an isolated home so the collectors only see
# the fixtures a test lays down: no real transcripts, credentials, or CLIs.
run_plugin_script() {
  local home="$1"
  shift
  mkdir -p "$home"
  run env -i HOME="$home" PATH="/usr/bin:/bin" \
    XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_HOME="$home/.local/share" XDG_CONFIG_HOME="$home/.config" \
    "$ROOT_DIR/$AGENT_USAGE_REL/scripts/$@"
}

# The inventory in an isolated home: only the overlay a test writes, and a
# login shell with nothing but the system directories on PATH.
run_zz_menu_inventory() {
  local home="$1"
  mkdir -p "$home"
  run bash -c "env -i HOME='$home' PATH='/usr/bin:/bin' XDG_CONFIG_HOME='$home/.config' \
    '$ROOT_DIR/$ZZ_MENU_REL/scripts/zz-menu-inventory' 2>/dev/null"
}

write_claude_transcript() {
  local home="$1"
  local today
  today="$(date +%Y-%m-%dT10:00:00%:z)"
  mkdir -p "$home/.claude/projects/example"
  cat >"$home/.claude/projects/example/session.jsonl" <<EOF
{"type":"user","sessionId":"s1","timestamp":"$today","message":{"role":"user","content":"hi"}}
{"type":"assistant","sessionId":"s1","timestamp":"$today","message":{"id":"m1","role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":5}}}
{"type":"assistant","sessionId":"s1","timestamp":"$today","message":{"id":"m1","role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50}}}
{"type":"assistant","sessionId":"s1","timestamp":"2026-01-02T10:00:00+00:00","message":{"id":"m2","role":"assistant","model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":5}}}
EOF
}

write_claude_stats_cache() {
  local home="$1"
  local today
  today="$(date +%Y-%m-%d)"
  mkdir -p "$home/.claude"
  cat >"$home/.claude/stats-cache.json" <<EOF
{"totalMessages":40,"totalSessions":3,
 "dailyActivity":[{"date":"2026-01-02","messageCount":12},{"date":"$today","messageCount":28}],
 "dailyModelTokens":[{"date":"2026-01-02","tokensByModel":{"claude-sonnet-5":900}},{"date":"$today","tokensByModel":{"claude-opus-4-8":1500,"claude-sonnet-5":250}}],
 "modelUsage":{"claude-opus-4-8":{"inputTokens":1000,"outputTokens":500,"cacheReadInputTokens":0,"cacheCreationInputTokens":0}}}
EOF
}

write_codex_session() {
  local home="$1"
  mkdir -p "$home/.codex/sessions/2026"
  cat >"$home/.codex/sessions/2026/rollout.jsonl" <<'EOF'
{"type":"turn_context","payload":{"model":"gpt-5.6-codex"}}
{"type":"event_msg","timestamp":"2026-01-03T10:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"output_tokens":300},"last_token_usage":{"input_tokens":300,"cached_input_tokens":100,"output_tokens":40}}}}
{"type":"event_msg","timestamp":"2026-01-03T10:05:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"output_tokens":400},"last_token_usage":{"input_tokens":300,"cached_input_tokens":0,"output_tokens":100}}}}
EOF
}

# The generic managed-config apply for one component, the way module 60
# runs it, against the test home.
apply_component() {
  DRY_RUN=0
  SKIP_USER_CONFIG=0
  run_cmd_as_user() { shift; "$@"; }
  managed_config_required_command_available() { return 0; }
  mkdir -p "$PLAN_DIR/files"
  : >"$(managed_config_deployment_plan_file)"
  append_managed_config_component "$1"
  apply_managed_config_plan
}

@test "shipped DMS plugin manifests validate against the upstream schema and layout rules" {
  local plugin
  for plugin in "$ROOT_DIR/$PLUGIN_ROOT_REL"/*/; do
    "$SYSTEM_PYTHON" "$ROOT_DIR/tests/support/dms_plugin.py" "$plugin"
  done
}

@test "agent usage plugin declares the surfaces, scripts, marks, and dependency its files rely on" {
  local dir="$ROOT_DIR/$AGENT_USAGE_REL"

  assert_equal "agentUsage" "$(jq -r '.id' "$dir/plugin.json")"
  assert_equal "python3" "$(jq -r '.dependencies[0]' "$dir/plugin.json")"
  assert_file_contains "$dir/StartupCheck.qml" "/usr/bin/python3"
  assert_file_contains "$dir/Settings.qml" 'pluginId: "agentUsage"'
  assert_file_contains "$dir/AgentUsageWidget.qml" "horizontalBarPill"
  assert_file_contains "$dir/AgentUsageWidget.qml" "verticalBarPill"
  assert_file_contains "$dir/AgentUsageWidget.qml" "property var popoutService"

  local script
  for script in update-usage collect-claude collect-codex; do
    [[ -x "$dir/scripts/$script" ]]
    assert_equal "#!/usr/bin/python3" "$(head -n 1 "$dir/scripts/$script")"
  done
  [[ -f "$dir/scripts/usage_common.py" ]]

  # The widget hides an agent through <id>Enabled; both collectors need a
  # toggle and the update command skips a switched-off collector by id.
  assert_file_contains "$dir/Settings.qml" 'settingKey: "claudeEnabled"'
  assert_file_contains "$dir/Settings.qml" 'settingKey: "codexEnabled"'
  assert_file_contains "$dir/UsageModel.qml" 'settings[id + "Enabled"]'
  assert_file_contains "$dir/UsageModel.qml" 'collectorIds: ["claude", "codex"]'

  # The hero resolves assets/<id>.svg per collector, with a dark twin for a
  # mark drawn in white.
  [[ -f "$dir/assets/claude.svg" ]]
  [[ -f "$dir/assets/codex.svg" ]]
  [[ -f "$dir/assets/codex-light.svg" ]]
  assert_file_contains "$dir/AgentUsageWidget.qml" '"assets/" + p.providerId + ".svg"'

  # Nothing product-owned may carry a user home path (the Homebrew prefix
  # under /home/linuxbrew is a fixed system location, not a user).
  run bash -c "grep -rn -E '/home/[A-Za-z0-9._-]+/' '$dir' | grep -v '/home/linuxbrew/'"
  [ "$status" -ne 0 ]
}

@test "zz menu plugin declares the surfaces, trigger, scripts, and dependencies its files rely on" {
  local dir="$ROOT_DIR/$ZZ_MENU_REL"

  assert_equal "zzMenu" "$(jq -r '.id' "$dir/plugin.json")"
  assert_equal "composite" "$(jq -r '.type' "$dir/plugin.json")"
  assert_equal "zz" "$(jq -r '.trigger' "$dir/plugin.json")"
  assert_equal "./ZzMenuLauncher.qml" "$(jq -r '.components.launcher' "$dir/plugin.json")"
  assert_equal "./ZzMenuWidget.qml" "$(jq -r '.components.widget' "$dir/plugin.json")"
  assert_file_contains "$dir/Settings.qml" 'pluginId: "zzMenu"'
  assert_file_contains "$dir/ZzMenuLauncher.qml" 'readonly property string pluginId: "zzMenu"'
  assert_file_contains "$dir/ZzMenuLauncher.qml" "function getItems"
  assert_file_contains "$dir/ZzMenuLauncher.qml" "function executeItem"
  assert_file_contains "$dir/ZzMenuLauncher.qml" "function getCategories"
  assert_file_contains "$dir/ZzMenuLauncher.qml" "requestLauncherUpdate"
  # Both surfaces load rows through the shared inventory item, which owns
  # the scripts, and the bar popout is the menu proper.
  assert_file_contains "$dir/ZzMenuLauncher.qml" "ZzMenuInventory {"
  assert_file_contains "$dir/ZzMenuWidget.qml" "ZzMenuInventory {"
  assert_file_contains "$dir/ZzMenuInventory.qml" "/zz-menu-inventory"
  assert_file_contains "$dir/ZzMenuInventory.qml" "/zz-menu-run"
  assert_file_contains "$dir/ZzMenuWidget.qml" "horizontalBarPill"
  assert_file_contains "$dir/ZzMenuWidget.qml" "verticalBarPill"
  assert_file_contains "$dir/ZzMenuWidget.qml" "popoutContent"
  assert_file_contains "$dir/ZzMenuWidget.qml" "ZzMenuPanel {"
  assert_file_contains "$dir/ZzMenuWidget.qml" "function openWithMode"
  assert_file_contains "$dir/ZzMenuWidget.qml" "function toggleWithMode"
  assert_file_contains "$dir/ZzMenuPanel.qml" "function enter"
  assert_file_contains "$dir/ZzMenuPanel.qml" "function back"
  assert_file_contains "$dir/ZzMenuPanel.qml" "function handleKey"
  assert_file_contains "$dir/ZzMenuPanel.qml" "keyForwardTargets"
  # Sibling types resolve by name only: an explicit directory import or an
  # absolute Loader URL fails through the product link with a file-name
  # case mismatch.
  run grep -n 'import "\."' "$dir"/*.qml
  [ "$status" -ne 0 ]

  [[ -x "$dir/scripts/zz-menu-inventory" ]]
  assert_equal "#!/usr/bin/python3" "$(head -n 1 "$dir/scripts/zz-menu-inventory")"
  [[ -x "$dir/scripts/zz-menu-run" ]]
  assert_file_contains "$dir/scripts/zz-menu-run" "xdg-terminal-exec"
  assert_file_contains "$dir/StartupCheck.qml" "/usr/bin/python3"
  assert_file_contains "$dir/StartupCheck.qml" "xdg-terminal-exec"
  run jq -r '.dependencies[]' "$dir/plugin.json"
  assert_contains "$output" "python3"
  assert_contains "$output" "xdg-terminal-exec"

  # The keybind seed opens the centered modal through the widget IPC; a
  # click on the pill opens the anchored popout instead.
  assert_file_contains "$ROOT_DIR/templates/niri/dms-binds.kdl" "dms ipc call widget toggleWith zzMenu root"
  assert_file_contains "$dir/ZzMenuWidget.qml" "DankModal {"
  assert_file_contains "$dir/ZzMenuWidget.qml" "import qs.Modals.Common"

  run bash -c "grep -rn -E '/home/[A-Za-z0-9._-]+/' '$dir' | grep -v '/home/linuxbrew/'"
  [ "$status" -ne 0 ]
}

@test "zz menu covers every zz command and update target and names only real ones" {
  local menu="$ROOT_DIR/$ZZ_MENU_REL/menu.json"
  local commands targets name
  commands="$("$ROOT_DIR/bin/zz" commands --json | jq -r '.[].name')"
  targets="$("$ROOT_DIR/bin/zz" update --help | awk '/^Targets:/ { active = 1; next } /^Options:/ { active = 0 } active && NF { print $1 }')"
  [[ -n "$commands" && -n "$targets" ]]

  # Every command the launcher lists is a row, or the provider that lists it.
  while IFS= read -r name; do
    run jq -e --arg name "$name" \
      'to_entries | map(.value) | any((.action // "" | test("^zz " + $name + "( |$)")) or (.provider // "") == $name)' "$menu"
    [ "$status" -eq 0 ]
  done <<<"$commands"

  # Every zz action names a command that exists and runs in a terminal (the
  # commands print, prompt, or ask for sudo); every provider is one the
  # inventory implements.
  while IFS= read -r name; do
    grep -Fxq -- "$name" <<<"$commands"
  done < <(jq -r 'to_entries[] | .value.action // empty | select(startswith("zz ")) | split(" ")[1]' "$menu")
  run jq -e 'to_entries | map(.value) | map(select(.action // "" | startswith("zz "))) | all(.terminal == true)' "$menu"
  [ "$status" -eq 0 ]
  assert_equal $'apps\nrefresh' "$(jq -r 'to_entries[] | .value.provider // empty' "$menu" | sort)"

  # The update group mirrors the updater's own target list.
  while IFS= read -r name; do
    run jq -e --arg target "$name" 'to_entries | map(.value.action // "") | any(. == "zz update " + $target)' "$menu"
    [ "$status" -eq 0 ]
  done <<<"$targets"
  while IFS= read -r name; do
    grep -Fxq -- "$name" <<<"$targets"
  done < <(jq -r 'to_entries[] | .value.action // empty | select(startswith("zz update ")) | split(" ")[2]' "$menu")

  # The groups beyond the CLI are present, and the compositor rows call the
  # compositor, not a shell page.
  run jq -e 'has("niri") and has("shell") and has("system") and has("learn")' "$menu"
  [ "$status" -eq 0 ]
  run jq -e 'to_entries | map(select(.key | startswith("niri."))) | all(.value.action | startswith("niri ") or contains("niri"))' "$menu"
  [ "$status" -eq 0 ]
}

@test "zz menu inventory merges the overlay, honors guards, and expands the refresh provider offline" {
  local home="$TEST_ROOT/menu-home"
  mkdir -p "$home/.config/zz-fedora"
  cat >"$home/.config/zz-fedora/menu.json" <<'EOF'
{
  "doctor": {"label": "Check-up"},
  "hidden": {"label": "Hidden", "action": "zz doctor --quiet", "when": "false"},
  "extras": {"icon": "star", "label": "Extras", "when": "true"},
  "extras.hello": {"label": "Hello", "description": "Says hello", "action": "echo hello", "aliases": ["greeting"]},
  "extras.more": {"label": "More", "description": "A nested group"},
  "extras.more.deep": {"label": "Deep", "action": "echo deep"}
}
EOF

  run_zz_menu_inventory "$home"
  [ "$status" -eq 0 ]
  local inventory="$output"

  # An overridden shipped row keeps its action, terminal flag, and place;
  # only the label changed.
  assert_equal "Check-up" "$(jq -r '.rows[] | select(.id == "doctor") | .label' <<<"$inventory")"
  assert_equal "zz doctor" "$(jq -r '.rows[] | select(.id == "doctor") | .action' <<<"$inventory")"
  assert_equal "true" "$(jq -r '.rows[] | select(.id == "doctor") | .terminal' <<<"$inventory")"
  run jq -e '[.rows[].id] | (index("update.zz") < index("doctor")) and (index("doctor") < index("extras.hello"))' <<<"$inventory"
  [ "$status" -eq 0 ]

  # A failed guard hides the row; a passing one keeps the group, whose rows
  # inherit its icon, carry its label as the path, search by alias, and run
  # detached unless marked terminal.
  run jq -e 'any(.rows[]; .id == "hidden") | not' <<<"$inventory"
  [ "$status" -eq 0 ]
  assert_equal "star" "$(jq -r '.rows[] | select(.id == "extras.hello") | .icon' <<<"$inventory")"
  assert_equal "Extras" "$(jq -r '.rows[] | select(.id == "extras.hello") | .path[0]' <<<"$inventory")"
  assert_equal "false" "$(jq -r '.rows[] | select(.id == "extras.hello") | .terminal' <<<"$inventory")"
  run jq -e '.rows[] | select(.id == "extras.hello") | .keywords | (index("greeting") != null) and (index("extras hello") != null)' <<<"$inventory"
  [ "$status" -eq 0 ]
  run jq -e '.groups | map(.id) | (index("update") != null) and (index("extras") != null) and (index("hidden") == null)' <<<"$inventory"
  [ "$status" -eq 0 ]

  # Nested groups are listed with their parent and path so the menu can
  # rebuild the tree; rows name their parent and their top-level group, and
  # siblings keep definition order.
  assert_equal "extras" "$(jq -r '.groups[] | select(.id == "extras.more") | .parent' <<<"$inventory")"
  assert_equal "Extras" "$(jq -r '.groups[] | select(.id == "extras.more") | .path[0]' <<<"$inventory")"
  assert_equal "star" "$(jq -r '.groups[] | select(.id == "extras.more") | .icon' <<<"$inventory")"
  assert_equal "" "$(jq -r '.groups[] | select(.id == "extras") | .parent' <<<"$inventory")"
  assert_equal "extras.more" "$(jq -r '.rows[] | select(.id == "extras.more.deep") | .parent' <<<"$inventory")"
  assert_equal "extras" "$(jq -r '.rows[] | select(.id == "extras.more.deep") | .group' <<<"$inventory")"
  assert_equal "Extras More" "$(jq -r '.rows[] | select(.id == "extras.more.deep") | .path | join(" ")' <<<"$inventory")"
  run jq -e '(.rows[] | select(.id == "extras.hello") | .order) < (.groups[] | select(.id == "extras.more") | .order)' <<<"$inventory"
  [ "$status" -eq 0 ]

  # The refresh provider lists exactly what zz refresh --list can restore,
  # with the key quoted for the shell and a terminal to read the result in.
  assert_equal "zz refresh niri/config.kdl" "$(jq -r '.rows[] | select(.id == "refresh.niri-config-kdl") | .action' <<<"$inventory")"
  assert_equal "Refresh" "$(jq -r '.rows[] | select(.id == "refresh.niri-config-kdl") | .path[0]' <<<"$inventory")"
  assert_equal "true" "$(jq -r '.rows[] | select(.id == "refresh.niri-config-kdl") | .terminal' <<<"$inventory")"
  local expected
  expected="$("$ROOT_DIR/bin/zz" refresh --list | wc -l)"
  assert_equal "$expected" "$(jq -r '[.rows[] | select(.group == "refresh")] | length' <<<"$inventory")"

  # A broken overlay contributes nothing and leaves the shipped menu intact.
  printf '{ not json' >"$home/.config/zz-fedora/menu.json"
  run_zz_menu_inventory "$home"
  [ "$status" -eq 0 ]
  assert_equal "Doctor" "$(jq -r '.rows[] | select(.id == "doctor") | .label' <<<"$output")"
  run jq -e 'any(.rows[]; .id == "extras.hello") | not' <<<"$output"
  [ "$status" -eq 0 ]
  [[ ! -e "$ROOT_DIR/$ZZ_MENU_REL/scripts/__pycache__" ]]
}

@test "zz menu guards see the per-user tool directories the terminal runner uses" {
  local home="$TEST_ROOT/tools-home"
  mkdir -p "$home/.dotnet"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$home/.dotnet/dotnet"
  chmod +x "$home/.dotnet/dotnet"

  # The session PATH has no dotnet; the guard must still find the per-user
  # install, so the .NET rows show.
  run_zz_menu_inventory "$home"
  [ "$status" -eq 0 ]
  run jq -e 'any(.rows[]; .id == "dotnet.devcert-status") and any(.rows[]; .id == "update.dotnet")' <<<"$output"
  [ "$status" -eq 0 ]

  # Without the install the rows stay hidden.
  rm -rf "$home/.dotnet"
  run_zz_menu_inventory "$home"
  [ "$status" -eq 0 ]
  run jq -e 'any(.rows[]; .id == "dotnet.devcert-status") | not' <<<"$output"
  [ "$status" -eq 0 ]

  # The runner exports the same directories before the terminal starts.
  assert_file_contains "$ROOT_DIR/$ZZ_MENU_REL/scripts/zz-menu-run" '$HOME/.local/bin:$DOTNET_ROOT:$DOTNET_ROOT/tools'
  assert_file_contains "$ROOT_DIR/$ZZ_MENU_REL/scripts/zz-menu-run" 'DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"'
}

@test "zz menu apps group lists catalog choices per category and installs or removes by state" {
  local home="$TEST_ROOT/apps-home"
  mkdir -p "$home/bin"
  cat >"$home/bin/zz" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "app list")
    printf '%s\n' '[{"category":"dev","category_label":"Development","id":"zed","label":"Zed","description":"Editor","default":true,"selected":true,"installed":false,"units":["dev-zed"]},{"category":"office","category_label":"Office","id":"pinta","label":"Pinta","description":"Painter","default":true,"selected":true,"installed":true,"units":["office-pinta"]}]'
    ;;
  "refresh --list")
    printf 'niri/config.kdl  Seeds the Niri entrypoint\n'
    ;;
esac
EOF
  chmod +x "$home/bin/zz"

  run bash -c "env -i HOME='$home' PATH='/usr/bin:/bin' XDG_CONFIG_HOME='$home/.config' ZZ_MENU_ZZ='$home/bin/zz' \
    '$ROOT_DIR/$ZZ_MENU_REL/scripts/zz-menu-inventory' 2>/dev/null"
  [ "$status" -eq 0 ]
  local inventory="$output"

  # One subgroup per category under Apps; a row installs when absent and
  # removes when present, and says which in its subtitle and icon.
  assert_equal "apps" "$(jq -r '.groups[] | select(.id == "apps.dev") | .parent' <<<"$inventory")"
  assert_equal "Development" "$(jq -r '.groups[] | select(.id == "apps.dev") | .label' <<<"$inventory")"
  assert_equal "apps.dev" "$(jq -r '.rows[] | select(.id == "apps.dev.zed") | .parent' <<<"$inventory")"
  assert_equal "zz app install dev/zed" "$(jq -r '.rows[] | select(.id == "apps.dev.zed") | .action' <<<"$inventory")"
  assert_equal "Install: Editor" "$(jq -r '.rows[] | select(.id == "apps.dev.zed") | .description' <<<"$inventory")"
  assert_equal "download" "$(jq -r '.rows[] | select(.id == "apps.dev.zed") | .icon' <<<"$inventory")"
  assert_equal "true" "$(jq -r '.rows[] | select(.id == "apps.dev.zed") | .terminal' <<<"$inventory")"
  assert_equal "zz app remove office/pinta" "$(jq -r '.rows[] | select(.id == "apps.office.pinta") | .action' <<<"$inventory")"
  assert_equal "Installed, remove: Painter" "$(jq -r '.rows[] | select(.id == "apps.office.pinta") | .description' <<<"$inventory")"
  assert_equal "check_circle" "$(jq -r '.rows[] | select(.id == "apps.office.pinta") | .icon' <<<"$inventory")"
  run jq -e '.rows[] | select(.id == "apps.office.pinta") | .keywords | index("uninstall") != null' <<<"$inventory"
  [ "$status" -eq 0 ]
  # The static listing row and the other provider share the launcher.
  assert_equal "zz app list" "$(jq -r '.rows[] | select(.id == "apps.list") | .action' <<<"$inventory")"
  assert_equal "zz refresh niri/config.kdl" "$(jq -r '.rows[] | select(.id == "refresh.niri-config-kdl") | .action' <<<"$inventory")"
}

@test "agent-usage selection plans the plugin link, unit, and interpreter" {
  build_test_plan "ai=agent-usage"

  assert_plan_has "$PLAN_DIR/bundles.list" "ai-agent-usage"
  assert_plan_has "$PLAN_DIR/config/components.list" "$AGENT_USAGE_COMPONENT"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "$AGENT_USAGE_PATH"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "python3"
}

@test "agent-usage is a default ai choice" {
  run default_choice_ids ai
  [ "$status" -eq 0 ]
  assert_contains "$output" "agent-usage"
}

@test "base plan links the ZZ menu and seeds enablement only for planned plugins" {
  build_test_plan

  assert_plan_has "$PLAN_DIR/config/components.list" "dms"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "$ZZ_MENU_PATH"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "$PLUGIN_SETTINGS_PATH"
  refute_plan_has "$PLAN_DIR/files/managed-files.list" "$AGENT_USAGE_PATH"
  run dms_plugin_settings_seed_json
  [ "$status" -eq 0 ]
  assert_equal "true" "$(jq -r '.zzMenu.enabled' <<<"$output")"
  assert_equal "null" "$(jq -r '.agentUsage' <<<"$output")"

  build_test_plan "ai=agent-usage"
  run dms_plugin_settings_seed_json
  [ "$status" -eq 0 ]
  assert_equal "true" "$(jq -r '.zzMenu.enabled' <<<"$output")"
  assert_equal "true" "$(jq -r '.agentUsage.enabled' <<<"$output")"
}

# The shell is "running": every dms call is recorded instead of sent.
record_dms_ipc() {
  local ipc_log="$1"
  eval "run_cmd_as_user() {
    shift
    if [[ \"\$1\" == dms ]]; then
      printf '%s\\n' \"\$*\" >>'$ipc_log'
      [[ \"\$*\" == *'plugins enable'* ]] && printf 'PLUGIN_ENABLE_SUCCESS\\n'
      return 0
    fi
    \"\$@\"
  }"
}

@test "the first plugin enablement seed loads the plugins into a running shell and preserves user edits" {
  build_test_plan "ai=agent-usage"
  local config="$TARGET_HOME/.config/DankMaterialShell"
  local settings="$config/plugin_settings.json"
  local ipc_log="$TEST_ROOT/ipc.log"
  DRY_RUN=0
  SKIP_USER_CONFIG=0
  STATE_DIR="$TEST_ROOT/state"
  CACHE_DIR="$TEST_ROOT/cache"
  mkdir -p "$CACHE_DIR"
  record_dms_ipc "$ipc_log"

  # An install whose state seeds ran before any plugin shipped, or a plugin
  # choice added from the desktop: the file is seeded and the shell asked to
  # load what it just gained.
  dms_seed_state_files_if_missing
  [[ ! -e "$settings" ]]
  [[ -f "$config/settings.json" ]]
  dms_apply_plugin_defaults

  assert_equal "true" "$(jq -r '.zzMenu.enabled' "$settings")"
  assert_equal "true" "$(jq -r '.agentUsage.enabled' "$settings")"
  assert_file_contains "$ipc_log" "dms ipc call plugin-scan scan"
  assert_file_contains "$ipc_log" "dms ipc call plugins enable zzMenu"
  assert_file_contains "$ipc_log" "dms ipc call plugins enable agentUsage"
  assert_file_contains "$STATE_DIR/dms-placed-widgets" "zzMenu"

  # The user's own edits stand on the next apply, and the shell is left alone.
  printf '{"zzMenu":{"enabled":false},"agentUsage":{"enabled":true}}\n' >"$settings"
  : >"$ipc_log"
  dms_apply_plugin_defaults
  assert_equal "false" "$(jq -r '.zzMenu.enabled' "$settings")"
  [[ ! -s "$ipc_log" ]]
}

@test "a widget is recorded as placed only once the bar carries it" {
  build_test_plan
  local config="$TARGET_HOME/.config/DankMaterialShell"
  local settings="$config/settings.json"
  DRY_RUN=0
  SKIP_USER_CONFIG=0
  STATE_DIR="$TEST_ROOT/state"
  CACHE_DIR="$TEST_ROOT/cache"
  mkdir -p "$CACHE_DIR" "$config"
  record_dms_ipc "$TEST_ROOT/ipc.log"
  printf '{"zzMenu":{"enabled":true}}\n' >"$config/plugin_settings.json"

  # DMS writes no barConfigs while the bar is at its own defaults: nothing
  # to insert into yet, so the placement stays pending.
  printf '{"customThemeFile":"keep"}\n' >"$settings"
  run dms_apply_plugin_defaults
  [ "$status" -eq 0 ]
  assert_contains "$output" "placed once the shell writes one"
  assert_equal '{"customThemeFile":"keep"}' "$(jq -c . "$settings")"
  [[ ! -e "$STATE_DIR/dms-placed-widgets" ]]

  cat >"$settings" <<'EOF'
{"customThemeFile":"keep","barConfigs":[{"id":"default","leftWidgets":["launcherButton"],"centerWidgets":[],"rightWidgets":["systemTray","clipboard"]}]}
EOF
  dms_apply_plugin_defaults
  assert_equal '["systemTray","zzMenu","clipboard"]' "$(jq -c '.barConfigs[0].rightWidgets' "$settings")"
  assert_file_contains "$STATE_DIR/dms-placed-widgets" "zzMenu"
}

@test "forgetting a plugin unloads it, drops its enablement and widget, and lets a re-add place it again" {
  build_test_plan "ai=agent-usage"
  local config="$TARGET_HOME/.config/DankMaterialShell"
  local settings="$config/settings.json"
  local plugins="$config/plugin_settings.json"
  local ipc_log="$TEST_ROOT/ipc.log"
  DRY_RUN=0
  SKIP_USER_CONFIG=0
  STATE_DIR="$TEST_ROOT/state"
  CACHE_DIR="$TEST_ROOT/cache"
  mkdir -p "$CACHE_DIR" "$config"
  record_dms_ipc "$ipc_log"
  printf '{"zzMenu":{"enabled":true},"agentUsage":{"enabled":true},"launcherExample":{"enabled":true}}\n' >"$plugins"
  cat >"$settings" <<'EOF'
{"barConfigs":[{"id":"default","leftWidgets":["launcherButton"],"centerWidgets":[],"rightWidgets":["systemTray","zzMenu",{"id":"agentUsage","size":1},"battery"]}]}
EOF
  printf 'zzMenu\nagentUsage\n' >"$STATE_DIR/dms-placed-widgets"

  run dms_component_plugin_ids "$AGENT_USAGE_COMPONENT"
  [ "$status" -eq 0 ]
  assert_equal "agentUsage" "$output"
  run dms_component_plugin_ids core
  [ "$status" -eq 0 ]
  assert_equal "" "$output"

  dms_forget_plugin agentUsage
  assert_file_contains "$ipc_log" "dms ipc call plugins disable agentUsage"
  assert_equal "null" "$(jq -r '.agentUsage' "$plugins")"
  assert_equal "true" "$(jq -r '.launcherExample.enabled' "$plugins")"
  assert_equal '["systemTray","zzMenu","battery"]' "$(jq -c '.barConfigs[0].rightWidgets' "$settings")"
  assert_equal "zzMenu" "$(cat "$STATE_DIR/dms-placed-widgets")"

  # Added again later: enabled, placed, and loaded like any new plugin.
  : >"$ipc_log"
  dms_apply_plugin_defaults
  assert_equal "true" "$(jq -r '.agentUsage.enabled' "$plugins")"
  assert_equal '["systemTray","zzMenu","agentUsage","battery"]' "$(jq -c '.barConfigs[0].rightWidgets' "$settings")"
  assert_file_contains "$ipc_log" "dms ipc call plugins enable agentUsage"
}

@test "a plugin shipped after install is enabled, placed in the bar once, and user removal is respected" {
  build_test_plan "ai=agent-usage"
  local config="$TARGET_HOME/.config/DankMaterialShell"
  local settings="$config/settings.json"
  local plugins="$config/plugin_settings.json"
  local ipc_log="$TEST_ROOT/ipc.log"
  DRY_RUN=0
  SKIP_USER_CONFIG=0
  STATE_DIR="$TEST_ROOT/state"
  CACHE_DIR="$TEST_ROOT/cache"
  mkdir -p "$CACHE_DIR" "$config"
  record_dms_ipc "$ipc_log"

  # An install from before either plugin existed: the seeds already ran and
  # the user reshaped the bar (memUsage gone, an object entry, a plugin of
  # their own enabled).
  printf '{"launcherExample":{"enabled":true}}\n' >"$plugins"
  cat >"$settings" <<'EOF'
{"customThemeFile":"keep","barConfigs":[{"id":"default","leftWidgets":["launcherButton",{"id":"workspaceSwitcher","size":1}],"centerWidgets":["clock"],"rightWidgets":["systemTray","clipboard","notificationButton","battery"]}]}
EOF

  dms_apply_plugin_defaults

  assert_equal "true" "$(jq -r '.zzMenu.enabled' "$plugins")"
  assert_equal "true" "$(jq -r '.agentUsage.enabled' "$plugins")"
  assert_equal "true" "$(jq -r '.launcherExample.enabled' "$plugins")"
  assert_equal '["launcherButton",{"id":"workspaceSwitcher","size":1}]' "$(jq -c '.barConfigs[0].leftWidgets' "$settings")"
  # agentUsage lands before notificationButton, its next seed neighbor still
  # in the section, since memUsage is gone; zzMenu follows the system tray
  # as in the seed.
  assert_equal '["systemTray","zzMenu","clipboard","agentUsage","notificationButton","battery"]' "$(jq -c '.barConfigs[0].rightWidgets' "$settings")"
  assert_equal "keep" "$(jq -r '.customThemeFile' "$settings")"
  assert_file_contains "$STATE_DIR/dms-placed-widgets" "zzMenu"
  assert_file_contains "$STATE_DIR/dms-placed-widgets" "agentUsage"
  assert_file_contains "$ipc_log" "dms ipc call plugin-scan scan"
  assert_file_contains "$ipc_log" "dms ipc call plugins enable zzMenu"
  assert_file_contains "$ipc_log" "dms ipc call plugins enable agentUsage"

  # The user disables one plugin and removes the other from the bar:
  # a second apply brings neither back and leaves the shell alone.
  jq '.zzMenu.enabled = false' "$plugins" >"$plugins.next" && mv "$plugins.next" "$plugins"
  jq '.barConfigs[0].rightWidgets -= ["agentUsage"]' "$settings" >"$settings.next" && mv "$settings.next" "$settings"
  : >"$ipc_log"
  dms_apply_plugin_defaults
  assert_equal "false" "$(jq -r '.zzMenu.enabled' "$plugins")"
  assert_equal '["systemTray","zzMenu","clipboard","notificationButton","battery"]' "$(jq -c '.barConfigs[0].rightWidgets' "$settings")"
  [[ ! -s "$ipc_log" ]]

  # A plugin the plan leaves out is neither enabled nor placed.
  build_test_plan
  printf '{}\n' >"$plugins"
  rm -f "$STATE_DIR/dms-placed-widgets"
  jq '.barConfigs[0].rightWidgets -= ["zzMenu"]' "$settings" >"$settings.next" && mv "$settings.next" "$settings"
  dms_apply_plugin_defaults
  assert_equal "true" "$(jq -r '.zzMenu.enabled' "$plugins")"
  assert_equal "null" "$(jq -r '.agentUsage' "$plugins")"
  assert_equal '["systemTray","zzMenu","clipboard","notificationButton","battery"]' "$(jq -c '.barConfigs[0].rightWidgets' "$settings")"
}

@test "plugin components link the repository plugin directories" {
  local menu_link="$TARGET_HOME/.config/DankMaterialShell/plugins/ZzMenu"
  local usage_link="$TARGET_HOME/.config/DankMaterialShell/plugins/AgentUsage"

  apply_component "dms"
  [[ -L "$menu_link" ]]
  [[ -f "$menu_link/plugin.json" ]]
  [[ -f "$menu_link/menu.json" ]]
  [[ -x "$menu_link/scripts/zz-menu-inventory" ]]
  assert_equal "$(readlink -f "$ROOT_DIR/$ZZ_MENU_REL")" "$(readlink -f "$menu_link")"
  [[ ! -e "$usage_link" ]]

  apply_component "$AGENT_USAGE_COMPONENT"
  [[ -L "$usage_link" ]]
  [[ -x "$usage_link/scripts/update-usage" ]]
  assert_equal "$(readlink -f "$ROOT_DIR/$AGENT_USAGE_REL")" "$(readlink -f "$usage_link")"
}

@test "settings seed places each shipped widget only when its plugin component is planned" {
  local menu_id usage_id
  menu_id="$(jq -r '.id' "$ROOT_DIR/$ZZ_MENU_REL/plugin.json")"
  usage_id="$(jq -r '.id' "$ROOT_DIR/$AGENT_USAGE_REL/plugin.json")"
  local widgets='.barConfigs[0] | (.leftWidgets + .centerWidgets + .rightWidgets)'

  # The ZZ button sits on the right, right after the system tray.
  assert_equal "$menu_id" "$(jq -r '.barConfigs[0].rightWidgets[1]' "$ROOT_DIR/templates/dms/settings-seed.json")"
  assert_equal "systemTray" "$(jq -r '.barConfigs[0].rightWidgets[0]' "$ROOT_DIR/templates/dms/settings-seed.json")"
  run jq -e --arg id "$usage_id" "$widgets | index(\$id) != null" "$ROOT_DIR/templates/dms/settings-seed.json"
  [ "$status" -eq 0 ]

  # The base plan keeps the base plugin's widget and drops the optional one,
  # which DMS would otherwise list as an unavailable entry in the bar editor.
  build_test_plan
  run dms_settings_seed_json
  [ "$status" -eq 0 ]
  local seed="$output"
  run jq -e --arg menu "$menu_id" --arg usage "$usage_id" \
    "($widgets | index(\$menu) != null) and ($widgets | index(\$usage) == null) and ($widgets | index(\"notificationButton\") != null)" <<<"$seed"
  [ "$status" -eq 0 ]
  assert_equal "$(dms_theme_file)" "$(jq -r '.customThemeFile' <<<"$seed")"

  build_test_plan "ai=agent-usage"
  run dms_settings_seed_json
  [ "$status" -eq 0 ]
  run jq -e --arg menu "$menu_id" --arg usage "$usage_id" \
    "($widgets | index(\$menu) != null) and ($widgets | index(\$usage) != null)" <<<"$output"
  [ "$status" -eq 0 ]
}

@test "claude collector summarizes transcripts offline and reports missing auth" {
  local home="$TEST_ROOT/claude-home"
  write_claude_transcript "$home"

  run_plugin_script "$home" collect-claude --force
  [ "$status" -eq 0 ]

  local record="$output"
  assert_equal "claude" "$(jq -r '.id' <<<"$record")"
  # The duplicated message id counts once; the older message counts too.
  assert_equal "2" "$(jq -r '.totalPrompts' <<<"$record")"
  assert_equal "1" "$(jq -r '.todayPrompts' <<<"$record")"
  assert_equal "175" "$(jq -r '.todayTotalTokens' <<<"$record")"
  assert_equal "100" "$(jq -r '.modelUsage["claude-opus-4-8"].inputTokens' <<<"$record")"
  assert_equal "20" "$(jq -r '.modelUsage["claude-opus-4-8"].cacheReadInputTokens' <<<"$record")"
  assert_equal "2" "$(jq -r '.activeDays' <<<"$record")"
  assert_equal "7" "$(jq -r '.recentDays | length' <<<"$record")"
  assert_equal "175" "$(jq -r '.recentDays[-1].messageCount' <<<"$record")"
  assert_equal "Waiting for auth" "$(jq -r '.usageStatusText' <<<"$record")"
  assert_equal "[]" "$(jq -c '.limits' <<<"$record")"
  [[ -d "$home/.cache/zz-fedora/agent-usage" ]]
  # Importing the shared module must not litter the linked checkout.
  [[ ! -e "$ROOT_DIR/$AGENT_USAGE_REL/scripts/__pycache__" ]]
}

@test "claude collector falls back to the stats cache with tokens per calendar day" {
  local home="$TEST_ROOT/claude-cache-home"
  write_claude_stats_cache "$home"

  run_plugin_script "$home" collect-claude --force
  [ "$status" -eq 0 ]

  local record="$output"
  assert_equal "40" "$(jq -r '.totalPrompts' <<<"$record")"
  assert_equal "2" "$(jq -r '.activeDays' <<<"$record")"
  # recentDays covers the last seven calendar days and carries token totals,
  # never the message counts dailyActivity keeps.
  assert_equal "7" "$(jq -r '.recentDays | length' <<<"$record")"
  assert_equal "$(date +%Y-%m-%d)" "$(jq -r '.recentDays[-1].date' <<<"$record")"
  assert_equal "1750" "$(jq -r '.recentDays[-1].messageCount' <<<"$record")"
  assert_equal "0" "$(jq -r '.recentDays[0].messageCount' <<<"$record")"
  assert_equal "1750" "$(jq -r '.todayTotalTokens' <<<"$record")"
}

@test "codex collector counts the last turn of each token snapshot and reports a missing CLI" {
  local home="$TEST_ROOT/codex-home"
  write_codex_session "$home"

  run_plugin_script "$home" collect-codex --force
  [ "$status" -eq 0 ]

  local record="$output"
  assert_equal "codex" "$(jq -r '.id' <<<"$record")"
  assert_equal "2" "$(jq -r '.totalPrompts' <<<"$record")"
  assert_equal "1" "$(jq -r '.totalSessions' <<<"$record")"
  # Cached tokens are carved out of input rather than counted twice.
  assert_equal "500" "$(jq -r '.modelUsage["gpt-5.6-codex"].inputTokens' <<<"$record")"
  assert_equal "100" "$(jq -r '.modelUsage["gpt-5.6-codex"].cacheReadInputTokens' <<<"$record")"
  assert_equal "140" "$(jq -r '.modelUsage["gpt-5.6-codex"].outputTokens' <<<"$record")"
  assert_equal "Codex unavailable" "$(jq -r '.usageStatusText' <<<"$record")"
  assert_equal "[]" "$(jq -c '.limits' <<<"$record")"
}

@test "codex collector keeps the last probed limits whose window is still open" {
  local home="$TEST_ROOT/codex-cache-home"
  local cache="$home/.cache/zz-fedora/agent-usage"
  mkdir -p "$cache"
  local open closed
  open="$(date -u -d '+3 hours' +%Y-%m-%dT%H:%M:%S+00:00)"
  closed="$(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%S+00:00)"
  cat >"$cache/codex-limits.json" <<EOF
{"fetchedAtMs":0,"tierLabel":"plus","limits":[
 {"label":"5h window","title":"Session","percent":0.42,"resetsAt":"$open"},
 {"label":"Weekly (7-day)","title":"Weekly","percent":0.9,"resetsAt":"$closed"}]}
EOF

  run_plugin_script "$home" collect-codex
  [ "$status" -eq 0 ]

  local record="$output"
  assert_equal "plus" "$(jq -r '.tierLabel' <<<"$record")"
  assert_equal "1" "$(jq -r '.limits | length' <<<"$record")"
  assert_equal "Session" "$(jq -r '.limits[0].title' <<<"$record")"
  assert_equal "Codex unavailable" "$(jq -r '.usageStatusText' <<<"$record")"
}

@test "update-usage writes one record per collector into the state directory" {
  local home="$TEST_ROOT/update-home"
  write_claude_transcript "$home"

  run_plugin_script "$home" update-usage --force
  [ "$status" -eq 0 ]

  local usage_dir="$home/.local/state/zz-fedora/agent-usage"
  [[ -f "$usage_dir/claude.json" ]]
  [[ -f "$usage_dir/codex.json" ]]
  assert_equal "claude" "$(jq -r '.id' "$usage_dir/claude.json")"
  assert_equal "codex" "$(jq -r '.id' "$usage_dir/codex.json")"
  run find "$usage_dir" -name '*.tmp'
  [ -z "$output" ]

  # --except and positional ids narrow the run without touching other records.
  rm "$usage_dir/codex.json"
  run_plugin_script "$home" update-usage --except codex
  [ "$status" -eq 0 ]
  [[ -f "$usage_dir/claude.json" ]]
  [[ ! -e "$usage_dir/codex.json" ]]

  run_plugin_script "$home" update-usage codex
  [ "$status" -eq 0 ]
  [[ -f "$usage_dir/codex.json" ]]
}
