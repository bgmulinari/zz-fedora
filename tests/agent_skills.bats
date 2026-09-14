#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

SKILLS_ROOT="dotfiles/agent-skills/.agents/skills"
ASSISTANT_DIRS=('~/.agents/skills' '~/.claude/skills' '~/.codex/skills' '~/.pi/agent/skills')

setup() {
  setup_test_env
  source_core
}

shipped_skill_names() {
  local dir
  for dir in "$ROOT_DIR/$SKILLS_ROOT"/*/; do
    [[ -d "$dir" ]] || continue
    basename "$dir"
  done
}

@test "every shipped skill has a manifest header and existing topic guides" {
  local name skill guide found=0
  for name in $(shipped_skill_names); do
    found=1
    skill="$ROOT_DIR/$SKILLS_ROOT/$name/SKILL.md"
    [[ -f "$skill" ]]
    assert_equal "---" "$(sed -n 1p "$skill")"
    assert_file_contains "$skill" "name: $name"
    assert_file_contains "$skill" "description:"
    # Guides are linked as [`file.md`](file.md); each must exist beside SKILL.md.
    while IFS= read -r guide; do
      [[ -f "$ROOT_DIR/$SKILLS_ROOT/$name/$guide" ]] || {
        printf '%s links missing guide %s\n' "$skill" "$guide" >&2
        return 1
      }
    done < <(grep -oE '\]\([a-z0-9-]+\.md\)' "$skill" | sed 's/^](//; s/)$//' | sort -u)
  done
  [ "$found" -eq 1 ]
}

@test "every shipped skill directory is linked into every assistant skills directory" {
  local name dir
  for name in $(shipped_skill_names); do
    for dir in "${ASSISTANT_DIRS[@]}"; do
      assert_file_contains "$ROOT_DIR/config/managed-config.tsv" \
        "agent-skills"$'\t'"$dir/$name"$'\t'"product-link"$'\t'"backup-before-link"$'\t'"$SKILLS_ROOT/$name"$'\t'"-"
    done
  done
}

@test "base plan links every shipped skill into every assistant skills directory" {
  build_test_plan

  assert_plan_has "$PLAN_DIR/config/components.list" "agent-skills"
  local name dir
  for name in $(shipped_skill_names); do
    for dir in "${ASSISTANT_DIRS[@]}"; do
      assert_plan_has "$PLAN_DIR/files/managed-files.list" "$dir/$name"
    done
  done
}

@test "skill links resolve to the repository directory and expose SKILL.md" {
  DRY_RUN=0
  SKIP_USER_CONFIG=0
  run_cmd_as_user() { shift; "$@"; }
  local source="$ROOT_DIR/$SKILLS_ROOT/zz"
  local destination="$TARGET_HOME/.claude/skills/zz"

  run replace_user_path_with_product_link "$source" "$destination"

  [ "$status" -eq 0 ]
  [[ -L "$destination" ]]
  [[ -f "$destination/SKILL.md" ]]
  [[ -f "$destination/niri.md" ]]
  assert_equal "$(readlink -f "$source")" "$(readlink -f "$destination")"
}

@test "repository task guides are indexed from AGENTS.md and never shipped to home directories" {
  local guide
  for guide in "$ROOT_DIR"/agents/skills/*/; do
    [[ -f "$guide/SKILL.md" ]]
    assert_file_contains "$ROOT_DIR/AGENTS.md" "agents/skills/$(basename "$guide")/SKILL.md"
  done
  # CLAUDE.md is a symlink to AGENTS.md, so both assistants read one file.
  [[ -L "$ROOT_DIR/CLAUDE.md" ]]
  assert_equal "$(readlink -f "$ROOT_DIR/AGENTS.md")" "$(readlink -f "$ROOT_DIR/CLAUDE.md")"

  run awk -F'\t' '$5 ~ /^agents\// {print $2}' "$ROOT_DIR/config/managed-config.tsv"

  [ "$status" -eq 0 ]
  assert_equal "" "$output"
}

@test "the shipped skills elevate through pkexec and announce the command and reason first" {
  local zz_skill="$ROOT_DIR/$SKILLS_ROOT/zz/SKILL.md"
  local crash_skill="$ROOT_DIR/$SKILLS_ROOT/diagnose-crash/SKILL.md"
  assert_file_contains "$zz_skill" "run the command through \`pkexec\`"
  assert_file_contains "$zz_skill" "print the full command and the reason for it"
  assert_file_contains "$zz_skill" "Running with elevated permissions:"
  refute_file_contains "$zz_skill" "sudo dnf install"
  assert_file_contains "$crash_skill" "run it through \`pkexec\`"
  assert_file_contains "$crash_skill" "print the full command and"
}

@test "the plugin authoring skill answers from the installed shell and stays out of the repository" {
  local skill="$ROOT_DIR/$SKILLS_ROOT/create-dms-plugin/SKILL.md"
  # The installed package carries the guide, schema, and examples for the exact
  # release the plugin loads into; the skill points there instead of at memory.
  assert_file_contains "$skill" "/usr/share/quickshell/dms/"
  assert_file_contains "$skill" "PLUGINS/README.md"
  assert_file_contains "$skill" "dms ipc call plugin-scan"
  assert_file_contains "$skill" "~/.config/DankMaterialShell/plugins/"
  # Shipping a plugin with ZZ is the repository task guide's job.
  refute_file_contains "$skill" "managed-config"
  refute_file_contains "$skill" "catalog/"
  refute_file_contains "$skill" "install.sh"
}
