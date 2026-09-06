#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

PLUGIN_ROOT_REL="dotfiles/dms/.config/DankMaterialShell/plugins"
AGENT_USAGE_REL="$PLUGIN_ROOT_REL/AgentUsage"
AGENT_USAGE_COMPONENT="dms-plugin-agent-usage"

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

@test "agent-usage selection plans the plugin link, enablement seed, unit, and interpreter" {
  build_test_plan "ai=agent-usage"

  assert_plan_has "$PLAN_DIR/bundles.list" "ai-agent-usage"
  assert_plan_has "$PLAN_DIR/config/components.list" "$AGENT_USAGE_COMPONENT"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/DankMaterialShell/plugins/AgentUsage"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/DankMaterialShell/plugin_settings.json"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "python3"
}

@test "agent-usage is a default ai choice" {
  run default_choice_ids ai
  [ "$status" -eq 0 ]
  assert_contains "$output" "agent-usage"
}

@test "base plan neither links the plugin nor seeds its enablement" {
  build_test_plan

  refute_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/DankMaterialShell/plugins/AgentUsage"
  refute_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/DankMaterialShell/plugin_settings.json"
}

@test "plugin component seeds enablement before linking the directory and preserves user edits" {
  local settings="$TARGET_HOME/.config/DankMaterialShell/plugin_settings.json"
  local link="$TARGET_HOME/.config/DankMaterialShell/plugins/AgentUsage"

  apply_component "$AGENT_USAGE_COMPONENT"

  # DMS reads the enabled flag when it discovers the directory, so the seed
  # row must come first in the deployment plan.
  run awk -F'\t' -v c="$AGENT_USAGE_COMPONENT" '$1 == c { print $3 }' "$(managed_config_deployment_plan_file)"
  assert_equal $'seed-if-missing\nproduct-link' "$output"
  assert_equal "true" "$(jq -r '.agentUsage.enabled' "$settings")"
  [[ -L "$link" ]]
  [[ -f "$link/plugin.json" ]]
  [[ -x "$link/scripts/update-usage" ]]
  assert_equal "$(readlink -f "$ROOT_DIR/$AGENT_USAGE_REL")" "$(readlink -f "$link")"

  printf '{"agentUsage":{"enabled":false}}\n' >"$settings"
  apply_component "$AGENT_USAGE_COMPONENT"
  assert_equal "false" "$(jq -r '.agentUsage.enabled' "$settings")"
}

@test "settings seed places the widget only when its plugin component is planned" {
  local id
  id="$(jq -r '.id' "$ROOT_DIR/$AGENT_USAGE_REL/plugin.json")"
  local widgets='.barConfigs[0] | (.leftWidgets + .centerWidgets + .rightWidgets)'

  run jq -e --arg id "$id" "$widgets | index(\$id) != null" "$ROOT_DIR/templates/dms/settings-seed.json"
  [ "$status" -eq 0 ]

  build_test_plan "ai=agent-usage"
  run dms_settings_seed_json
  [ "$status" -eq 0 ]
  run jq -e --arg id "$id" "$widgets | index(\$id) != null" <<<"$output"
  [ "$status" -eq 0 ]

  # A deselected choice leaves no dangling widget id, which DMS would list
  # as an unavailable entry in the bar editor. Everything else survives.
  build_test_plan "ai=claude-code"
  refute_plan_has "$PLAN_DIR/config/components.list" "$AGENT_USAGE_COMPONENT"
  run dms_settings_seed_json
  [ "$status" -eq 0 ]
  local seed="$output"
  run jq -e --arg id "$id" "($widgets | index(\$id) == null) and ($widgets | index(\"notificationButton\") != null)" <<<"$seed"
  [ "$status" -eq 0 ]
  assert_equal "$(dms_theme_file)" "$(jq -r '.customThemeFile' <<<"$seed")"
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
