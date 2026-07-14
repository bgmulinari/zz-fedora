#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

@test "defaults resolve the current account when USER is absent" {
  run env -u USER -u SUDO_USER bash -c '
    set -Eeuo pipefail
    source "$1/config/defaults.sh"
    [[ "$DEFAULT_TARGET_USER" == "$(id -un)" ]]
  ' _ "$ROOT_DIR"

  [ "$status" -eq 0 ]
}

@test "manifest parser trims comments, blanks, whitespace, and duplicates" {
  manifest="$TEST_ROOT/test.pkgs"
  printf '%s\n' \
    '# comment' \
    'ghostty' \
    '' \
    'firefox   # inline comment' \
    'ghostty' \
    '  chromium  ' \
    >"$manifest"

  assert_equal $'chromium\nfirefox\nghostty' "$(manifest_entries "$manifest")"
}

@test "platform validation recognizes Fedora os-release files" {
  os_release="$TEST_ROOT/fedora-os-release"
  printf 'ID=fedora\n' >"$os_release"

  run fedora_release_file_is_supported "$os_release"
  [ "$status" -eq 0 ]

  printf 'ID=ubuntu\n' >"$os_release"
  run fedora_release_file_is_supported "$os_release"
  [ "$status" -ne 0 ]
}

@test "Fedora release support uses a minimum version floor" {
  MINIMUM_FEDORA_RELEASE=44

  run fedora_release_is_supported 43
  [ "$status" -ne 0 ]

  run fedora_release_is_supported 44
  [ "$status" -eq 0 ]

  run fedora_release_is_supported 45
  [ "$status" -eq 0 ]

  run fedora_release_is_supported rawhide
  [ "$status" -ne 0 ]
}

@test "bundle descriptor validation rejects missing or unsupported fields" {
  local descriptor_dir="$TEST_ROOT/bundles"
  mkdir -p "$descriptor_dir"

  cat >"$descriptor_dir/valid.bundle" <<'EOF'
BUNDLE_ID="test-valid"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_ID=""
BUNDLE_ITEMS_FILE="packages/official/bootstrap.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Valid test bundle"
EOF
  validate_bundle_descriptor "$descriptor_dir/valid.bundle"

  cat >"$descriptor_dir/missing-id.bundle" <<'EOF'
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_ID=""
BUNDLE_ITEMS_FILE="packages/official/bootstrap.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Missing id"
EOF
  run validate_bundle_descriptor "$descriptor_dir/missing-id.bundle"
  [ "$status" -ne 0 ]

  cat >"$descriptor_dir/bad-installer.bundle" <<'EOF'
BUNDLE_ID="test-bad-installer"
BUNDLE_INSTALLER="brew"
BUNDLE_SOURCE_ID=""
BUNDLE_ITEMS_FILE="packages/official/bootstrap.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Bad installer"
EOF
  run validate_bundle_descriptor "$descriptor_dir/bad-installer.bundle"
  [ "$status" -ne 0 ]

  cat >"$descriptor_dir/missing-items.bundle" <<'EOF'
BUNDLE_ID="test-missing-items"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_ID=""
BUNDLE_ITEMS_FILE="packages/__test__/missing.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Missing items file"
EOF
  run validate_bundle_descriptor "$descriptor_dir/missing-items.bundle"
  [ "$status" -ne 0 ]
}

@test "source descriptors include required trust metadata" {
  local source_file
  while IFS= read -r source_file; do
    assert_file_contains "$source_file" 'SOURCE_GPG_POLICY='
    assert_file_contains "$source_file" 'SOURCE_BOOTSTRAP_EXCEPTION='
    assert_file_contains "$source_file" 'SOURCE_REQUIRED='
    assert_file_contains "$source_file" 'SOURCE_REASON='
  done < <(find "$ROOT_DIR/sources" -type f -name '*.source' | sort)

  assert_file_contains "$ROOT_DIR/sources/terra/terra.source" 'SOURCE_GPG_POLICY="unsigned-bootstrap"'
  assert_file_contains "$ROOT_DIR/sources/terra/terra.source" 'SOURCE_BOOTSTRAP_EXCEPTION=1'
}

@test "source id catalog contains each descriptor exactly once" {
  local expected_count actual_count unique_count
  expected_count="$(find "$ROOT_DIR/sources" -type f -name '*.source' | wc -l | tr -d ' ')"
  actual_count="$(list_source_ids | wc -l | tr -d ' ')"
  unique_count="$(list_source_ids | sort -u | wc -l | tr -d ' ')"

  assert_equal "$expected_count" "$actual_count"
  assert_equal "$actual_count" "$unique_count"
}

@test "choice parser preserves empty bundle fields and rejects extra fields" {
  local fixture_catalog="$TEST_ROOT/choices.conf"
  printf 'empty\tEmpty choice\t0\t\tNo bundle required\n' >"$fixture_catalog"
  choice_catalog_path() {
    printf '%s\n' "$fixture_catalog"
  }

  validate_choice_catalog browsers
  assert_equal "" "$(choice_field $'empty\tEmpty choice\t0\t\tNo bundle required' 4)"
  assert_equal "No bundle required" "$(choice_field $'empty\tEmpty choice\t0\t\tNo bundle required' 5)"

  printf 'bad\tBad choice\t0\t\tDescription\textra\n' >"$fixture_catalog"
  run validate_choice_catalog browsers
  [ "$status" -ne 0 ]
}

@test "choice validation rejects duplicate IDs and invalid default flags" {
  local fixture_catalog="$TEST_ROOT/choices.conf"
  choice_catalog_path() {
    printf '%s\n' "$fixture_catalog"
  }

  printf 'one\tOne\t2\t\tInvalid default\n' >"$fixture_catalog"
  run validate_choice_catalog browsers
  [ "$status" -ne 0 ]

  printf '%s\n' \
    $'one\tOne\t0\t\tFirst' \
    $'one\tOne again\t0\t\tDuplicate' \
    >"$fixture_catalog"
  run validate_choice_catalog browsers
  [ "$status" -ne 0 ]
}

@test "normal installer defaults to every optional choice except Firefox-only browsers" {
  local category
  assert_equal "firefox" "$(effective_choice_ids browsers)"

  for category in ai dev dotnet gaming media office; do
    assert_equal \
      "$(all_choice_ids "$category")" \
      "$(effective_choice_ids "$category")"
  done
}

@test "choice descriptions explain purpose without package source wording" {
  local catalog choice_id label default_flag bundle_ids description
  while IFS= read -r catalog; do
    while IFS=$'\t' read -r choice_id label default_flag bundle_ids description; do
      [[ -n "$choice_id" && "$choice_id" != \#* ]] || continue
      if grep -Eiq '(RPM|COPR|Flatpak|Flathub|Homebrew|Fedora|repository)' <<<"$description"; then
        printf 'package source wording in %s description: %s\n' "$choice_id" "$description" >&2
        return 1
      fi
    done <"$catalog"
  done < <(list_choice_catalogs)
}

@test "TUI passes defaults separately and escapes gum selection delimiters" {
  local gum_args="$TEST_ROOT/gum-args"
  gum() {
    printf '%s\n' "$@" >"$gum_args"
    return 1
  }

  tui_pick_catalog_choices ai "Test choices"

  assert_equal \
    "$(all_choice_ids ai | wc -l | tr -d ' ')" \
    "$(grep -cx -- '--selected' "$gum_args")"
  assert_file_contains \
    "$gum_args" \
    'Claude Code                    Terminal coding agent that reads\, edits\, and tests codebases'
}

@test "catalog identifies installed product surfaces precisely" {
  local record

  record="$(choice_record ai opencode)"
  assert_equal "OpenCode Terminal" "$(choice_field "$record" 2)"
  assert_equal \
    "Open-source AI coding agent built for the terminal" \
    "$(choice_field "$record" 5)"

  record="$(choice_record ai claude-desktop)"
  assert_equal \
    "Unofficial Linux port of the Claude Desktop app" \
    "$(choice_field "$record" 5)"

  record="$(choice_record dev docker)"
  assert_equal \
    "Docker Engine, CLI, containerd, Buildx, and Compose for running containers" \
    "$(choice_field "$record" 5)"
}

@test "base shell artifacts use pinned commit trust policies" {
  local source_id
  for source_id in \
    artifact:oh-my-zsh \
    artifact:zsh-autosuggestions \
    artifact:zsh-syntax-highlighting; do
    load_source_descriptor "$source_id"
    assert_equal "artifact" "$SOURCE_KIND"
    assert_equal "pinned-commit" "$SOURCE_GPG_POLICY"
    assert_equal "1" "$SOURCE_REQUIRED"
    [[ "$SOURCE_PROJECT" == *@???????????????????????????????????????? ]]
  done
}

@test "base bundle ids are not exposed as optional choice ids" {
  local base_id choice_file
  for base_id in "${BASE_BUNDLE_IDS[@]}"; do
    for choice_file in "$ROOT_DIR"/choices/*.conf; do
      ! awk -F'\t' -v id="$base_id" 'NF==5 && $1 == id {found=1} END {exit found ? 0 : 1}' "$choice_file"
    done
  done
}
