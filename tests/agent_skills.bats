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

@test "base plan links the end-user skill into every assistant skills directory" {
  build_test_plan

  assert_plan_has "$PLAN_DIR/config/components.list" "agent-skills"
  local dir
  for dir in "${ASSISTANT_DIRS[@]}"; do
    assert_plan_has "$PLAN_DIR/files/managed-files.list" "$dir/zz"
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
