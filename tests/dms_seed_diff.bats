#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

# Build a throwaway root/home pair so the comparison never reads or writes the
# repository's own seed or the developer's live DMS state.
seed_diff_fixture() {
  FIX="$TEST_ROOT/seed-diff"
  mkdir -p "$FIX/root/templates/dms" \
    "$FIX/home/.config/DankMaterialShell" \
    "$FIX/home/.local/state/DankMaterialShell"
  cp "$ROOT_DIR/templates/dms/settings-seed.json" \
    "$ROOT_DIR/templates/dms/session-seed.json" "$FIX/root/templates/dms/"
  SPEC_DIR="$FIX/spec"
  mkdir -p "$SPEC_DIR"
  cat >"$SPEC_DIR/SettingsSpec.js" <<'SPEC'
.pragma library
function percentToUnit(v) { return v; }
var SPEC = {
    cornerRadius: { def: 16, onChange: "updateCompositorLayout" },
    popupTransparency: { def: 1.0, coerce: percentToUnit },
    greeterAutoLogin: { def: false },
    availableIconThemes: { def: ["System Default"], persist: false },
    barConfigs: { def: [{ id: "default", fontScale: 1, autoHide: false }] },
    workspaceNameIcons: { def: {} },
    niriOutputSettings: { def: {} }
};
SPEC
  cat >"$SPEC_DIR/SessionSpec.js" <<'SPEC'
.pragma library
var SPEC = {
    isLightMode: { def: false },
    pinnedApps: { def: [] },
    weatherCoordinates: { def: "40.7128,-74.0060" }
};
SPEC
}

seed_diff() {
  "$SYSTEM_PYTHON" "$ROOT_DIR/lib/dms_seed_diff.py" \
    --root "$FIX/root" --home "$FIX/home" --spec-dir "$SPEC_DIR" \
    --derived "${DERIVED_FACTS:-{\}}" "$@"
}

# DMS always writes every key it knows, so a realistic live file is the seed
# with the test's overrides layered on top. Passing only the overrides would
# make every unmentioned seeded key look absent.
write_live() {
  local settings_override="$1" session_override="${2:-{\}}"
  jq -s '.[0] * .[1]' "$FIX/root/templates/dms/settings-seed.json" \
    <(printf '%s' "$settings_override") \
    >"$FIX/home/.config/DankMaterialShell/settings.json"
  jq -s '.[0] * .[1]' "$FIX/root/templates/dms/session-seed.json" \
    <(printf '%s' "$session_override") \
    >"$FIX/home/.local/state/DankMaterialShell/session.json"
}

@test "the spec parser reads the literal subset the DMS specs use" {
  "$SYSTEM_PYTHON" - "$ROOT_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/lib")
from dms_spec import parse_spec, defaults
spec = parse_spec('''
var SPEC = {
    a: { def: 1 },
    b: { def: "x" },
    c: { def: { nested: [1, 2, {deep: true}] } },
    d: { def: [], coerce: someFunction },
    e: { def: 0, persist: false }
};
''')
got = defaults(spec)
assert got == {"a": 1, "b": "x", "c": {"nested": [1, 2, {"deep": True}]}, "d": []}, got
PY
}

@test "a live state matching the seed reports no differences" {
  seed_diff_fixture
  # Every seeded key at its seeded value, plus derived and excluded keys.
  "$SYSTEM_PYTHON" - "$FIX" <<'PY'
import json, pathlib, sys
fix = pathlib.Path(sys.argv[1])
seed = json.loads((fix / "root/templates/dms/settings-seed.json").read_text())
live = dict(seed)
live.update({
    "customThemeFile": "/home/someone/theme.json",
    "iconThemeDark": "Yaru-blue",
    "niriOutputSettings": {"eDP-1": {"mode": "1920x1200"}},
    "configVersion": 13,
})
(fix / "home/.config/DankMaterialShell/settings.json").write_text(json.dumps(live))
session_seed = json.loads((fix / "root/templates/dms/session-seed.json").read_text())
session = dict(session_seed)
session["weatherCoordinates"] = "-25.58,-49.40"
session["wallpaperPath"] = "/home/someone/wall.jpg"
(fix / "home/.local/state/DankMaterialShell/session.json").write_text(json.dumps(session))
PY
  run seed_diff
  [ "$status" -eq 0 ]
  assert_contains "$output" "matches the seeded defaults"
}

@test "host-specific and runtime keys are never promotable" {
  seed_diff_fixture
  write_live '{"niriOutputSettings":{"eDP-1":{"scale":2}},"configVersion":99,"customThemeFile":"/somewhere/else.json"}' \
    '{"weatherCoordinates":"-25.58,-49.40","launcherQueryHistory":["a","b"]}'
  run seed_diff
  [ "$status" -eq 0 ]
  assert_contains "$output" "matches the seeded defaults"
}

@test "a changed seeded key is reported and promoted by name" {
  seed_diff_fixture
  write_live '{"cornerRadius": 8}'
  run seed_diff
  [ "$status" -ne 0 ]
  assert_contains "$output" "cornerRadius"

  run seed_diff --apply cornerRadius
  [ "$status" -eq 0 ]
  assert_equal "8" "$(jq -r '.cornerRadius' "$FIX/root/templates/dms/settings-seed.json")"

  run seed_diff
  [ "$status" -eq 0 ]
}

@test "an unseeded key is reported only once it leaves the DMS default" {
  seed_diff_fixture
  write_live '{"greeterAutoLogin": false}'
  run seed_diff
  [ "$status" -eq 0 ]

  write_live '{"greeterAutoLogin": true}'
  run seed_diff
  [ "$status" -ne 0 ]
  assert_contains "$output" "greeterAutoLogin"
}

@test "structured settings compare and promote field by field" {
  seed_diff_fixture
  # A bar carrying DMS-backfilled fields the seed deliberately omits.
  write_live '{"barConfigs":[{"id":"default","fontScale":1.5,"autoHide":false,"spacing":0,"innerPadding":0,"transparency":0.8,"squareCorners":true,"noBackground":true,"name":"Main Bar","enabled":true,"leftWidgets":["launcherButton","workspaceSwitcher","focusedWindow"],"centerWidgets":["music","clock","weather"],"rightWidgets":["systemTray","clipboard","cpuUsage","memUsage","notificationButton","battery","controlCenterButton"]}]}'
  run seed_diff
  [ "$status" -ne 0 ]
  assert_contains "$output" "barConfigs[0].fontScale"
  # autoHide still matches the DMS default, so it is not a candidate.
  refute_contains "$output" "autoHide"

  run seed_diff --apply "barConfigs[0].fontScale"
  [ "$status" -eq 0 ]
  local seed="$FIX/root/templates/dms/settings-seed.json"
  assert_equal "1.5" "$(jq -r '.barConfigs[0].fontScale' "$seed")"
  # Promoting one field must not freeze the backfilled bar schema into the seed.
  assert_equal "null" "$(jq -r '.barConfigs[0].autoHide' "$seed")"
  assert_equal "0" "$(jq -r '.barConfigs[0].spacing' "$seed")"
}

@test "a setting whose DMS default is empty is still reported and promotable" {
  seed_diff_fixture
  # An empty-object default flattens to no paths at all, so comparing only
  # against flattened upstream values would drop this change silently.
  write_live '{"workspaceNameIcons":{"1":"term","2":"web"}}'
  run seed_diff
  [ "$status" -ne 0 ]
  assert_contains "$output" "workspaceNameIcons.1"
  assert_contains "$output" "the DMS default carries no such value"

  run seed_diff --apply "workspaceNameIcons.1"
  [ "$status" -eq 0 ]
  assert_equal "term" \
    "$(jq -r '.workspaceNameIcons["1"]' "$FIX/root/templates/dms/settings-seed.json")"
}

@test "a host-derived key is reported against its helper and never written to a seed" {
  seed_diff_fixture
  DERIVED_FACTS='{"settings":{"iconThemeDark":"Yaru-blue"},"session":{}}'
  write_live '{"iconThemeDark":"Papirus-Dark"}'
  run seed_diff
  [ "$status" -ne 0 ]
  assert_contains "$output" "iconThemeDark"
  assert_contains "$output" "dms_icon_theme() in lib/dms.sh"

  # --apply must not freeze a host fact into the seed file.
  run seed_diff --apply
  [ "$status" -eq 0 ]
  assert_equal "null" \
    "$(jq -r '.iconThemeDark' "$FIX/root/templates/dms/settings-seed.json")"
}

@test "a derived key matching its helper value is not reported" {
  seed_diff_fixture
  DERIVED_FACTS='{"settings":{"iconThemeDark":"Yaru-blue"},"session":{}}'
  write_live '{"iconThemeDark":"Yaru-blue"}'
  run seed_diff
  [ "$status" -eq 0 ]
}

@test "--json --apply keeps stdout a single parseable document" {
  seed_diff_fixture
  write_live '{"cornerRadius": 8}'
  # Apply progress belongs on stderr; anything on stdout would break jq.
  seed_diff --json --apply 2>/dev/null >"$FIX/report.json"
  run jq -e '.settings | length' "$FIX/report.json"
  [ "$status" -eq 0 ]
}

@test "reset restores the defaults onto the live state and backs it up" {
  seed_diff_fixture
  DERIVED_FACTS='{"settings":{"iconThemeDark":"Yaru-blue"},"session":{}}'
  # One pinned scalar, one unseeded key that drifted, one derived key, one key
  # whose DMS default is an empty container, and one key nobody reports.
  # Left at its seeded value, whatever that is, so it is never a difference.
  local seeded_popup
  seeded_popup="$(jq -r '.popupTransparency' "$FIX/root/templates/dms/settings-seed.json")"
  write_live '{"cornerRadius":12,"greeterAutoLogin":true,"iconThemeDark":"Papirus-Dark","workspaceNameIcons":{"1":"term"}}'
  local live="$FIX/home/.config/DankMaterialShell/settings.json"

  run seed_diff --reset
  [ "$status" -eq 0 ]

  assert_equal "0" "$(jq -r '.cornerRadius' "$live")"
  assert_equal "false" "$(jq -r '.greeterAutoLogin' "$live")"
  assert_equal "Yaru-blue" "$(jq -r '.iconThemeDark' "$live")"
  # No leaf to restore, so the whole key goes back to the empty default.
  assert_equal "{}" "$(jq -c '.workspaceNameIcons' "$live")"
  assert_equal "$seeded_popup" "$(jq -r '.popupTransparency' "$live")"

  # The previous contents are recoverable.
  local backup
  backup="$(find "$FIX/home/.config/DankMaterialShell" -name 'settings.json.bak.*' | head -1)"
  [ -n "$backup" ]
  assert_equal "12" "$(jq -r '.cornerRadius' "$backup")"

  run seed_diff
  [ "$status" -eq 0 ]
}

@test "reset leaves live keys the report does not mention alone" {
  seed_diff_fixture
  write_live '{"cornerRadius":12,"showSeconds":true,"barConfigs":[{"id":"default","fontScale":1.2,"autoHideDelay":400,"spacing":0,"innerPadding":0,"transparency":0.8,"squareCorners":true,"noBackground":true,"name":"Main Bar","enabled":true,"leftWidgets":["launcherButton","workspaceSwitcher","focusedWindow"],"centerWidgets":["music","clock","weather"],"rightWidgets":["systemTray","clipboard","cpuUsage","memUsage","notificationButton","battery","controlCenterButton"]}]}'
  local live="$FIX/home/.config/DankMaterialShell/settings.json"

  run seed_diff --reset cornerRadius
  [ "$status" -eq 0 ]

  assert_equal "0" "$(jq -r '.cornerRadius' "$live")"
  # Not named on the command line, and not described by the fixture spec.
  assert_equal "true" "$(jq -r '.showSeconds' "$live")"
  # A bar field the seed deliberately omits must survive a reset.
  assert_equal "400" "$(jq -r '.barConfigs[0].autoHideDelay' "$live")"
}

@test "reset never writes to the seed files" {
  seed_diff_fixture
  write_live '{"cornerRadius":12}'
  local seed="$FIX/root/templates/dms/settings-seed.json"
  local before
  before="$(cat "$seed")"

  run seed_diff --reset
  [ "$status" -eq 0 ]
  assert_equal "$before" "$(cat "$seed")"
}

@test "apply and reset cannot be combined" {
  seed_diff_fixture
  write_live '{"cornerRadius":12}'
  run seed_diff --apply --reset
  [ "$status" -ne 0 ]
  assert_contains "$output" "opposites"
}

@test "keybinds diff by bind rather than by file text" {
  seed_diff_fixture
  write_live '{}'
  local seed='{"binds":{"Execute":[{"key":"Mod+Return","action":"spawn ghostty"},{"key":"Mod+E","action":"spawn nautilus"}]}}'
  # Same binds, reordered and regrouped the way DMS rewrites the fragment.
  local same='{"binds":{"Other":[{"key":"Mod+E","action":"spawn nautilus"}],"Execute":[{"key":"Mod+Return","action":"spawn ghostty"}]}}'
  BINDS_PAYLOAD="$(jq -n --argjson a "$seed" --argjson b "$same" '{seed:$a,live:$b}')"
  run seed_diff --binds "$BINDS_PAYLOAD"
  [ "$status" -eq 0 ]

  local changed='{"binds":{"Execute":[{"key":"Mod+Return","action":"spawn kitty"},{"key":"Mod+E","action":"spawn nautilus"}]}}'
  BINDS_PAYLOAD="$(jq -n --argjson a "$seed" --argjson b "$changed" '{seed:$a,live:$b}')"
  run seed_diff --binds "$BINDS_PAYLOAD"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Mod+Return"
  assert_contains "$output" "bound to a different action"
}

@test "keybind added and removed binds are both reported" {
  seed_diff_fixture
  write_live '{}'
  local seed='{"binds":{"Execute":[{"key":"Mod+Return","action":"spawn ghostty"}]}}'
  local live='{"binds":{"Execute":[{"key":"Mod+G","action":"spawn gimp"}]}}'
  BINDS_PAYLOAD="$(jq -n --argjson a "$seed" --argjson b "$live" '{seed:$a,live:$b}')"
  run seed_diff --binds "$BINDS_PAYLOAD"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Mod+G"
  assert_contains "$output" "Mod+Return"
}

@test "promoting a keybind edits only that bind's line" {
  seed_diff_fixture
  cat >"$FIX/binds-seed.kdl" <<'KDL'
// managed header

binds {
    // Launchers
    Mod+Return hotkey-overlay-title="Open Terminal" { spawn "ghostty"; }
    Mod+E { spawn "nautilus"; }

    // Shell
    Mod+N { spawn-sh "dms ipc call notifications toggle"; }
}
KDL
  # DMS rewrites the live fragment: no comments, re-sorted, one bind changed.
  cat >"$FIX/binds-live.kdl" <<'KDL'
binds {
    Mod+E { spawn "nautilus"; }
    Mod+N hotkey-overlay-title="Launch netwatch" { spawn "ghostty" "-e" "netwatch"; }
    Mod+Return hotkey-overlay-title="Open Terminal" { spawn "ghostty"; }
}
KDL

  "$SYSTEM_PYTHON" - "$ROOT_DIR" "$FIX" <<'PY'
import pathlib, sys
sys.path.insert(0, sys.argv[1] + "/lib")
from dms_seed_diff import write_binds
fix = pathlib.Path(sys.argv[2])
write_binds(fix / "binds-live.kdl", fix / "binds-seed.kdl", ["Mod+N"])
PY

  # The one bind moved across.
  assert_file_contains "$FIX/binds-seed.kdl" 'Launch netwatch'
  # Everything that makes the seed readable survived.
  assert_file_contains "$FIX/binds-seed.kdl" '// managed header'
  assert_file_contains "$FIX/binds-seed.kdl" '// Launchers'
  assert_file_contains "$FIX/binds-seed.kdl" '// Shell'
  # The seed keeps its own order (Return, E, N) rather than adopting the
  # live file's alphabetical sort (E, N, Return).
  assert_equal "Mod+Return Mod+E Mod+N" \
    "$(grep -oE 'Mod\+[A-Za-z]+' "$FIX/binds-seed.kdl" | tr '\n' ' ' | sed 's/ $//')"
  assert_equal "3" "$(grep -c 'Mod+' "$FIX/binds-seed.kdl")"
}

@test "promoting a keybind can add and remove binds without reflowing the file" {
  seed_diff_fixture
  printf '// header\n\nbinds {\n    // group\n    Mod+A { spawn "a"; }\n    Mod+B { spawn "b"; }\n}\n' \
    >"$FIX/binds-seed.kdl"
  printf 'binds {\n    Mod+A { spawn "a"; }\n    Mod+C { spawn "c"; }\n}\n' \
    >"$FIX/binds-live.kdl"

  "$SYSTEM_PYTHON" - "$ROOT_DIR" "$FIX" <<'PY'
import pathlib, sys
sys.path.insert(0, sys.argv[1] + "/lib")
from dms_seed_diff import write_binds
fix = pathlib.Path(sys.argv[2])
write_binds(fix / "binds-live.kdl", fix / "binds-seed.kdl", ["Mod+B", "Mod+C"])
PY

  assert_file_contains "$FIX/binds-seed.kdl" '// group'
  assert_file_contains "$FIX/binds-seed.kdl" 'Mod+C'
  refute_file_contains "$FIX/binds-seed.kdl" 'Mod+B'
  assert_file_contains "$FIX/binds-seed.kdl" 'Mod+A'
}

@test "a missing DMS spec fails with an actionable message" {
  seed_diff_fixture
  write_live '{}'
  rm -f "$SPEC_DIR/SettingsSpec.js"
  run seed_diff
  [ "$status" -ne 0 ]
  assert_contains "$output" "missing DMS spec"
}
