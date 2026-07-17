#!/usr/bin/env bats

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=helpers/runner.bash
  source "$ROOT_DIR/tests/helpers/runner.bash"
  bats() {
    printf 'bats:%s\n' "$*"
  }
}

@test "test runner keeps suites sequential when one job is requested" {
  ZZ_TEST_JOBS=1

  run run_bats_suites first.bats second.bats

  [ "$status" -eq 0 ]
  [ "$output" = "bats:first.bats second.bats" ]
}

@test "test runner parallelizes files but not tests within a file" {
  ZZ_TEST_JOBS=3

  run run_bats_suites first.bats second.bats

  [ "$status" -eq 0 ]
  [ "$output" = "bats:--jobs 3 --no-parallelize-within-files first.bats second.bats" ]
}

@test "test runner rejects invalid job counts" {
  ZZ_TEST_JOBS=invalid

  run run_bats_suites first.bats

  [ "$status" -ne 0 ]
  [[ "$output" == *"ZZ_TEST_JOBS must be a positive integer."* ]]
}

@test "tagged suite selection returns only suites carrying the tag" {
  local tests_dir="$BATS_TEST_TMPDIR/tests"
  mkdir -p "$tests_dir"
  printf '#!/usr/bin/env bats\n# zz-test-tags: smoke\n' >"$tests_dir/alpha.bats"
  printf '#!/usr/bin/env bats\n' >"$tests_dir/beta.bats"
  printf '#!/usr/bin/env bats\n# zz-test-tags: smoke slow\n' >"$tests_dir/gamma.bats"

  run list_tagged_bats_suites smoke "$tests_dir"

  [ "$status" -eq 0 ]
  [ "$output" = "$tests_dir/alpha.bats
$tests_dir/gamma.bats" ]
}

@test "tagged suite selection does not match tags as substrings" {
  local tests_dir="$BATS_TEST_TMPDIR/tests"
  mkdir -p "$tests_dir"
  printf '#!/usr/bin/env bats\n# zz-test-tags: smokescreen\n' >"$tests_dir/alpha.bats"
  printf '#!/usr/bin/env bats\n# zz-test-tags: smoke\n' >"$tests_dir/beta.bats"

  run list_tagged_bats_suites smoke "$tests_dir"

  [ "$status" -eq 0 ]
  [ "$output" = "$tests_dir/beta.bats" ]
}

@test "tagged suite selection fails loudly when no suite carries the tag" {
  local tests_dir="$BATS_TEST_TMPDIR/tests"
  mkdir -p "$tests_dir"
  printf '#!/usr/bin/env bats\n' >"$tests_dir/alpha.bats"

  run list_tagged_bats_suites smoke "$tests_dir"

  [ "$status" -ne 0 ]
  [[ "$output" == *'No bats suites tagged "smoke"'* ]]
}

@test "tag runner requires exactly one tag argument" {
  run bash "$ROOT_DIR/tests/run.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: tests/run.sh <tag>"* ]]
}

@test "tag runner fails loudly for a tag no suite carries" {
  run bash "$ROOT_DIR/tests/run.sh" no-such-tag

  [ "$status" -ne 0 ]
  [[ "$output" == *'No bats suites tagged "no-such-tag"'* ]]
}

@test "repository smoke gate selects at least one tagged suite" {
  run list_tagged_bats_suites smoke "$ROOT_DIR/tests"

  [ "$status" -eq 0 ]
  [ -n "$output" ]
  while IFS= read -r suite; do
    [ -f "$suite" ]
  done <<<"$output"
}

@test "shell lint targets resolve to existing files including CI setup script" {
  cd "$ROOT_DIR"

  run shell_lint_targets

  [ "$status" -eq 0 ]
  [ -n "$output" ]
  local found_ci_setup=0 target
  while IFS= read -r target; do
    [ -f "$target" ]
    [[ "$target" == "scripts/ci-setup.sh" ]] && found_ci_setup=1
  done <<<"$output"
  [ "$found_ci_setup" -eq 1 ]
}

@test "shellcheck lint gate runs at warning severity over the shared target list" {
  cd "$ROOT_DIR"
  shellcheck() {
    printf 'shellcheck:%s\n' "$*"
  }

  run run_shellcheck_lint

  [ "$status" -eq 0 ]
  [[ "$output" == shellcheck:-S\ warning\ * ]]
  [[ "$output" == *"bootstrap.sh install.sh bin/zz"* ]]
}
