#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  PLUGIN_DIR="$ROOT_DIR/dotfiles/noctalia/.local/share/noctalia/plugins/display-settings"
  BACKEND="$PLUGIN_DIR/backend.py"
  FAKE_BIN="$TEST_ROOT/bin"
  NIRI_LOG="$TEST_ROOT/niri.log"
  export NIRI_LOG
  export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
  mkdir -p "$FAKE_BIN" "$XDG_RUNTIME_DIR"

  cat >"$FAKE_BIN/niri" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$NIRI_LOG"
if [[ "$*" == "msg -j outputs" ]]; then
  printf '%s\n' '{"HDMI-A-1":{"name":"HDMI-A-1","make":"Acme","model":"Panel","serial":"42","physical_size":[600,340],"modes":[{"width":2560,"height":1440,"refresh_rate":59950,"is_preferred":false},{"width":2560,"height":1440,"refresh_rate":143912,"is_preferred":true}],"current_mode":1,"is_custom_mode":true,"vrr_supported":true,"vrr_enabled":true,"logical":{"x":1920,"y":0,"width":1707,"height":960,"scale":1.5,"transform":"Normal"}},"DP-2":{"name":"DP-2","make":"Acme","model":"Standby","serial":null,"physical_size":[520,320],"modes":[{"width":1920,"height":1080,"refresh_rate":60000,"is_preferred":true}],"current_mode":null,"is_custom_mode":false,"vrr_supported":false,"vrr_enabled":false,"logical":null}}'
  exit 0
fi
if [[ "$*" == "msg -j event-stream" ]]; then
  printf '%s\n' '{"ConfigLoaded":{"failed":false}}'
  printf '{"ConfigLoaded":{"failed":%s}}\n' "${NIRI_CONFIG_LOAD_FAILED:-false}"
  exit 0
fi
if [[ "${1:-}" == "validate" ]]; then
  exit 0
fi
exit 0
EOF
  chmod +x "$FAKE_BIN/niri"
}

@test "managed Noctalia config enables the display plugin and places its bar launcher" {
  config="$ROOT_DIR/dotfiles/noctalia/.config/noctalia/config.toml"

  assert_file_contains "$config" 'enabled = [ "local/display-settings" ]'
  assert_file_contains "$config" 'type = "local/display-settings:launcher"'
  assert_file_contains "$config" '"display-settings",'
}

@test "plugin manifest exposes a panel, bar widget, and Control Center shortcut" {
  manifest="$PLUGIN_DIR/plugin.toml"
  panel_source="$PLUGIN_DIR/panel.luau"

  assert_file_contains "$manifest" 'id = "local/display-settings"'
  assert_file_contains "$manifest" '[[panel]]'
  assert_file_contains "$manifest" '[[widget]]'
  assert_file_contains "$manifest" '[[shortcut]]'
  assert_file_contains "$manifest" 'width = 900'
  assert_file_contains "$manifest" 'height = 720'
  assert_file_contains "$manifest" 'placement = "attached"'
  assert_file_contains "$manifest" 'open_near_click = true'
  assert_file_contains "$panel_source" 'panel.render(ui.column({ gap = 12, padding = 14, flexGrow = 1 }, {'
  assert_file_contains "$panel_source" 'ui.separator({ orientation = "vertical" })'
  assert_file_contains "$panel_source" 'ui.scroll({ gap = 8, padding = 4, flexGrow = 1 }, detailContent())'
  assert_file_contains "$panel_source" 'local configPath = noctalia.expandPath("~/.config/niri/cfg/display.kdl")'
}

@test "backend normalizes active and disabled Niri outputs" {
  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" query

  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["ok"] is True
assert [item["name"] for item in payload["outputs"]] == ["DP-2", "HDMI-A-1"]
disabled, active = payload["outputs"]
assert disabled["enabled"] is False
assert disabled["mode"] == "1920x1080@60.000"
assert active["enabled"] is True
assert active["mode"] == "2560x1440@143.912"
assert active["custom_mode"] is True
assert active["mode_labels"][1].endswith("• custom")
assert active["scale"] == 1.5
assert active["x"] == 1920
assert active["vrr_enabled"] is True
PY
}

@test "keep validates, backs up, and writes the dedicated Niri display file" {
  draft="$TEST_ROOT/draft.json"
  target="$TEST_ROOT/config/niri/cfg/display.kdl"
  mkdir -p "$(dirname "$target")"
  printf 'output "eDP-1" {\n    scale 1\n}\n' >"$target"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1200@60.003","custom_mode":true,"scale":1.25,"transform":"normal","x":0,"y":0,"vrr_supported":true,"vrr_enabled":true},{"name":"HDMI-A-1","enabled":false,"mode":"2560x1440@60.000","custom_mode":false,"scale":1,"transform":"normal","x":1536,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$draft"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$target" --timeout 5
  [ "$status" -eq 0 ]
  preview_id="$(python3 -c 'import json, sys; print(json.loads(sys.argv[1])["preview_id"])' "$output")"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" keep --draft "$draft" --config "$target" --preview-id "$preview_id"

  [ "$status" -eq 0 ]
  assert_contains "$output" '"ok":true'
  assert_file_contains "$target" '// Managed by the Noctalia display settings plugin.'
  assert_file_contains "$target" 'mode custom=true "1920x1200@60.003"'
  assert_file_contains "$target" 'scale 1.25'
  assert_file_contains "$target" 'variable-refresh-rate'
  assert_file_contains "$target" 'output "HDMI-A-1" {'
  assert_file_contains "$target" '    off'
  assert_file_contains "$target.previous" 'scale 1'
  assert_file_contains "$NIRI_LOG" 'validate -c'
  assert_file_contains "$NIRI_LOG" 'msg output eDP-1 custom-mode 1920x1200@60.003'
  assert_file_contains "$NIRI_LOG" 'msg action load-config-file'
}

@test "preview applies temporary Niri output commands and explicit revert reloads config" {
  draft="$TEST_ROOT/draft.json"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1200@60.003","scale":1.5,"transform":"90","x":0,"y":0,"vrr_supported":true,"vrr_enabled":false},{"name":"HDMI-A-1","enabled":false,"mode":"2560x1440@60.000","scale":1,"transform":"normal","x":800,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$draft"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$ROOT_DIR/templates/niri/display.kdl" --timeout 5
  [ "$status" -eq 0 ]
  assert_contains "$output" '"ok":true'
  preview_id="$(python3 -c 'import json, sys; print(json.loads(sys.argv[1])["preview_id"])' "$output")"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" revert --preview-id "$preview_id"
  [ "$status" -eq 0 ]

  assert_file_contains "$NIRI_LOG" 'msg output eDP-1 on'
  assert_file_contains "$NIRI_LOG" 'msg output eDP-1 mode 1920x1200@60.003'
  assert_file_contains "$NIRI_LOG" 'msg output eDP-1 scale 1.5'
  assert_file_contains "$NIRI_LOG" 'msg output eDP-1 transform 90'
  assert_file_contains "$NIRI_LOG" 'msg output eDP-1 position set 0 0'
  assert_file_contains "$NIRI_LOG" 'msg output eDP-1 vrr off'
  assert_file_contains "$NIRI_LOG" 'msg output HDMI-A-1 off'
  assert_file_contains "$NIRI_LOG" 'msg action load-config-file'
}

@test "preview confirmation countdown starts only after output application completes" {
  draft="$TEST_ROOT/draft.json"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1200@60.003","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$draft"

  run python3 - "$BACKEND" "$draft" "$TEST_ROOT/display.kdl" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys
import time

spec = importlib.util.spec_from_file_location("display_backend", sys.argv[1])
backend = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(backend)
backend.spawn_watchdog = lambda preview_id: None
backend.validate_persistent_config = lambda: None
backend.query_outputs = lambda: []

def delayed_apply(outputs):
    token = backend.read_preview_token()
    assert token is not None
    assert token["status"] == "applying"
    assert "expires" not in token
    time.sleep(1.1)

backend.apply_outputs = delayed_apply
result = backend.preview(Path(sys.argv[2]), Path(sys.argv[3]), 5)
token = backend.read_preview_token()
assert token is not None
assert token["status"] == "active"
assert token["expires"] == result["expires"]
assert result["expires"] >= int(time.time()) + 4
backend.cancel_preview(result["preview_id"])
print(json.dumps(result))
PY

  [ "$status" -eq 0 ]
  assert_contains "$output" '"timeout": 5'
}

@test "preview restores immediately when its confirmation state cannot be armed" {
  draft="$TEST_ROOT/draft.json"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1200@60.003","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$draft"

  run python3 - "$BACKEND" "$draft" "$TEST_ROOT/display.kdl" <<'PY'
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("display_backend", sys.argv[1])
backend = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(backend)
backend.spawn_watchdog = lambda preview_id: None
backend.validate_persistent_config = lambda: None
backend.query_outputs = lambda: []
backend.apply_outputs = lambda outputs: None
original_atomic_write = backend.atomic_write
reloads = []

def fail_active_state(path, content):
    if '"status":"active"' in content:
        raise OSError("simulated full runtime filesystem")
    original_atomic_write(path, content)

backend.atomic_write = fail_active_state
backend.reload_persistent_config = lambda: reloads.append(True)

try:
    backend.preview(Path(sys.argv[2]), Path(sys.argv[3]), 5)
except backend.BackendError as exc:
    assert "persistent display configuration was restored" in str(exc)
    assert exc.preview_id is not None
else:
    raise AssertionError("preview unexpectedly succeeded")

assert reloads == [True]
assert backend.read_preview_token() is None
PY

  [ "$status" -eq 0 ]
}

@test "failed aggregate validation restores the prior display file" {
  run python3 - "$BACKEND" "$TEST_ROOT" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys
import time

spec = importlib.util.spec_from_file_location("display_backend", sys.argv[1])
backend = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(backend)
root = Path(sys.argv[2])
draft = root / "draft.json"
config = root / "display.kdl"
draft.write_text(json.dumps({"outputs": [{
    "name": "eDP-1", "enabled": True, "mode": "1920x1200@60.003",
    "scale": 1, "transform": "normal", "x": 0, "y": 0,
    "vrr_supported": False, "vrr_enabled": False,
}]}))
original = 'output "eDP-1" {\n    scale 1.25\n}\n'
config.write_text(original)
preview_id = "validation-timeout"
backend.write_preview_token(preview_id, "active", expires=int(time.time()) + 30)
backend.validate_candidate = lambda path: None
backend.run_command = lambda args, timeout=8: (_ for _ in ()).throw(
    backend.BackendError("simulated aggregate validation timeout")
)

try:
    backend.keep(draft, config, preview_id)
except backend.BackendError as exc:
    assert "validation timeout" in str(exc)
else:
    raise AssertionError("keep unexpectedly succeeded")

assert config.read_text() == original
assert backend.read_preview_token()["id"] == preview_id
PY

  [ "$status" -eq 0 ]
}

@test "rollback watchdog retries reload before deleting its token" {
  run python3 - "$BACKEND" <<'PY'
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("display_backend", sys.argv[1])
backend = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(backend)
preview_id = "reload-retry"
backend.write_preview_token(preview_id, "active", expires=0)
attempts = 0

def reload():
    global attempts
    attempts += 1
    assert backend.read_preview_token()["id"] == preview_id
    if attempts == 1:
        raise backend.BackendError("simulated reload failure")

backend.reload_persistent_config = reload
backend.time.sleep = lambda delay: None
backend.watchdog(preview_id)
assert attempts == 2
assert backend.read_preview_token() is None
PY

  [ "$status" -eq 0 ]
}

@test "failed partial preview leaves rollback pending when reload fails" {
  draft="$TEST_ROOT/draft.json"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1200@60.003","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$draft"

  run python3 - "$BACKEND" "$draft" "$TEST_ROOT/display.kdl" <<'PY'
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("display_backend", sys.argv[1])
backend = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(backend)
backend.spawn_watchdog = lambda preview_id: None
backend.validate_persistent_config = lambda: None
backend.query_outputs = lambda: []
backend.apply_outputs = lambda outputs: (_ for _ in ()).throw(backend.BackendError("apply failed"))
backend.reload_persistent_config = lambda: (_ for _ in ()).throw(backend.BackendError("reload failed"))

try:
    backend.preview(Path(sys.argv[2]), Path(sys.argv[3]), 5)
except backend.BackendError as exc:
    assert "still pending" in str(exc)
else:
    raise AssertionError("preview unexpectedly succeeded")

token = backend.read_preview_token()
assert token is not None
assert token["status"] == "rollback"
backend.cancel_preview(token["id"])
PY

  [ "$status" -eq 0 ]
}

@test "preview refuses to convert an existing Niri modeline" {
  draft="$TEST_ROOT/draft.json"
  target="$TEST_ROOT/display.kdl"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1080@100.000","custom_mode":true,"scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$draft"
  printf 'output "eDP-1" {\n    modeline 173.00 1920 2048 2248 2576 1080 1083 1088 1120 "-hsync" "+vsync"\n}\n' >"$target"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$target" --timeout 5

  [ "$status" -ne 0 ]
  assert_contains "$output" 'Niri IPC cannot expose its timings'
  [[ ! -e "$NIRI_LOG" ]]
}

@test "preview refuses output settings that cannot be round-tripped" {
  draft="$TEST_ROOT/draft.json"
  target="$TEST_ROOT/display.kdl"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1200@60.003","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":true,"vrr_enabled":false}]}' >"$draft"
  printf 'output "eDP-1" {\n    variable-refresh-rate on-demand=true\n}\n' >"$target"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$target" --timeout 5

  [ "$status" -ne 0 ]
  assert_contains "$output" 'cannot round-trip that setting'
  [[ ! -e "$NIRI_LOG" ]]

  printf 'output "eDP-1" {\n    max-bpc 10\n}\n' >"$target"
  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$target" --timeout 5

  [ "$status" -ne 0 ]
  assert_contains "$output" "unsupported output setting 'max-bpc'"
  [[ ! -e "$NIRI_LOG" ]]
}

@test "preview preserves saved settings for disconnected and disabled outputs" {
  draft="$TEST_ROOT/draft.json"
  target="$TEST_ROOT/display.kdl"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1200@60.003","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$draft"
  printf 'output "HDMI-A-1" {\n    mode "2560x1440@60.000"\n}\n' >"$target"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$target" --timeout 5

  [ "$status" -ne 0 ]
  assert_contains "$output" 'not currently connected'
  [[ ! -e "$NIRI_LOG" ]]

  printf 'output "eDP-1" {\n    off\n    mode "1920x1200@60.003"\n}\n' >"$target"
  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$target" --timeout 5

  [ "$status" -ne 0 ]
  assert_contains "$output" 'inactive values'
  [[ ! -e "$NIRI_LOG" ]]
}

@test "preview preserves settings for an output temporarily disabled through IPC" {
  draft="$TEST_ROOT/draft.json"
  target="$TEST_ROOT/display.kdl"
  printf '%s\n' '{"outputs":[{"name":"DP-2","enabled":false,"mode":"1920x1080@60.000","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false},{"name":"HDMI-A-1","enabled":true,"mode":"2560x1440@143.912","scale":1.5,"transform":"normal","x":1920,"y":0,"vrr_supported":true,"vrr_enabled":true}]}' >"$draft"
  printf 'output "DP-2" {\n    mode "1920x1080@60.000"\n    scale 1.25\n}\n' >"$target"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$target" --timeout 5

  [ "$status" -ne 0 ]
  assert_contains "$output" 'retains settings for an output that is currently disabled'
  assert_file_contains "$target" 'scale 1.25'
  ! grep -q '^msg output ' "$NIRI_LOG"
}

@test "preview can intentionally disable an output that is currently active" {
  draft="$TEST_ROOT/draft.json"
  target="$TEST_ROOT/display.kdl"
  printf '%s\n' '{"outputs":[{"name":"DP-2","enabled":true,"mode":"1920x1080@60.000","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false},{"name":"HDMI-A-1","enabled":false,"mode":"2560x1440@143.912","scale":1.5,"transform":"normal","x":1920,"y":0,"vrr_supported":true,"vrr_enabled":true}]}' >"$draft"
  printf 'output "HDMI-A-1" {\n    mode "2560x1440@143.912"\n    scale 1.5\n}\n' >"$target"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$target" --timeout 5

  [ "$status" -eq 0 ]
  preview_id="$(python3 -c 'import json, sys; print(json.loads(sys.argv[1])["preview_id"])' "$output")"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" revert --preview-id "$preview_id"
  [ "$status" -eq 0 ]
  assert_file_contains "$NIRI_LOG" 'msg output HDMI-A-1 off'
}

@test "panel retains its preview draft when reopened" {
  run python3 - "$PLUGIN_DIR/panel.luau" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
on_open = source[source.index("function onOpen(context)"):source.index("function onClose()")]
assert 'queryOutputs("Edit a display, then use Preview to test it safely", "Loading connected displays…")' in on_open
assert 'restorePreview("Preview timed out and the persistent display configuration was restored")' in source
assert source.count("syncPreviewState(previewState)") == 3
PY

  [ "$status" -eq 0 ]
}

@test "panel enables draft actions only for semantic output changes" {
  panel_source="$PLUGIN_DIR/panel.luau"

  assert_file_contains "$panel_source" 'local baselineOutputs = nil'
  assert_file_contains "$panel_source" 'local function draftHasChanges()'
  assert_file_contains "$panel_source" 'enabled = not busy and not previewActive and draftChanged'
  assert_file_contains "$panel_source" 'enabled = not busy and previewActive and previewStatus == "active" and draftChanged'
  assert_file_contains "$panel_source" 'enabled = not busy and not previewActive and not draftChanged'
  assert_file_contains "$panel_source" 'if busy or not draft or not draftHasChanges() then'
  assert_file_contains "$panel_source" 'baselineOutputs = clone(draft.outputs)'
}

@test "keep rejects an expired preview without writing display config" {
  draft="$TEST_ROOT/draft.json"
  target="$TEST_ROOT/config/niri/cfg/display.kdl"
  mkdir -p "$(dirname "$target")"
  printf 'original display config\n' >"$target"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":true,"mode":"1920x1200@60.003","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$draft"

  preview_id="expired-preview"
  token="$XDG_RUNTIME_DIR/noctalia-display-settings-$(id -u)/preview.json"
  mkdir -p "$(dirname "$token")"
  python3 - "$token" "$preview_id" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
path.write_text('{"id":"' + sys.argv[2] + '","status":"active","started":0,"expires":0}')
PY

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" keep --draft "$draft" --config "$target" --preview-id "$preview_id"

  [ "$status" -ne 0 ]
  assert_contains "$output" 'preview expired'
  python3 - "$output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["preview"] == {"active": False, "status": "inactive"}
PY
  assert_file_contains "$target" 'original display config'
  [[ ! -e "$target.previous" ]]
}

@test "revert retains active preview state when Niri rejects the config reload" {
  preview_id="rejected-reload"
  token="$XDG_RUNTIME_DIR/noctalia-display-settings-$(id -u)/preview.json"
  mkdir -p "$(dirname "$token")"
  python3 - "$token" "$preview_id" <<'PY'
from pathlib import Path
import sys
import time

Path(sys.argv[1]).write_text(
    '{"id":"' + sys.argv[2] + '","status":"active","started":0,"expires":' + str(int(time.time()) + 30) + '}'
)
PY

  run env PATH="$FAKE_BIN:$PATH" NIRI_CONFIG_LOAD_FAILED=true python3 "$BACKEND" revert --preview-id "$preview_id"

  [ "$status" -ne 0 ]
  assert_contains "$output" 'Niri rejected the persistent configuration during reload'
  python3 - "$output" "$token" <<'PY'
import json
from pathlib import Path
import sys

payload = json.loads(sys.argv[1])
assert payload["preview"]["active"] is True
assert payload["preview"]["id"] == "rejected-reload"
assert payload["preview"]["status"] == "rollback"
assert Path(sys.argv[2]).exists()
PY
}

@test "backend refuses to disable every connected output" {
  draft="$TEST_ROOT/all-disabled.json"
  printf '%s\n' '{"outputs":[{"name":"eDP-1","enabled":false,"mode":"1920x1200@60.003","scale":1,"transform":"normal","x":0,"y":0,"vrr_supported":false,"vrr_enabled":false}]}' >"$draft"

  run env PATH="$FAKE_BIN:$PATH" python3 "$BACKEND" preview --draft "$draft" --config "$TEST_ROOT/display.kdl" --timeout 5

  [ "$status" -ne 0 ]
  assert_contains "$output" 'at least one output must remain enabled'
  [[ ! -e "$NIRI_LOG" ]]
}
