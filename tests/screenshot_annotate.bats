#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

HELPER="$BATS_TEST_DIRNAME/../dotfiles/screenshot-tools/.local/bin/zz-screenshot-annotate"

setup() {
  setup_test_env
  setup_fake_bin
  RUNTIME_DIR="$TEST_ROOT/runtime"
  mkdir -p "$RUNTIME_DIR"
  # satty logs its arguments and whether the capture it was handed is readable.
  write_fake_command satty <<EOF
#!/usr/bin/env bash
printf 'satty %s\n' "\$*" >>"$COMMAND_LOG"
[[ "\$1" == --filename && -s "\$2" ]] && printf 'capture readable\n' >>"$COMMAND_LOG"
exit 0
EOF
}

# fake_focused_output <width> <height> <scale> makes niri report the focused
# output's logical size.
fake_focused_output() {
  write_fake_command niri <<EOF
#!/usr/bin/env bash
[[ "\$*" == "msg -j focused-output" ]] || exit 1
printf '{"name":"DP-1","logical":{"x":0,"y":0,"width":%s,"height":%s,"scale":%s,"transform":"Normal"}}\n' $1 $2 $3
EOF
}

be32() {
  printf "\\x$(printf %02x $((($1 >> 24) & 255)))\\x$(printf %02x $((($1 >> 16) & 255)))"
  printf "\\x$(printf %02x $((($1 >> 8) & 255)))\\x$(printf %02x $(($1 & 255)))"
}

# png_header <width> <height> prints the PNG signature and IHDR chunk.
png_header() {
  printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR'
  be32 "$1"
  be32 "$2"
  printf '\x08\x06\x00\x00\x00'
}

run_helper() {
  run env PATH="$FAKE_BIN:$PATH" XDG_RUNTIME_DIR="$RUNTIME_DIR" "$HELPER" "$@"
}

@test "a full-output capture opens scaled to fit the focused output with room for the toolbars" {
  fake_focused_output 3072 1728 1.25
  png_header 3840 2160 >"$TEST_ROOT/capture.png"

  run_helper <"$TEST_ROOT/capture.png"

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "--resize 2601x1555"
  assert_file_contains "$COMMAND_LOG" "capture readable"
}

@test "a small region opens at its on-screen size plus the toolbars" {
  fake_focused_output 3072 1728 1.25
  png_header 400 240 >"$TEST_ROOT/capture.png"

  run_helper <"$TEST_ROOT/capture.png"

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "--resize 320x284"
}

@test "a tall capture is bounded by the output height" {
  fake_focused_output 2560 1440 1
  png_header 1080 2400 >"$TEST_ROOT/capture.png"

  run_helper <"$TEST_ROOT/capture.png"

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "--resize 541x1296"
}

@test "extra arguments reach satty and the capture copy is removed afterwards" {
  fake_focused_output 2560 1440 1
  png_header 800 600 >"$TEST_ROOT/capture.png"

  run_helper --initial-tool text <"$TEST_ROOT/capture.png"

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "--resize 800x692 --initial-tool text"
  [ -z "$(ls -A "$RUNTIME_DIR")" ]
}

@test "a cancelled selection opens no editor" {
  fake_focused_output 2560 1440 1

  run_helper </dev/null

  [ "$status" -eq 0 ]
  [ ! -e "$COMMAND_LOG" ]
  [ -z "$(ls -A "$RUNTIME_DIR")" ]
}

@test "the editor still opens when the output size is unavailable" {
  make_fake_command niri 1
  png_header 800 600 >"$TEST_ROOT/capture.png"

  run_helper <"$TEST_ROOT/capture.png"

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "capture readable"
  refute_file_contains "$COMMAND_LOG" "--resize"
}

@test "the DMS seed drops niri's own screenshot notification so satty's is the only one" {
  local seed="$BATS_TEST_DIRNAME/../templates/dms/settings-seed.json"

  run jq -e '[.notificationRules[]
    | select(.enabled and .action == "ignore"
      and .field == "appName" and .matchType == "exact" and .pattern == "niri"
      and (.conditions | any(.field == "summary" and .matchType == "exact" and .pattern == "Screenshot captured")))]
    | length == 1' "$seed"

  [ "$status" -eq 0 ]
}

@test "a size or fullscreen option given to the helper replaces its computed size" {
  fake_focused_output 2560 1440 1
  png_header 800 600 >"$TEST_ROOT/capture.png"

  run_helper --resize smart <"$TEST_ROOT/capture.png"
  [ "$status" -eq 0 ]
  run_helper --fullscreen=current-screen <"$TEST_ROOT/capture.png"
  [ "$status" -eq 0 ]

  [ "$(grep -c -- '--resize' "$COMMAND_LOG")" -eq 1 ]
  assert_file_contains "$COMMAND_LOG" "--resize smart"
  assert_file_contains "$COMMAND_LOG" "--fullscreen=current-screen"
}

@test "an output too small for the toolbars keeps satty's own sizing" {
  fake_focused_output 200 100 1
  png_header 800 600 >"$TEST_ROOT/capture.png"

  run_helper <"$TEST_ROOT/capture.png"

  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "capture readable"
  refute_file_contains "$COMMAND_LOG" "--resize"
}

@test "the screenshot keybinds' helper is an executable managed link" {
  [ -x "$BATS_TEST_DIRNAME/../dotfiles/screenshot-tools/.local/bin/zz-screenshot-annotate" ]
  awk -F'\t' '$1 == "screenshot-tools" && $2 == "~/.local/bin/zz-screenshot-annotate" &&
    $3 == "product-link" && $5 == "dotfiles/screenshot-tools/.local/bin/zz-screenshot-annotate" {found = 1}
    END {exit !found}' "$BATS_TEST_DIRNAME/../config/managed-config.tsv"
}
