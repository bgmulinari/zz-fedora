#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  setup_fake_bin
  export COMMAND_LOG
  export HOME="$TARGET_HOME"
  export HOMEBREW_PREFIX="$TEST_ROOT/brew"
  AGENT_FILE="$XDG_CONFIG_HOME/zz-fedora/agent"
  mkdir -p "$HOMEBREW_PREFIX/bin" "$(dirname "$AGENT_FILE")"
}

# The script searches ~/.local/bin, the caller's PATH, and the Homebrew
# prefix; the test owns all three so the machine's own agents stay out.
# The chosen agent lives in the config file, which each test writes itself.
zz_agent() {
  PATH="$FAKE_BIN:/usr/bin:/bin" run bash "$ROOT_DIR/bin/zz" agent "$@"
}

@test "zz agent exposes its commands" {
  run bash "$ROOT_DIR/bin/zz" agent --help
  [ "$status" -eq 0 ]
  assert_contains "$output" "zz agent prompt <text>"
  assert_contains "$output" "zz agent default"

  zz_agent bogus
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown zz agent command: bogus"

  run bash "$ROOT_DIR/bin/zz" commands --json
  [ "$status" -eq 0 ]
  assert_contains "$output" '"name":"agent"'
}

@test "no agent is the default until one is chosen" {
  zz_agent default
  [ "$status" -ne 0 ]
  assert_contains "$output" "No coding agent is installed"
  assert_contains "$output" "zz app install claude-code"

  make_fake_command claude
  make_fake_command codex
  zz_agent default
  [ "$status" -ne 0 ]
  assert_contains "$output" "No default coding agent chosen"
  assert_contains "$output" "zz agent default <claude|codex|opencode>"

  zz_agent run --inline
  [ "$status" -ne 0 ]
  assert_contains "$output" "No default coding agent chosen"
  [[ ! -s "$COMMAND_LOG" ]]

  make_fake_command opencode
  zz_agent default opencode
  [ "$status" -eq 0 ]
  assert_contains "$output" "Default coding agent: OpenCode (opencode)"
  assert_equal "opencode" "$(cat "$AGENT_FILE")"
  zz_agent default
  [ "$status" -eq 0 ]
  assert_equal "opencode" "$output"
}

@test "zz agent invite asks for the choice once and its click opens the picker" {
  make_fake_command dms
  make_fake_command busctl
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

  # Nothing to choose from while none of the agents is installed.
  zz_agent invite
  [ "$status" -eq 0 ]
  assert_contains "$output" "No coding agent is installed; nothing to choose"
  [[ ! -s "$COMMAND_LOG" ]]

  make_fake_command codex
  zz_agent invite
  [ "$status" -eq 0 ]
  assert_contains "$output" "Invited the default coding agent choice"
  local attempts=50
  until grep -q "notify-send" "$COMMAND_LOG" || [[ "$attempts" -eq 0 ]]; do
    sleep 0.1
    attempts=$((attempts - 1))
  done
  # The server is checked before the toast so a login-time send is not lost.
  assert_file_contains "$COMMAND_LOG" "busctl --user call org.freedesktop.Notifications"
  local attempts=50
  until grep -q "notify-send" "$COMMAND_LOG" || [[ "$attempts" -eq 0 ]]; do
    sleep 0.1
    attempts=$((attempts - 1))
  done
  assert_file_contains "$COMMAND_LOG" "--urgency=critical"
  assert_file_contains "$COMMAND_LOG" "--action=choose=Choose an agent Set your default coding agent"
  refute_file_contains "$COMMAND_LOG" "dms "

  # The click opens the ZZ menu at Setup > AI agent, where the rows choose.
  : >"$COMMAND_LOG"
  FAKE_NOTIFY_CLICK=1 zz_agent invite
  [ "$status" -eq 0 ]
  attempts=50
  until grep -q "dms " "$COMMAND_LOG" || [[ "$attempts" -eq 0 ]]; do
    sleep 0.1
    attempts=$((attempts - 1))
  done
  assert_file_contains "$COMMAND_LOG" "dms ipc call widget openWith zzMenu setup.agent"

  # A chosen agent means the invitation has nothing to offer.
  : >"$COMMAND_LOG"
  printf 'claude\n' >"$AGENT_FILE"
  zz_agent invite
  [ "$status" -eq 0 ]
  assert_contains "$output" "already chosen: Claude Code"
  [[ ! -s "$COMMAND_LOG" ]]
}

@test "choosing a default agent needs a supported, installed one" {
  zz_agent default cursor
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unsupported agent: cursor"
  [[ ! -e "$AGENT_FILE" ]]

  zz_agent default claude-code
  [ "$status" -ne 0 ]
  assert_contains "$output" "Claude Code is not installed"
  assert_contains "$output" "zz app install claude-code"
  [[ ! -e "$AGENT_FILE" ]]

  make_fake_command claude
  zz_agent default claude-code
  [ "$status" -eq 0 ]
  assert_equal "claude" "$(cat "$AGENT_FILE")"
}

@test "zz agent opens the default agent in a terminal window in its unattended mode" {
  make_fake_command claude
  printf 'claude\n' >"$AGENT_FILE"
  make_fake_command xdg-terminal-exec
  make_fake_command ghostty

  zz_agent
  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "xdg-terminal-exec --app-id=zz-agent --title=ZZ agent -- $FAKE_BIN/claude --permission-mode auto"
  refute_file_contains "$COMMAND_LOG" "ghostty"

  # The machine may carry a real xdg-terminal-exec in /usr/bin, so the
  # fallback runs on a PATH holding only what the launcher itself needs.
  rm "$FAKE_BIN/xdg-terminal-exec"
  : >"$COMMAND_LOG"
  local sysbin="$TEST_ROOT/sysbin" tool
  mkdir -p "$sysbin"
  for tool in bash readlink dirname find sort awk mkdir cat; do
    ln -s "$(command -v "$tool")" "$sysbin/$tool"
  done
  PATH="$FAKE_BIN:$sysbin" run bash "$ROOT_DIR/bin/zz" agent run
  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "ghostty --class=zz-agent -e $FAKE_BIN/claude --permission-mode auto"
}

@test "zz agent prompt passes the task the way each agent takes it" {
  make_fake_command claude
  make_fake_command codex
  make_fake_command opencode
  printf 'claude\n' >"$AGENT_FILE"

  zz_agent prompt "Why did nautilus crash?" --inline
  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "claude --permission-mode auto -- Why did nautilus crash?"

  printf 'codex\n' >"$AGENT_FILE"
  zz_agent prompt "Review this" --inline
  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "codex --approve-for-me -- Review this"

  printf 'opencode\n' >"$AGENT_FILE"
  zz_agent prompt "Review this" --inline
  [ "$status" -eq 0 ]
  assert_file_contains "$COMMAND_LOG" "opencode --auto --prompt Review this"

  zz_agent prompt
  [ "$status" -ne 0 ]
  assert_contains "$output" "Usage: zz agent prompt <text>"

  zz_agent run "Review this"
  [ "$status" -ne 0 ]
  assert_contains "$output" 'zz agent prompt "Review this"'
}

@test "a chosen agent that is no longer installed is reported, not silently replaced" {
  make_fake_command codex
  printf 'claude\n' >"$AGENT_FILE"

  zz_agent run --inline
  [ "$status" -ne 0 ]
  assert_contains "$output" "Claude Code is not installed"
  assert_contains "$output" "zz agent default <name>"
  refute_file_contains "$COMMAND_LOG" "codex"
}

@test "zz agent list reports installed and default state, and --notify confirms a choice" {
  make_fake_command codex
  zz_agent list --json
  [ "$status" -eq 0 ]
  assert_equal '[{"id":"claude","label":"Claude Code","installed":false,"default":false},{"id":"codex","label":"Codex CLI","installed":true,"default":false},{"id":"opencode","label":"OpenCode","installed":false,"default":false}]' "$output"

  make_fake_command notify-send
  zz_agent default codex --notify
  [ "$status" -eq 0 ]
  assert_contains "$output" "Default coding agent: Codex CLI (codex)"
  assert_file_contains "$COMMAND_LOG" "notify-send --app-name=zz --icon=dialog-information Default coding agent: Codex CLI"

  zz_agent list --json
  run jq -r '.[] | select(.default) | .id' <<<"$output"
  assert_equal "codex" "$output"
  zz_agent list
  [ "$status" -eq 0 ]
  assert_contains "$output" "codex     Codex CLI    installed, default"
  assert_contains "$output" "claude    Claude Code  not installed"
}

@test "the menu shows the agent and crash groups only once an agent is installed" {
  local menu="$ROOT_DIR/dotfiles/dms/.config/DankMaterialShell/plugins/ZzMenu/menu.json"
  local guard="command -v claude || command -v codex || command -v opencode"
  assert_equal "$guard" "$(jq -r '."setup.agent".when' "$menu")"
  assert_equal "agent" "$(jq -r '."setup.agent".provider' "$menu")"
  assert_equal "$guard" "$(jq -r '."troubleshoot.crash".when' "$menu")"
  # The capture switch and the mute list are about the watcher, which only
  # the crash-diagnosis choice links.
  run jq -e '[."troubleshoot.crash.capture", ."troubleshoot.crash.muted"] | all(.when | test("zz-crash-watch.service"))' "$menu"
  [ "$status" -eq 0 ]
}

@test "zz agent invite is not a failure on a desktop without notify-send" {
  make_fake_command claude
  local sysbin="$TEST_ROOT/sysbin" tool
  mkdir -p "$sysbin"
  for tool in bash readlink dirname find sort awk mkdir cat; do
    ln -s "$(command -v "$tool")" "$sysbin/$tool"
  done
  PATH="$FAKE_BIN:$sysbin" run bash "$ROOT_DIR/bin/zz" agent invite
  [ "$status" -eq 0 ]
  assert_contains "$output" "notify-send is not installed"
}
