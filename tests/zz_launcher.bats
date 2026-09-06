#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
}

@test "zz commands --json escapes control characters in command metadata" {
  local root="$TEST_ROOT/launcher-root"
  mkdir -p "$root/bin/zz.d"
  cp "$ROOT_DIR/bin/zz" "$root/bin/zz"
  chmod +x "$root/bin/zz"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# zz-name: probe\n'
    printf '# zz-summary: control\001char\ttab\rreturn\177del back\\slash "quote"\n'
    printf '# zz-usage: zz probe\n'
    printf 'exit 0\n'
  } >"$root/bin/zz.d/probe"
  chmod +x "$root/bin/zz.d/probe"

  run bash "$root/bin/zz" commands --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | /usr/bin/python3 -c '
import json, sys
commands = json.loads(sys.stdin.read())
assert len(commands) == 1, commands
probe = commands[0]
assert probe["name"] == "probe", probe
assert probe["summary"] == "control\x01char\ttab\rreturn\x7fdel back\\slash \"quote\"", repr(probe["summary"])
assert probe["usage"] == "zz probe", probe
'
}
