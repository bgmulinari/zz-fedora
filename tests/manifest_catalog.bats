#!/usr/bin/env bats
# zz-test-tags: smoke

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
  previous_release="$((MINIMUM_FEDORA_RELEASE - 1))"
  next_release="$((MINIMUM_FEDORA_RELEASE + 1))"

  run fedora_release_is_supported "$previous_release"
  [ "$status" -ne 0 ]

  run fedora_release_is_supported "$MINIMUM_FEDORA_RELEASE"
  [ "$status" -eq 0 ]

  run fedora_release_is_supported "$next_release"
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
BUNDLE_SOURCE_IDS=""
BUNDLE_ITEMS_FILE="packages/official/bootstrap.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Valid test bundle"
EOF
  validate_bundle_descriptor "$descriptor_dir/valid.bundle"

  cat >"$descriptor_dir/missing-id.bundle" <<'EOF'
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_IDS=""
BUNDLE_ITEMS_FILE="packages/official/bootstrap.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Missing id"
EOF
  run validate_bundle_descriptor "$descriptor_dir/missing-id.bundle"
  [ "$status" -ne 0 ]

  cat >"$descriptor_dir/bad-installer.bundle" <<'EOF'
BUNDLE_ID="test-bad-installer"
BUNDLE_INSTALLER="brew"
BUNDLE_SOURCE_IDS=""
BUNDLE_ITEMS_FILE="packages/official/bootstrap.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Bad installer"
EOF
  run validate_bundle_descriptor "$descriptor_dir/bad-installer.bundle"
  [ "$status" -ne 0 ]

  cat >"$descriptor_dir/bad-source.bundle" <<'EOF'
BUNDLE_ID="test-bad-source"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_IDS="missing-source"
BUNDLE_ITEMS_FILE="packages/official/bootstrap.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Bad source"
EOF
  run validate_bundle_descriptor "$descriptor_dir/bad-source.bundle"
  [ "$status" -ne 0 ]

  cat >"$descriptor_dir/missing-items.bundle" <<'EOF'
BUNDLE_ID="test-missing-items"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_IDS=""
BUNDLE_ITEMS_FILE="packages/__test__/missing.pkgs"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Missing items file"
EOF
  run validate_bundle_descriptor "$descriptor_dir/missing-items.bundle"
  [ "$status" -ne 0 ]

  cat >"$descriptor_dir/no-items.bundle" <<'EOF'
BUNDLE_ID="test-no-items"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_IDS=""
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Source-only bundle without payload items"
EOF
  validate_bundle_descriptor "$descriptor_dir/no-items.bundle"

  cat >"$descriptor_dir/bad-suffix.bundle" <<'EOF'
BUNDLE_ID="test-bad-suffix"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_IDS=""
BUNDLE_ITEMS_FILE="packages/empty.list"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Non-manifest payload suffix"
EOF
  run validate_bundle_descriptor "$descriptor_dir/bad-suffix.bundle"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must use a manifest suffix"* ]]
}

@test "bundle descriptor validation rejects unknown keys" {
  local descriptor_dir="$TEST_ROOT/bundles"
  mkdir -p "$descriptor_dir"

  cat >"$descriptor_dir/legacy-source-key.bundle" <<'EOF'
BUNDLE_ID="test-legacy-source-key"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_ID="rpmfusion-free"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Bundle using the retired singular source key"
EOF
  run validate_bundle_descriptor "$descriptor_dir/legacy-source-key.bundle"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown bundle descriptor key 'BUNDLE_SOURCE_ID'"

  cat >"$descriptor_dir/unknown-key.bundle" <<'EOF'
BUNDLE_ID="test-unknown-key"
BUNDLE_INSTALLER="dnf"
BUNDLE_FROBNICATE="1"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Bundle with a made-up key"
EOF
  run validate_bundle_descriptor "$descriptor_dir/unknown-key.bundle"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown bundle descriptor key 'BUNDLE_FROBNICATE'"

  cat >"$descriptor_dir/multi-source.bundle" <<'EOF'
BUNDLE_ID="test-multi-source"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_IDS="rpmfusion-free,rpmfusion-nonfree"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Bundle with a comma-separated source list"
EOF
  validate_bundle_descriptor "$descriptor_dir/multi-source.bundle"
}

@test "source descriptor validation rejects unknown keys" {
  local descriptor_dir="$TEST_ROOT/sources"
  mkdir -p "$descriptor_dir"

  cat >"$descriptor_dir/unknown-key.source" <<'EOF'
SOURCE_ID="vendor:test-unknown-key"
SOURCE_KIND="vendor"
SOURCE_LABEL="Test vendor repository"
SOURCE_FROBNICATE="1"
SOURCE_REQUIRED=0
SOURCE_DESCRIPTION="Source with a made-up key"
SOURCE_GPG_POLICY="repo-gpg-key"
SOURCE_BOOTSTRAP_EXCEPTION=0
SOURCE_REASON="Test fixture"
EOF
  run validate_source_descriptor "$descriptor_dir/unknown-key.source"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown source descriptor key 'SOURCE_FROBNICATE'"
}

@test "source descriptor validation scopes SOURCE_PROJECT by kind" {
  local descriptor_dir="$TEST_ROOT/sources"
  mkdir -p "$descriptor_dir"

  cat >"$descriptor_dir/copr-no-project.source" <<'EOF'
SOURCE_ID="copr:test/no-project"
SOURCE_KIND="copr"
SOURCE_LABEL="COPR without a project"
SOURCE_REQUIRED=0
SOURCE_DESCRIPTION="COPR source missing SOURCE_PROJECT"
SOURCE_GPG_POLICY="copr-plugin"
SOURCE_BOOTSTRAP_EXCEPTION=0
SOURCE_REASON="Test fixture"
EOF
  run validate_source_descriptor "$descriptor_dir/copr-no-project.source"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Missing SOURCE_PROJECT for copr source"

  cat >"$descriptor_dir/vendor-with-project.source" <<'EOF'
SOURCE_ID="vendor:test-with-project"
SOURCE_KIND="vendor"
SOURCE_LABEL="Vendor with a stray project"
SOURCE_PROJECT="acme/stray"
SOURCE_REQUIRED=0
SOURCE_DESCRIPTION="Vendor source declaring SOURCE_PROJECT"
SOURCE_GPG_POLICY="repo-gpg-key"
SOURCE_BOOTSTRAP_EXCEPTION=0
SOURCE_REASON="Test fixture"
EOF
  run validate_source_descriptor "$descriptor_dir/vendor-with-project.source"
  [ "$status" -ne 0 ]
  assert_contains "$output" "SOURCE_PROJECT is only valid for artifact and copr sources"

  cat >"$descriptor_dir/vendor-plain.source" <<'EOF'
SOURCE_ID="vendor:test-plain"
SOURCE_KIND="vendor"
SOURCE_LABEL="Vendor without a project"
SOURCE_REQUIRED=0
SOURCE_DESCRIPTION="Vendor source omitting SOURCE_PROJECT"
SOURCE_GPG_POLICY="repo-gpg-key"
SOURCE_BOOTSTRAP_EXCEPTION=0
SOURCE_REASON="Test fixture"
EOF
  validate_source_descriptor "$descriptor_dir/vendor-plain.source"
}

@test "action manifest validation accepts registered ids and rejects unknown ids" {
  manifest="$TEST_ROOT/test.actions"
  printf '%s\n' 'docker' 'brew:lazydocker' 'vscode-extension:noctalia.noctaliatheme' >"$manifest"
  validate_action_manifest "$manifest"

  printf '%s\n' 'docker' 'not-a-registered-action' >"$manifest"
  run validate_action_manifest "$manifest"
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown custom action 'not-a-registered-action' in $manifest"
}

@test "action bundle payload referencing an unregistered id fails descriptor validation" {
  fixture_root="$TEST_ROOT/fixture-root"
  mkdir -p "$fixture_root/packages/actions"
  printf 'not-a-registered-action\n' >"$fixture_root/packages/actions/bad.actions"
  cat >"$TEST_ROOT/bad-actions.bundle" <<'EOF'
BUNDLE_ID="test-bad-actions"
BUNDLE_INSTALLER="action"
BUNDLE_SOURCE_IDS=""
BUNDLE_ITEMS_FILE="packages/actions/bad.actions"
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Payload referencing an unregistered action"
EOF
  validate_fixture_bundle() {
    ROOT_DIR="$fixture_root" validate_bundle_descriptor "$TEST_ROOT/bad-actions.bundle"
  }

  run validate_fixture_bundle
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown custom action 'not-a-registered-action'"
}

@test "every bundle payload file uses a declared manifest suffix and exists" {
  local bundle_file items_file
  while IFS= read -r bundle_file; do
    items_file=""
    descriptor_value_from_file "$bundle_file" BUNDLE_ITEMS_FILE items_file || true
    [[ -n "$items_file" ]] || continue
    [[ "$items_file" =~ \.(pkgs|flatpaks|actions)$ ]]
    [ -f "$ROOT_DIR/$items_file" ]
  done < <(find "$ROOT_DIR/bundles" -type f -name '*.bundle' | sort)
}

@test "every bundle ID is its category directory name plus its file basename" {
  local bundle_file bundle_id category basename
  while IFS= read -r bundle_file; do
    bundle_id=""
    descriptor_value_from_file "$bundle_file" BUNDLE_ID bundle_id
    category="$(basename "$(dirname "$bundle_file")")"
    basename="$(basename "$bundle_file" .bundle)"
    assert_equal "$category-$basename" "$bundle_id"
  done < <(find "$ROOT_DIR/bundles" -type f -name '*.bundle' | sort)
}

@test "every dotfiles directory is referenced by a bundle stow declaration" {
  local bundle_file stow_packages package package_dir referenced=$'\n'

  while IFS= read -r bundle_file; do
    stow_packages=""
    descriptor_value_from_file "$bundle_file" BUNDLE_STOW_PACKAGES stow_packages || true
    [[ -n "$stow_packages" ]] || continue
    while IFS= read -r package; do
      referenced+="${package}"$'\n'
    done < <(split_csv "$stow_packages")
  done < <(find "$ROOT_DIR/bundles" -type f -name '*.bundle' | sort)

  while IFS= read -r package_dir; do
    package="$(basename "$package_dir")"
    if [[ "$referenced" != *$'\n'"$package"$'\n'* ]]; then
      printf 'orphan stow package not referenced by any bundle: dotfiles/%s\n' "$package" >&2
      return 1
    fi
  done < <(find "$ROOT_DIR/dotfiles" -mindepth 1 -maxdepth 1 -type d | sort)
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

  for category in $(category_names); do
    [[ "$category" == "browsers" ]] && continue
    assert_equal \
      "$(all_choice_ids "$category")" \
      "$(effective_choice_ids "$category")"
  done
}

@test "minimal desktop profile skips desktop defaults but keeps explicit selections" {
  DESKTOP_APP_PROFILE=minimal

  assert_equal "" "$(effective_choice_ids desktop)"

  add_category_selection desktop calculator
  assert_equal "calculator" "$(effective_choice_ids desktop)"
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

@test "TUI passes effective defaults separately and escapes gum selection delimiters" {
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

@test "TUI desktop preselection respects the effective profile and explicit additions" {
  local gum_args="$TEST_ROOT/gum-args"
  gum() {
    printf '%s\n' "$@" >"$gum_args"
    return 1
  }

  DESKTOP_APP_PROFILE=minimal
  tui_pick_catalog_choices desktop "Test desktop choices"
  assert_equal \
    "0" \
    "$(awk '$0 == "--selected" {count++} END {print count+0}' "$gum_args")"

  add_category_selection desktop calculator
  tui_pick_catalog_choices desktop "Test desktop choices"
  assert_equal \
    "1" \
    "$(awk '$0 == "--selected" {count++} END {print count+0}' "$gum_args")"
  assert_file_contains \
    "$gum_args" \
    'Calculator                     Perform arithmetic\, scientific\, and financial calculations'
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

@test "base bundle membership is derived from bundle metadata" {
  local bundle_file bundle_id base_flag
  local -a declared_base_ids=()

  while IFS= read -r bundle_file; do
    descriptor_value_from_file "$bundle_file" BUNDLE_ID bundle_id
    base_flag=""
    descriptor_value_from_file "$bundle_file" BUNDLE_BASE base_flag || true
    if [[ "$bundle_file" == "$ROOT_DIR/bundles/base/"* ]]; then
      assert_equal "1" "$base_flag"
    fi
    [[ "$base_flag" == "1" ]] && declared_base_ids+=("$bundle_id")
  done < <(list_bundle_files)

  assert_equal "${#declared_base_ids[@]}" "${#BASE_BUNDLE_IDS[@]}"
  for bundle_id in "${declared_base_ids[@]}"; do
    array_contains "$bundle_id" "${BASE_BUNDLE_IDS[@]}"
  done
  for bundle_id in "${BASE_BUNDLE_IDS[@]}"; do
    bundle_file_for_id "$bundle_id" >/dev/null
  done
  for bundle_id in "${EARLY_BASE_BUNDLE_IDS[@]}"; do
    array_contains "$bundle_id" "${BASE_BUNDLE_IDS[@]}"
  done
  for bundle_id in "${MINIMAL_DESKTOP_SKIP_BUNDLE_IDS[@]}"; do
    array_contains "$bundle_id" "${BASE_BUNDLE_IDS[@]}"
  done
}

@test "a new bundles/base descriptor joins the derived base set at its declared order" {
  local sandbox="$TEST_ROOT/sandbox-root"
  mkdir -p "$sandbox"
  cp -R "$ROOT_DIR/bundles" "$sandbox/bundles"
  cat >"$sandbox/bundles/base/zz-test.bundle" <<'BUNDLE'
BUNDLE_ID="base-zz-test"
BUNDLE_BASE="1"
BUNDLE_BASE_ORDER="15"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_IDS=""
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Sandbox base bundle for derivation tests"
BUNDLE

  derive_sandbox_base_ids() {
    ROOT_DIR="$sandbox"
    BUNDLE_FILE_CACHE=()
    BUNDLE_FILE_CACHE_LOADED=()
    BASE_BUNDLE_CATALOG_LOADED=()
    load_base_bundle_catalog
    printf '%s\n' "${BASE_BUNDLE_IDS[@]}"
  }

  run derive_sandbox_base_ids
  [ "$status" -eq 0 ]
  assert_equal "base-bootstrap" "${lines[0]}"
  assert_equal "base-zz-test" "${lines[1]}"
  assert_equal "base-source-rpmfusion-free" "${lines[2]}"
}

@test "a bundles/base descriptor without BUNDLE_BASE=1 fails catalog derivation" {
  local sandbox="$TEST_ROOT/sandbox-root-invalid"
  mkdir -p "$sandbox"
  cp -R "$ROOT_DIR/bundles" "$sandbox/bundles"
  cat >"$sandbox/bundles/base/zz-test.bundle" <<'BUNDLE'
BUNDLE_ID="base-zz-test"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_IDS=""
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Sandbox base bundle missing base metadata"
BUNDLE

  derive_invalid_sandbox_base_ids() {
    ROOT_DIR="$sandbox"
    BUNDLE_FILE_CACHE=()
    BUNDLE_FILE_CACHE_LOADED=()
    BASE_BUNDLE_CATALOG_LOADED=()
    load_base_bundle_catalog
  }

  run derive_invalid_sandbox_base_ids
  [ "$status" -ne 0 ]
  assert_contains "$output" "must declare BUNDLE_BASE=1"
}

@test "duplicate BUNDLE_BASE_ORDER fails catalog derivation" {
  local sandbox="$TEST_ROOT/sandbox-root-dup-order"
  mkdir -p "$sandbox"
  cp -R "$ROOT_DIR/bundles" "$sandbox/bundles"
  cat >"$sandbox/bundles/base/zz-test.bundle" <<'BUNDLE'
BUNDLE_ID="base-zz-test"
BUNDLE_BASE="1"
BUNDLE_BASE_ORDER="10"
BUNDLE_INSTALLER="dnf"
BUNDLE_SOURCE_IDS=""
BUNDLE_STOW_PACKAGES=""
BUNDLE_DESCRIPTION="Sandbox base bundle with a duplicate order"
BUNDLE

  derive_dup_order_base_ids() {
    ROOT_DIR="$sandbox"
    BUNDLE_FILE_CACHE=()
    BUNDLE_FILE_CACHE_LOADED=()
    BASE_BUNDLE_CATALOG_LOADED=()
    load_base_bundle_catalog
  }

  run derive_dup_order_base_ids
  [ "$status" -ne 0 ]
  assert_contains "$output" "Duplicate BUNDLE_BASE_ORDER '10'"
}

@test "dotfiles layering doc references only existing repository paths" {
  local doc="$ROOT_DIR/docs/dotfiles-layering.md"
  [ -f "$doc" ]

  local path
  while IFS= read -r path; do
    [[ "$path" == *'<'* || "$path" == *'*'* ]] && continue
    if [[ ! -e "$ROOT_DIR/$path" ]]; then
      printf 'docs/dotfiles-layering.md references missing path: %s\n' "$path" >&2
      return 1
    fi
  done < <(grep -oE '`(dotfiles|templates|config|bundles|lib|modules)/[^`]*`' "$doc" | tr -d '`' | sort -u)
}

@test "dotfiles layering doc seed rows exist in managed-config.tsv" {
  local policy="$ROOT_DIR/config/managed-config.tsv"
  local path
  for path in \
    '~/.config/ghostty/themes/noctalia' \
    '~/.config/niri/cfg/display.kdl' \
    '~/.config/niri/noctalia.kdl' \
    '~/.config/starship.toml'; do
    if ! awk -F'\t' -v p="$path" '$1==p && $2=="seed-if-missing" && $3=="preserve" {found=1} END {exit !found}' "$policy"; then
      printf 'missing seed-if-missing/preserve row for %s\n' "$path" >&2
      return 1
    fi
  done

  awk -F'\t' -v p='~/.config/noctalia/config.toml' '$1==p && $2=="stow" {found=1} END {exit !found}' "$policy"
}
