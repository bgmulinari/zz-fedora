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
