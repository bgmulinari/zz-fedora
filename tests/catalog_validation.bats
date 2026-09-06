#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
}

@test "catalog validation rejects control characters in unit strings" {
  local sandbox="$TEST_ROOT/control-character-root"
  mkdir -p "$sandbox"
  cp -R "$ROOT_DIR/catalog" "$sandbox/catalog"
  printf 'id = "dev-zz-control"\ndescription = "Sandbox unit with a carriage\\r return"\n\n[[install]]\nbackend = "dnf"\npackages = ["zz-control-package"]\n' \
    >"$sandbox/catalog/units/dev/zz-control.toml"

  run /usr/bin/python3 "$ROOT_DIR/lib/catalog.py" --root "$sandbox" validate
  [ "$status" -ne 0 ]
  assert_contains "$output" "zz-control.toml"
  assert_contains "$output" "'description' must not contain control characters"
}
