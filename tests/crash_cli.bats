#!/usr/bin/env bats

load "helpers/common"

WATCH_UNIT_REL="dotfiles/crash-watch/.config/systemd/user/zz-crash-watch.service"
SKILL_REL="dotfiles/agent-skills/.agents/skills/diagnose-crash"

setup() {
  setup_test_env
  source_core
  setup_fake_bin
  export COMMAND_LOG
  export HOME="$TARGET_HOME"
  export HOMEBREW_PREFIX="$TEST_ROOT/brew"
  export FAKE_STATE="$TEST_ROOT/fake-state"
  export JOURNAL_ENTRIES="$FAKE_STATE/journal"
  STATE_DIR="$XDG_STATE_HOME/zz-fedora"
  MUTE_DIR="$STATE_DIR/crash-ignore"
  CAPTURE_OFF_FLAG="$STATE_DIR/crash-capture-off"
  mkdir -p "$HOMEBREW_PREFIX/bin" "$FAKE_STATE" "$XDG_CONFIG_HOME/zz-fedora"
  : >"$JOURNAL_ENTRIES"
  printf 'claude\n' >"$XDG_CONFIG_HOME/zz-fedora/agent"
  write_fakes
}

# journalctl replays the stubbed entries and ends, so the watcher's loop ends
# with it; notify-send prints the action's name when FAKE_NOTIFY_CLICK is set,
# the way libnotify does for a click; coredumpctl lists the stubbed cores.
write_fakes() {
  make_fake_command claude
  make_fake_command busctl
  make_fake_command systemctl
  make_fake_command xdg-terminal-exec
  write_fake_command journalctl <<'EOS'
#!/usr/bin/env bash
cat "$JOURNAL_ENTRIES"
EOS
  write_fake_command notify-send <<EOS
#!/usr/bin/env bash
printf 'notify-send %s\\n' "\$*" >>"$COMMAND_LOG"
[[ -n "\${FAKE_NOTIFY_CLICK:-}" ]] || exit 0
for arg in "\$@"; do
  [[ "\$arg" == --action=* ]] || continue
  name="\${arg#--action=}"
  printf '%s\\n' "\${name%%=*}"
  exit 0
done
EOS
  write_fake_command coredumpctl <<EOS
#!/usr/bin/env bash
printf 'coredumpctl %s\\n' "\$*" >>"$COMMAND_LOG"
[[ "\$1" == "list" ]] || exit 0
[[ -s "$FAKE_STATE/coredumps" ]] || { echo "No coredumps found." >&2; exit 1; }
for arg in "\$@"; do
  if [[ "\$arg" =~ ^[0-9]+\$ ]]; then
    awk -v pid="\$arg" '\$5 == pid' "$FAKE_STATE/coredumps"
    exit 0
  fi
done
cat "$FAKE_STATE/coredumps"
EOS
}

zz_crash() {
  PATH="$FAKE_BIN:/usr/bin:/bin" run bash "$ROOT_DIR/bin/zz" crash "$@"
}

# One core dump as systemd-coredump journals it. The UID must be this user's,
# or the watcher discards it as somebody else's crash before anything under
# test.
crash_entry() {
  local comm="$1" exe="$2" uid="${3:-$UID}" pid="${4:-4242}"
  jq -cn --arg uid "$uid" --arg comm "$comm" --arg exe "$exe" --arg pid "$pid" \
    '{_UID: $uid, COREDUMP_COMM: $comm, COREDUMP_PID: $pid,
      COREDUMP_EXE: $exe, COREDUMP_SIGNAL_NAME: "SIGSEGV"}' >>"$JOURNAL_ENTRIES"
}

# The watcher's exit status matters: one that dies on a muted crash notifies
# about nothing afterwards, which every assertion expecting silence would
# otherwise read as success.
run_watch() {
  : >"$COMMAND_LOG"
  zz_crash watch
  [ "$status" -eq 0 ]
}

announced() {
  grep -F "notify-send" "$COMMAND_LOG" | grep -F -- "$1 crashed" >/dev/null
}

stub_coredumps() {
  cat >"$FAKE_STATE/coredumps" <<'EOS'
Sun 2026-09-06 01:41:36 -03 2885516 1000 1000 SIGSYS  present /usr/bin/bwrap    40.8K
Sun 2026-09-13 23:55:46 -03    4242 1000 1000 SIGSEGV present /usr/bin/nautilus  2.2M
EOS
}

@test "zz crash exposes its commands" {
  run bash "$ROOT_DIR/bin/zz" crash --help
  [ "$status" -eq 0 ]
  for word in list diagnose mute capture watch; do
    assert_contains "$output" "  $word"
  done

  zz_crash bogus
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown zz crash command: bogus"

  run bash "$ROOT_DIR/bin/zz" commands --json
  assert_contains "$output" '"name":"crash"'
}

@test "a crash of this user's program is announced once with a diagnose action" {
  crash_entry nautilus /usr/bin/nautilus
  run_watch
  announced Nautilus
  assert_file_contains "$COMMAND_LOG" "--urgency=critical"
  assert_file_contains "$COMMAND_LOG" "--action=diagnose=Diagnose with AI"
  assert_file_contains "$COMMAND_LOG" "Nautilus crashed Click to diagnose with AI"
  # The server is checked before the toast: a shell crash takes it down.
  assert_file_contains "$COMMAND_LOG" "busctl --user call org.freedesktop.Notifications"

  # A crash loop is one toast per window, other programs still speak.
  crash_entry nautilus /usr/bin/nautilus "$UID" 4243
  crash_entry foot /usr/bin/foot "$UID" 4244
  run_watch
  assert_equal 1 "$(grep -c "Nautilus crashed" "$COMMAND_LOG")"
  announced Foot
}

@test "the watcher keys on the binary, survives empty fields, and skips other users' crashes" {
  # comm is truncated to 15 characters; the binary's basename is not.
  crash_entry "long-program-na" /usr/bin/long-program-name
  # A process can blank its own name; the fields after it must not shift.
  crash_entry "" ""
  # A daemon dumping core is not this user's problem.
  crash_entry nginx /usr/sbin/nginx 0 77
  run_watch
  announced Long-program-name
  announced Unknown
  ! announced Nginx
}

@test "a muted program, an ignored pattern, and a missing agent keep the watcher silent" {
  crash_entry nautilus /usr/bin/nautilus
  zz_crash mute /usr/bin/nautilus
  [ "$status" -eq 0 ]
  assert_contains "$output" "Muted crash notifications for nautilus"
  assert_contains "$output" "zz crash mute nautilus off"
  [[ -f "$MUTE_DIR/nautilus" ]]
  run_watch
  ! announced Nautilus

  zz_crash mute nautilus off
  assert_contains "$output" "Crash notifications for nautilus are back on"
  [[ ! -e "$MUTE_DIR/nautilus" ]]
  run_watch
  announced Nautilus

  export ZZ_CRASH_IGNORE='^naut'
  run_watch
  ! announced Nautilus
  unset ZZ_CRASH_IGNORE

  # Nothing to offer until a default agent is chosen.
  rm "$XDG_CONFIG_HOME/zz-fedora/agent"
  run_watch
  ! announced Nautilus
}

@test "zz crash mute lists, toggles, and keeps a hostile name inside the flag directory" {
  zz_crash mute
  assert_contains "$output" "No programs muted"

  zz_crash mute nautilus
  zz_crash mute -- -h
  [ "$status" -eq 0 ]
  [[ -f "$MUTE_DIR/-h" ]]
  zz_crash mute
  assert_equal $'-h\nnautilus' "$(printf '%s\n' "$output" | sort)"

  zz_crash mute nautilus toggle
  assert_contains "$output" "back on"
  zz_crash mute nautilus toggle
  assert_contains "$output" "Muted"

  zz_crash mute nautilus sideways
  [ "$status" -ne 0 ]
  assert_contains "$output" "Not an action: sideways"

  zz_crash mute /
  [ "$status" -ne 0 ]
  assert_contains "$output" "Not a program name"
  zz_crash mute ..
  [ "$status" -ne 0 ]
  zz_crash mute "../escape"
  [ "$status" -eq 0 ]
  [[ -f "$MUTE_DIR/escape" ]]
  [[ ! -e "$STATE_DIR/escape" ]]
}

@test "clicking the notification hands the crash facts to the default agent" {
  export FAKE_NOTIFY_CLICK=1
  crash_entry nautilus /usr/bin/nautilus
  stub_coredumps
  run_watch

  # The click runs in the background so the journal keeps being read.
  local attempts=50
  until grep -q "xdg-terminal-exec" "$COMMAND_LOG" || [[ "$attempts" -eq 0 ]]; do
    sleep 0.1
    attempts=$((attempts - 1))
  done
  assert_file_contains "$COMMAND_LOG" "xdg-terminal-exec --app-id=zz-agent --title=ZZ agent -- $FAKE_BIN/claude --permission-mode auto -- A process crashed on this ZZ Fedora desktop"
  assert_file_contains "$COMMAND_LOG" "process:  nautilus"
  assert_file_contains "$COMMAND_LOG" "PID:      4242"
  assert_file_contains "$COMMAND_LOG" "binary:   /usr/bin/nautilus"
  assert_file_contains "$COMMAND_LOG" "signal:   SIGSEGV"
  assert_file_contains "$COMMAND_LOG" "time:     Sun 2026-09-13 23:55:46 -03"
  assert_file_contains "$COMMAND_LOG" "Use the diagnose-crash skill"
  assert_file_contains "$COMMAND_LOG" "$ROOT_DIR/$SKILL_REL/SKILL.md"
}

@test "zz crash diagnose fills the facts in from coredumpctl for a PID or the latest core" {
  stub_coredumps
  zz_crash diagnose 4242 --inline
  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "claude --permission-mode auto -- A process crashed"
  assert_file_contains "$COMMAND_LOG" "process:  nautilus"
  assert_file_contains "$COMMAND_LOG" "binary:   /usr/bin/nautilus"
  assert_file_contains "$COMMAND_LOG" "signal:   SIGSEGV"
  assert_file_contains "$COMMAND_LOG" "time:     Sun 2026-09-13 23:55:46 -03"

  : >"$COMMAND_LOG"
  zz_crash diagnose latest --inline
  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "PID:      4242"

  zz_crash diagnose
  [ "$status" -ne 0 ]
  assert_contains "$output" "Usage: zz crash diagnose <pid|latest>"
  zz_crash diagnose nautilus
  [ "$status" -ne 0 ]
  assert_contains "$output" "Not a PID: nautilus"

  : >"$FAKE_STATE/coredumps"
  zz_crash diagnose latest --inline
  [ "$status" -ne 0 ]
  assert_contains "$output" "No core dumps recorded"
}

@test "zz crash capture flags the watcher off across logins and back on" {
  zz_crash capture
  [ "$status" -eq 0 ]
  assert_contains "$output" "Crash capture is on"

  zz_crash capture off
  [ "$status" -eq 0 ]
  assert_contains "$output" "Crash capture is off"
  [[ -f "$CAPTURE_OFF_FLAG" ]]
  assert_file_contains "$COMMAND_LOG" "systemctl --user stop zz-crash-watch.service"
  assert_file_contains "$COMMAND_LOG" "Crash capture disabled"

  : >"$COMMAND_LOG"
  zz_crash capture toggle
  assert_contains "$output" "Crash capture is on"
  [[ ! -e "$CAPTURE_OFF_FLAG" ]]
  assert_file_contains "$COMMAND_LOG" "systemctl --user start zz-crash-watch.service"
  assert_file_contains "$COMMAND_LOG" "Crash capture enabled"

  zz_crash capture sideways
  [ "$status" -ne 0 ]

  # The unit reads the same flag, so a login after `off` stays quiet without
  # the unit being disabled, and it runs the watcher through the launcher.
  local unit="$ROOT_DIR/$WATCH_UNIT_REL"
  assert_file_line "$unit" 'ConditionPathExists=!%h/.local/state/zz-fedora/crash-capture-off'
  assert_file_line "$unit" 'ExecStart=%h/.local/bin/zz crash watch'
  assert_file_line "$unit" 'WantedBy=graphical-session.target'
}

@test "the crash diagnosis choice plans the watcher unit, its packages, and is a default" {
  build_test_plan "ai=crash-diagnosis"

  assert_plan_has "$PLAN_DIR/bundles.list" "ai-crash-diagnosis"
  assert_plan_has "$PLAN_DIR/config/components.list" "crash-watch"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.config/systemd/user/zz-crash-watch.service"
  assert_plan_has "$PLAN_DIR/services/user-enable.list" "zz-crash-watch.service"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "libnotify"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "gdb"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "elfutils-debuginfod-client"

  run default_choice_ids ai
  [ "$status" -eq 0 ]
  assert_contains "$output" "crash-diagnosis"
}

@test "the diagnose-crash skill ships with the base plan and points at zz crash" {
  build_test_plan
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.claude/skills/diagnose-crash"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "~/.agents/skills/diagnose-crash"
  assert_file_contains "$ROOT_DIR/$SKILL_REL/SKILL.md" "zz crash mute"
  assert_file_contains "$ROOT_DIR/$SKILL_REL/SKILL.md" "debuginfod.fedoraproject.org"
  # Personal assistance: the outcome is cause, remedy, and an offer to fix,
  # never a bug report filed on the user's behalf.
  assert_file_contains "$ROOT_DIR/$SKILL_REL/SKILL.md" "## Offer to address it"
  assert_file_contains "$ROOT_DIR/$SKILL_REL/SKILL.md" "Do not file issues"
  [[ ! -e "$ROOT_DIR/$SKILL_REL/reporting.md" ]]
  refute_file_contains "$ROOT_DIR/$SKILL_REL/SKILL.md" "gh issue"
}
