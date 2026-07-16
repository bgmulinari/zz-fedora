#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  PLUGIN_DIR="$ROOT_DIR/dotfiles/noctalia/.local/share/noctalia/plugins/niri-outputs"
  BACKEND="$PLUGIN_DIR/backend.py"
  FAKE_BIN="$TEST_ROOT/bin"
  NIRI_LOG="$TEST_ROOT/niri.log"
  NIRI_STATE="$TEST_ROOT/niri-outputs.json"
  NIRI_FAIL_FILE="$TEST_ROOT/reject-config-load"
  NIRI_OUTPUTS_READY="$TEST_ROOT/outputs-ready"
  NIRI_OUTPUTS_RELEASE="$TEST_ROOT/outputs-release"
  DISPLAY_CONFIG="$TEST_ROOT/config/niri/cfg/display.kdl"
  MAIN_CONFIG="$TEST_ROOT/config/niri/config.kdl"
  MAIN_SOURCE="$TEST_ROOT/managed/niri/config.kdl"
  DRAFT="$TEST_ROOT/draft.json"
  export NIRI_LOG NIRI_STATE NIRI_FAIL_FILE NIRI_OUTPUTS_READY NIRI_OUTPUTS_RELEASE
  export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
  mkdir -p "$FAKE_BIN" "$XDG_RUNTIME_DIR" "$(dirname "$DISPLAY_CONFIG")" "$(dirname "$MAIN_SOURCE")"

  printf '%s\n' 'include "./cfg/input.kdl"' 'include "./cfg/display.kdl"' >"$MAIN_SOURCE"
  ln -s "$MAIN_SOURCE" "$MAIN_CONFIG"
  printf '%s\n' 'input {}' >"$(dirname "$DISPLAY_CONFIG")/input.kdl"
  printf '%s\n' 'output "HDMI-A-1" {' '    scale 1.5' '    max-bpc 10' '}' >"$DISPLAY_CONFIG"
  printf '%s\n' '{"HDMI-A-1":{"name":"HDMI-A-1","make":"Acme","model":"Panel","serial":"42","physical_size":[600,340],"modes":[{"width":2560,"height":1440,"refresh_rate":59950,"is_preferred":false},{"width":2560,"height":1440,"refresh_rate":143912,"is_preferred":true}],"current_mode":1,"is_custom_mode":true,"vrr_supported":true,"vrr_enabled":true,"logical":{"x":1920,"y":0,"width":1707,"height":960,"scale":1.5,"transform":"Normal"}},"DP-2":{"name":"DP-2","make":"Acme","model":"Standby","serial":null,"physical_size":[520,320],"modes":[{"width":1920,"height":1080,"refresh_rate":60000,"is_preferred":true}],"current_mode":null,"is_custom_mode":false,"vrr_supported":false,"vrr_enabled":false,"logical":null}}' >"$NIRI_STATE"
  printf '%s\n' '{"outputs":[{"name":"DP-2","enabled":false,"mode":"1920x1080@60.000","custom_mode":false,"scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false},{"name":"HDMI-A-1","enabled":true,"mode":"2560x1440@143.912","custom_mode":true,"scale":1.25,"transform":"normal","x":1920,"y":0,"vrr_supported":true,"vrr_enabled":false}]}' >"$DRAFT"

  cat >"$FAKE_BIN/niri" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$NIRI_LOG"

if [[ "$*" == "msg -j outputs" ]]; then
  command cat "$NIRI_STATE"
  if [[ "${NIRI_BLOCK_OUTPUTS:-false}" == "true" ]]; then
    : >"$NIRI_OUTPUTS_READY"
    while [[ ! -e "$NIRI_OUTPUTS_RELEASE" ]]; do
      sleep 0.01
    done
  fi
  exit 0
fi

if [[ "$*" == "msg -j event-stream" ]]; then
  printf '%s\n' '{"ConfigLoaded":{"failed":false}}'
  failed=false
  if [[ -e "$NIRI_FAIL_FILE" || "${NIRI_CONFIG_LOAD_FAILED:-false}" == "true" ]]; then
    failed=true
  fi
  printf '{"ConfigLoaded":{"failed":%s}}\n' "$failed"
  exit 0
fi

if [[ "${1:-}" == "validate" ]]; then
  candidate="${3:-}"
  if [[ "${NIRI_VALIDATE_FAILED:-false}" == "true" || ! -f "$candidate" ]]; then
    printf '%s\n' 'simulated validation failure' >&2
    exit 1
  fi
  exit 0
fi

if [[ "${1:-}" == "msg" && "${2:-}" == "output" ]]; then
  printf '%s\n' 'per-output IPC is forbidden by this test' >&2
  exit 99
fi

if [[ "${NIRI_ACTION_FAILED:-false}" == "true" && "${1:-}" == "msg" && "${2:-}" == "action" ]]; then
  printf '%s\n' 'simulated action failure' >&2
  exit 1
fi

exit 0
EOF
  chmod +x "$FAKE_BIN/niri"
}

preview() {
  env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview \
    --draft "$DRAFT" \
    --display-config "$DISPLAY_CONFIG" \
    --main-config "$MAIN_CONFIG" \
    --timeout 5
}

json_field() {
  python3 -c 'import json,sys; print(json.loads(sys.argv[1])[sys.argv[2]])' "$1" "$2"
}

@test "managed Noctalia config enables Niri Outputs and places its bar launcher" {
  config="$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml"

  assert_file_contains "$config" 'enabled = [ "local/niri-outputs" ]'
  assert_file_contains "$config" 'type = "local/niri-outputs:launcher"'
  assert_file_contains "$config" '"niri-outputs",'
}

@test "plugin manifest exposes a panel, bar widget, and Control Center shortcut" {
  manifest="$PLUGIN_DIR/plugin.toml"
  panel_source="$PLUGIN_DIR/panel.luau"
  translations="$PLUGIN_DIR/translations/en.json"

  assert_file_contains "$manifest" 'id = "local/niri-outputs"'
  assert_file_contains "$manifest" 'name = "Niri Outputs"'
  assert_file_contains "$manifest" 'plugin_api = 3'
  assert_file_contains "$manifest" '[[panel]]'
  assert_file_contains "$manifest" '[[widget]]'
  assert_file_contains "$manifest" '[[shortcut]]'
  assert_file_contains "$manifest" 'label_key = "settings.confirm_timeout.label"'
  assert_file_contains "$manifest" 'description_key = "settings.confirm_timeout.description"'
  assert_file_contains "$translations" '"label": "Preview Timeout"'
  assert_file_contains "$panel_source" 'local displayConfigPath = noctalia.expandPath("~/.config/niri/cfg/display.kdl")'
  assert_file_contains "$panel_source" 'local mainConfigPath = noctalia.expandPath("~/.config/niri/config.kdl")'
  assert_file_contains "$panel_source" 'noctalia.getConfig("confirm_timeout")'
  refute_file_contains "$panel_source" 'panel.getConfig('
}

@test "plugin UI copy resolves through the English translation catalog" {
  run python3 - "$PLUGIN_DIR" <<'PY'
import ast
import json
from pathlib import Path
import re
import sys

plugin = Path(sys.argv[1])
catalog = json.loads((plugin / "translations/en.json").read_text())

def flatten(value, prefix=""):
    keys = set()
    for key, child in value.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(child, dict):
            keys.update(flatten(child, path))
        else:
            assert isinstance(child, str), path
            keys.add(path)
    return keys

sources = "\n".join((plugin / name).read_text() for name in ("panel.luau", "widget.luau", "shortcut.luau"))
manifest = (plugin / "plugin.toml").read_text()
backend = (plugin / "backend.py").read_text()
direct = set(re.findall(r'\b(?:noctalia\.)?tr\("([^"]+)"', sources))
plural = set(re.findall(r'\bnoctalia\.trp\("([^"]+)"', sources))
manifest_keys = set(re.findall(r'(?:label|description)_key\s*=\s*"([^"]+)"', manifest))
backend_keys = set(re.findall(r'error_key(?::[^=,\n]+)?\s*=\s*"([^"]+)"', backend))
resolved = direct | manifest_keys | backend_keys
for key in plural:
    resolved.update({f"{key}.one", f"{key}.other"})

catalog_keys = flatten(catalog)
assert not resolved - catalog_keys, f"missing translations: {sorted(resolved - catalog_keys)}"
assert not catalog_keys - resolved, f"unused translations: {sorted(catalog_keys - resolved)}"

literal_ui_patterns = (
    r'\b(?:setTooltip|setLabel|setStatus|queryOutputs|restorePreview)\(\s*"',
    r'\bsettingRow\(\s*"',
    r'\btext\s*=\s*"[^"]*[A-Za-z][^"]*"',
    r'\bstatusText\s*=\s*"',
)
for pattern in literal_ui_patterns:
    assert re.search(pattern, sources, re.MULTILINE) is None, pattern

tree = ast.parse(backend)
for node in ast.walk(tree):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "BackendError":
        assert any(keyword.arg == "error_key" for keyword in node.keywords), node.lineno
PY

  [ "$status" -eq 0 ]
}

@test "backend normalizes active and disabled Niri outputs" {
  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" query

  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["ok"] is True
assert payload["preview"] == {"active": False, "status": "inactive"}
assert [item["name"] for item in payload["outputs"]] == ["DP-2", "HDMI-A-1"]
disabled, active = payload["outputs"]
assert disabled["enabled"] is False
assert disabled["mode"] == "1920x1080@60.000"
assert active["enabled"] is True
assert active["mode"] == "2560x1440@143.912"
assert active["custom_mode"] is True
assert active["mode_preferred"] == [False, True]
assert active["scale"] == 1.5
assert active["x"] == 1920
assert active["vrr_enabled"] is True
PY
}

@test "preview switches once without touching or watching the persistent display file" {
  original="$(<"$DISPLAY_CONFIG")"

  run preview

  [ "$status" -eq 0 ]
  preview_id="$(json_field "$output" preview_id)"
  preview_display="$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview-output.kdl"
  preview_config="$(dirname "$MAIN_CONFIG")/.noctalia-niri-outputs-preview.kdl"
  token="$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview.json"

  [ "$(<"$DISPLAY_CONFIG")" = "$original" ]
  [ -f "$preview_display" ]
  [ -f "$preview_config" ]
  [ -f "$token" ]
  assert_file_contains "$preview_display" 'mode custom=true "2560x1440@143.912"'
  assert_file_contains "$preview_display" 'scale 1.25'
  refute_file_contains "$preview_display" 'variable-refresh-rate'
  python3 - "$preview_config" "$preview_display" "$MAIN_CONFIG" <<'PY'
from pathlib import Path
import json
import sys

content = Path(sys.argv[1]).read_text()
lines = content.splitlines()
assert lines[0] == 'include "./cfg/input.kdl"'
assert lines[1] == f"include {json.dumps(sys.argv[2])}"
assert './cfg/display.kdl' not in content
assert sys.argv[3] not in content
PY
  mapfile -t actions < <(grep '^msg action load-config-file --path ' "$NIRI_LOG")
  [ "${#actions[@]}" -eq 1 ]
  [ "${actions[0]}" = "msg action load-config-file --path $preview_config" ]
  refute_file_contains "$NIRI_LOG" 'msg output '

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" revert --preview-id "$preview_id"
  [ "$status" -eq 0 ]
}

@test "query exposes an active preview so a reopened panel can keep or revert it" {
  run preview
  [ "$status" -eq 0 ]
  preview_id="$(json_field "$output" preview_id)"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" query

  [ "$status" -eq 0 ]
  python3 - "$output" "$preview_id" <<'PY'
import json
import sys

preview = json.loads(sys.argv[1])["preview"]
assert preview["active"] is True
assert preview["id"] == sys.argv[2]
assert preview["status"] == "active"
assert preview["expires"] > 0
PY

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" revert --preview-id "$preview_id"
  [ "$status" -eq 0 ]
}

@test "query cannot mix preview outputs with post-restore preview state" {
  run preview
  [ "$status" -eq 0 ]
  preview_id="$(json_field "$output" preview_id)"
  token="$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview.json"
  query_result="$TEST_ROOT/query.json"
  revert_result="$TEST_ROOT/revert.json"
  revert_started="$TEST_ROOT/revert-started"

  env PATH="$FAKE_BIN:$PATH" NIRI_BLOCK_OUTPUTS=true python3 "$BACKEND" query >"$query_result" &
  query_pid=$!
  for _ in {1..100}; do
    [[ -e "$NIRI_OUTPUTS_READY" ]] && break
    sleep 0.01
  done

  (
    : >"$revert_started"
    exec env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" revert --preview-id "$preview_id" >"$revert_result"
  ) &
  revert_pid=$!
  for _ in {1..100}; do
    [[ -e "$revert_started" ]] && break
    sleep 0.01
  done
  sleep 0.1
  revert_blocked=false
  if kill -0 "$revert_pid" 2>/dev/null; then
    revert_blocked=true
  fi

  : >"$NIRI_OUTPUTS_RELEASE"
  query_status=0
  wait "$query_pid" || query_status=$?
  revert_status=0
  wait "$revert_pid" || revert_status=$?

  [ -e "$NIRI_OUTPUTS_READY" ]
  [ -e "$revert_started" ]
  [ "$revert_blocked" = true ]
  [ "$query_status" -eq 0 ]
  [ "$revert_status" -eq 0 ]
  python3 - "$query_result" "$preview_id" <<'PY'
import json
from pathlib import Path
import sys

preview = json.loads(Path(sys.argv[1]).read_text())["preview"]
assert preview["active"] is True
assert preview["id"] == sys.argv[2]
PY
  [ ! -e "$token" ]
}

@test "revert switches once back to the normal config and removes preview state" {
  run preview
  [ "$status" -eq 0 ]
  preview_id="$(json_field "$output" preview_id)"
  preview_display="$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview-output.kdl"
  preview_config="$(dirname "$MAIN_CONFIG")/.noctalia-niri-outputs-preview.kdl"
  token="$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview.json"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" revert --preview-id "$preview_id"

  [ "$status" -eq 0 ]
  [ ! -e "$token" ]
  [ ! -e "$preview_display" ]
  [ ! -e "$preview_config" ]
  mapfile -t actions < <(grep '^msg action load-config-file --path ' "$NIRI_LOG")
  [ "${#actions[@]}" -eq 2 ]
  [ "${actions[1]}" = "msg action load-config-file --path $MAIN_CONFIG" ]
  refute_file_contains "$NIRI_LOG" 'msg output '
}

@test "detached watchdog switches back to the normal config after timeout" {
  run preview
  [ "$status" -eq 0 ]
  token="$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview.json"

  for _ in {1..80}; do
    [[ -e "$token" ]] || break
    sleep 0.1
  done

  [ ! -e "$token" ]
  mapfile -t actions < <(grep '^msg action load-config-file --path ' "$NIRI_LOG")
  [ "${#actions[@]}" -eq 2 ]
  [ "${actions[1]}" = "msg action load-config-file --path $MAIN_CONFIG" ]
  refute_file_contains "$NIRI_LOG" 'msg output '
}

@test "keep copies the validated preview file, backs up the old file, and returns to normal config" {
  run preview
  [ "$status" -eq 0 ]
  preview_id="$(json_field "$output" preview_id)"
  rm "$DRAFT"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" keep --preview-id "$preview_id"

  [ "$status" -eq 0 ]
  assert_file_contains "$DISPLAY_CONFIG" '// Managed by the Noctalia Niri Outputs plugin.'
  assert_file_contains "$DISPLAY_CONFIG" 'mode custom=true "2560x1440@143.912"'
  assert_file_contains "$DISPLAY_CONFIG" 'scale 1.25'
  refute_file_contains "$DISPLAY_CONFIG" 'max-bpc'
  assert_file_contains "$DISPLAY_CONFIG.previous" 'max-bpc 10'
  [ ! -e "$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview.json" ]
  mapfile -t actions < <(grep '^msg action load-config-file --path ' "$NIRI_LOG")
  [ "${#actions[@]}" -eq 2 ]
  [ "${actions[1]}" = "msg action load-config-file --path $MAIN_CONFIG" ]
  refute_file_contains "$NIRI_LOG" 'msg output '
}

@test "expired preview cannot be kept and leaves the persistent file unchanged" {
  original="$(<"$DISPLAY_CONFIG")"
  run preview
  [ "$status" -eq 0 ]
  preview_id="$(json_field "$output" preview_id)"
  token="$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview.json"
  python3 - "$token" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = json.loads(path.read_text())
data["expires"] = 0
path.write_text(json.dumps(data))
PY

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" keep --preview-id "$preview_id"

  [ "$status" -ne 0 ]
  [ "$(<"$DISPLAY_CONFIG")" = "$original" ]
  [ ! -e "$token" ]
  [ ! -e "$DISPLAY_CONFIG.previous" ]
}

@test "failed preview validation cleans temporary files without switching Niri" {
  original="$(<"$DISPLAY_CONFIG")"

  run env PATH="$FAKE_BIN:$PATH" NIRI_VALIDATE_FAILED=true python3 "$BACKEND" preview \
    --draft "$DRAFT" \
    --display-config "$DISPLAY_CONFIG" \
    --main-config "$MAIN_CONFIG" \
    --timeout 5

  [ "$status" -ne 0 ]
  assert_contains "$output" 'simulated validation failure'
  [ "$(<"$DISPLAY_CONFIG")" = "$original" ]
  [ ! -e "$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview.json" ]
  [ -z "$(find "$XDG_RUNTIME_DIR" -name 'preview-*.kdl' -print -quit)" ]
  [ ! -e "$(dirname "$MAIN_CONFIG")/.noctalia-niri-outputs-preview.kdl" ]
  refute_file_contains "$NIRI_LOG" 'msg action load-config-file '
}

@test "failed revert stays recoverable and the watchdog retries the normal config" {
  run preview
  [ "$status" -eq 0 ]
  preview_id="$(json_field "$output" preview_id)"
  token="$XDG_RUNTIME_DIR/noctalia-niri-outputs-$(id -u)/preview.json"
  touch "$NIRI_FAIL_FILE"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" revert --preview-id "$preview_id"

  [ "$status" -ne 0 ]
  assert_contains "$output" '"key":"backend_errors.preview_restore_pending"'
  [ -e "$token" ]
  python3 - "$token" <<'PY'
import json
from pathlib import Path
import sys

assert json.loads(Path(sys.argv[1]).read_text())["status"] == "restoring"
PY

  rm "$NIRI_FAIL_FILE"
  for _ in {1..40}; do
    [[ -e "$token" ]] || break
    sleep 0.1
  done
  [ ! -e "$token" ]
}

@test "panel refreshes from Niri after keep, revert, timeout, and reopen" {
  run python3 - "$PLUGIN_DIR/panel.luau" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
query = source[source.index("local function queryOutputs"):source.index("local function modeIndex")]
keep = source[source.index("function keepChanges()"):source.index("restorePreview = function")]
restore = source[source.index("restorePreview = function"):source.index("function revertPreview()")]
on_open = source[source.index("function onOpen(context)"):source.index("function onClose()")]

assert "syncPreviewState(decoded.preview)" in query
assert 'local arguments = "keep --preview-id "' in keep
assert "--draft" not in keep
assert "queryOutputs(" in keep
assert "queryOutputs(successMessage" in restore
assert 'queryOutputs(tr("panel.status.ready"), tr("panel.status.loading_outputs"))' in on_open
assert "previewRollbackOutputs" not in source
assert 'previewStatus == "restoring"' in source
PY

  [ "$status" -eq 0 ]
}

@test "panel enables draft actions only for semantic output changes" {
  run python3 - "$PLUGIN_DIR/panel.luau" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
assert "local function outputSettingChanged(current, baseline)" in source
assert "local draftChanged = draftHasChanges()" in source
assert "enabled = not busy and not previewActive and draftChanged" in source
assert "enabled = not busy and not previewActive and not draftChanged" in source
assert 'enabled = not busy and previewActive and previewStatus == "active"' in source
PY

  [ "$status" -eq 0 ]
}

@test "backend refuses to disable every connected output" {
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":false,"mode":"1920x1200@60.003","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$DRAFT"

  run preview

  [ "$status" -ne 0 ]
  assert_contains "$output" 'at least one output must remain enabled'
  [ ! -e "$NIRI_LOG" ]
}
