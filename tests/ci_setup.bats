#!/usr/bin/env bats
# zz-test-tags: smoke

setup() {
  ROOT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

ci_package_list() {
  grep -Ev '^[[:space:]]*(#|$)' "$ROOT_DIR/scripts/ci-packages.txt"
}

@test "CI package list is non-empty and one package per line" {
  run ci_package_list

  [ "$status" -eq 0 ]
  [ -n "$output" ]
  local package
  while IFS= read -r package; do
    [[ "$package" =~ ^[A-Za-z0-9._+-]+$ ]]
  done <<<"$output"
}

@test "CI package list carries the test-run dependencies" {
  run ci_package_list

  [ "$status" -eq 0 ]
  local package
  for package in bats ShellCheck git jq; do
    grep -qx "$package" <<<"$output"
  done
}

@test "CI workflow prepares the container through the tracked setup script" {
  run grep -F 'scripts/ci-setup.sh' "$ROOT_DIR/.github/workflows/ci.yml"

  [ "$status" -eq 0 ]
}

@test "CI workflow tests the minimum supported and latest Fedora containers" {
  source "$ROOT_DIR/config/defaults.sh"

  run grep -E "^[[:space:]]*fedora: \[\"$MINIMUM_FEDORA_RELEASE\", \"latest\"\]$" "$ROOT_DIR/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]

  run grep -F 'container: fedora:${{ matrix.fedora }}' "$ROOT_DIR/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]
}

@test "CI workflow runs the full suite once with lint enabled" {
  run grep -E 'ZZ_TEST_LINT=1 .*\./tests/full\.sh' "$ROOT_DIR/.github/workflows/ci.yml"

  [ "$status" -eq 0 ]
}

@test "CI setup script installs the tracked package list" {
  run grep -F 'ci-packages.txt' "$ROOT_DIR/scripts/ci-setup.sh"

  [ "$status" -eq 0 ]
}

@test "release workflow is manually triggered and gated on the CI tests" {
  run grep -F 'workflow_dispatch:' "$ROOT_DIR/.github/workflows/release-iso.yml"
  [ "$status" -eq 0 ]

  run grep -F 'workflow_call:' "$ROOT_DIR/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]

  run grep -F 'uses: ./.github/workflows/ci.yml' "$ROOT_DIR/.github/workflows/release-iso.yml"
  [ "$status" -eq 0 ]

  run grep -E '^[[:space:]]*needs: test$' "$ROOT_DIR/.github/workflows/release-iso.yml"
  [ "$status" -eq 0 ]
}

@test "release workflow builds through the tracked ISO builder" {
  run grep -F 'iso/scripts/build-fedora-installer-iso.sh' "$ROOT_DIR/.github/workflows/release-iso.yml"

  [ "$status" -eq 0 ]
}

@test "release workflow replaces one rolling release" {
  run grep -F 'gh release delete "$RELEASE_TAG" --yes --cleanup-tag' "$ROOT_DIR/.github/workflows/release-iso.yml"
  [ "$status" -eq 0 ]

  run grep -F 'gh release create "$RELEASE_TAG"' "$ROOT_DIR/.github/workflows/release-iso.yml"
  [ "$status" -eq 0 ]
}
