#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
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

@test "CI workflow tests Fedora containers from the resolved matrix" {
  run grep -F 'scripts/ci-fedora-matrix.sh' "$ROOT_DIR/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]

  run grep -F 'fedora: ${{ fromJSON(needs.matrix.outputs.fedora) }}' "$ROOT_DIR/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]

  run grep -F 'container: fedora:${{ matrix.fedora }}' "$ROOT_DIR/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]
}

# Stub curl with the Docker Hub tags API shape the matrix script consumes.
# The minimum-release arm is pinned to the exact tag so a wrong-tag query
# falls through to exit 1 instead of being answered, and the fixed arm64
# entry comes first so a regression from architecture-based selection back
# to .images[0] compares identical arm64 digests and fails the
# differing-image test below.
write_curl_stub() {
  export ZZ_TEST_MINIMUM_TAG="$MINIMUM_FEDORA_RELEASE"
  export ZZ_TEST_MINIMUM_DIGEST="$1"
  export ZZ_TEST_LATEST_DIGEST="$2"
  write_fake_command curl <<'SH'
#!/usr/bin/env bash
url="${*: -1}"
arm64_digest="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
respond() {
  printf '{"images": [{"architecture": "arm64", "digest": "%s"}, {"architecture": "amd64", "digest": "%s"}]}' \
    "$arm64_digest" "$1"
}
case "$url" in
  */tags/latest) respond "$ZZ_TEST_LATEST_DIGEST" ;;
  */tags/"$ZZ_TEST_MINIMUM_TAG") respond "$ZZ_TEST_MINIMUM_DIGEST" ;;
  *) exit 1 ;;
esac
SH
}

@test "matrix script drops the latest leg when it matches the minimum release image" {
  command -v jq >/dev/null 2>&1 || skip "jq is not installed"
  source "$ROOT_DIR/config/defaults.sh"
  setup_fake_bin
  local digest="sha256:$(printf 'a%.0s' {1..64})"
  write_curl_stub "$digest" "$digest"

  run env PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/scripts/ci-fedora-matrix.sh"

  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "fedora=[\"$MINIMUM_FEDORA_RELEASE\"]" ]
}

@test "matrix script keeps both legs when latest is a different image" {
  command -v jq >/dev/null 2>&1 || skip "jq is not installed"
  source "$ROOT_DIR/config/defaults.sh"
  setup_fake_bin
  write_curl_stub "sha256:$(printf 'a%.0s' {1..64})" "sha256:$(printf 'b%.0s' {1..64})"

  run env PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/scripts/ci-fedora-matrix.sh"

  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "fedora=[\"$MINIMUM_FEDORA_RELEASE\", \"latest\"]" ]
}

@test "matrix script keeps both legs when digest resolution fails" {
  command -v jq >/dev/null 2>&1 || skip "jq is not installed"
  source "$ROOT_DIR/config/defaults.sh"
  setup_fake_bin
  make_fake_command curl 22

  run env PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/scripts/ci-fedora-matrix.sh"

  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "fedora=[\"$MINIMUM_FEDORA_RELEASE\", \"latest\"]" ]
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
