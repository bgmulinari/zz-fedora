#!/usr/bin/env bats
# zz-test-tags: smoke
#
# Catalog contract suite. Covers the TOML catalog validation contract
# enforced by lib/catalog.py over sandbox catalogs, the compiled-catalog
# access layer in lib/catalog.sh against the real repository catalog, and
# real-tree invariants that keep units, sources, choices, and dotfiles
# consistent.

load "helpers/common"

setup() {
  setup_test_env
  source_core
}

catalog_validate() {
  python3 "$ROOT_DIR/lib/catalog.py" --root "$1" validate
}

# write_catalog_file <sandbox> <relative-path-under-catalog/> reads the file
# body from stdin and creates parent directories as needed.
write_catalog_file() {
  local sandbox="$1"
  local rel="$2"
  mkdir -p "$sandbox/catalog/$(dirname "$rel")"
  cat >"$sandbox/catalog/$rel"
}

# Every sandbox catalog needs at least one valid unit for the units tree to
# exist; fixtures layer broken files on top of this baseline.
make_minimal_sandbox() {
  local sandbox="$1"
  write_catalog_file "$sandbox" units/misc/thing.toml <<'TOML'
id = "misc-thing"
description = "Minimal valid unit"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
}

# copy_repo_catalog_sandbox <sandbox> stages the real catalog plus the
# compiler so the Bash shim can be pointed at the sandbox via ROOT_DIR.
copy_repo_catalog_sandbox() {
  local sandbox="$1"
  mkdir -p "$sandbox/lib"
  cp -R "$ROOT_DIR/catalog" "$sandbox/catalog"
  cp "$ROOT_DIR/lib/catalog.py" "$sandbox/lib/catalog.py"
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

@test "a minimal valid catalog passes python validation" {
  local sandbox="$TEST_ROOT/sandbox-valid"
  make_minimal_sandbox "$sandbox"
  write_catalog_file "$sandbox" units/base/core.toml <<'TOML'
id = "base-core"
description = "Sandbox base unit"

[base]
order = 10
early = true
minimal_desktop_skip = true

[[install]]
backend = "dnf"
sources = ["vendor:test"]
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/pick.toml <<'TOML'
id = "misc-pick"
description = "Sandbox choice unit"

[choice]
category = "misc"
id = "pick"
label = "Pick"
default = true
order = 10
description = "Sandbox wizard choice"

[[install]]
backend = "flatpak"
sources = ["flatpak:test"]
flatpaks = ["org.example.Pick"]
TOML
  write_catalog_file "$sandbox" sources/vendor/test.toml <<'TOML'
id = "vendor:test"
kind = "vendor"
label = "Test vendor repository"
description = "Vendor repository fixture"
gpg_policy = "repo-gpg-key"
reason = "Test fixture"
TOML
  write_catalog_file "$sandbox" sources/flatpak/test.toml <<'TOML'
id = "flatpak:test"
kind = "flatpak"
label = "Test flatpak remote"
description = "Flatpak remote fixture"
gpg_policy = "flatpak-gpg"
reason = "Test fixture"
TOML

  run catalog_validate "$sandbox"
  [ "$status" -eq 0 ]
}

@test "catalog validation reports missing required keys" {
  local sandbox="$TEST_ROOT/sandbox-missing-keys"
  write_catalog_file "$sandbox" units/misc/nameless.toml <<'TOML'
[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" sources/vendor/incomplete.toml <<'TOML'
id = "vendor:incomplete"
kind = "vendor"
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "missing required key 'id'"
  assert_contains "$output" "missing required key 'description'"
  assert_contains "$output" "missing required key 'label'"
  assert_contains "$output" "missing required key 'gpg_policy'"
  assert_contains "$output" "missing required key 'reason'"
  assert_contains "$output" "catalog validation failed with"
}

@test "catalog validation rejects unknown keys in every table" {
  local sandbox="$TEST_ROOT/sandbox-unknown-keys"
  write_catalog_file "$sandbox" units/misc/top.toml <<'TOML'
id = "misc-top"
description = "Unit with an unknown top-level key"
frob_unit = 1

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/base-table.toml <<'TOML'
id = "misc-base-table"
description = "Base table with an unknown key"

[base]
order = 12
frob_base = true

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/choice-table.toml <<'TOML'
id = "misc-choice-table"
description = "Choice table with an unknown key"

[choice]
category = "misc"
id = "choice-table"
label = "Choice table"
description = "Choice fixture"
frob_choice = true

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/install-step.toml <<'TOML'
id = "misc-install-step"
description = "Install step with an unknown key"

[[install]]
backend = "dnf"
packages = ["hello"]
frob_install = true
TOML
  write_catalog_file "$sandbox" sources/vendor/stray.toml <<'TOML'
id = "vendor:stray"
kind = "vendor"
label = "Vendor with an unknown key"
description = "Source fixture"
gpg_policy = "repo-gpg-key"
reason = "Test fixture"
frob_source = true
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "unknown key 'frob_unit'"
  assert_contains "$output" "unknown key 'frob_base'"
  assert_contains "$output" "unknown key 'frob_choice'"
  assert_contains "$output" "unknown key 'frob_install'"
  assert_contains "$output" "unknown key 'frob_source'"
}

@test "install steps require a supported backend and a matching payload key" {
  local sandbox="$TEST_ROOT/sandbox-install-payloads"
  write_catalog_file "$sandbox" units/misc/dnf-with-flatpaks.toml <<'TOML'
id = "misc-dnf-with-flatpaks"
description = "dnf step carrying a flatpak payload"

[[install]]
backend = "dnf"
packages = ["hello"]
flatpaks = ["org.example.App"]
TOML
  write_catalog_file "$sandbox" units/misc/action-with-packages.toml <<'TOML'
id = "misc-action-with-packages"
description = "action step carrying a dnf payload"

[[install]]
backend = "action"
actions = ["docker"]
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/bad-backend.toml <<'TOML'
id = "misc-bad-backend"
description = "Unsupported backend"

[[install]]
backend = "brew"
TOML
  write_catalog_file "$sandbox" units/misc/empty-dnf.toml <<'TOML'
id = "misc-empty-dnf"
description = "dnf step with neither packages nor sources"

[[install]]
backend = "dnf"
TOML
  write_catalog_file "$sandbox" units/misc/empty-flatpak.toml <<'TOML'
id = "misc-empty-flatpak"
description = "flatpak step with neither flatpaks nor sources"

[[install]]
backend = "flatpak"
TOML
  write_catalog_file "$sandbox" units/misc/empty-action.toml <<'TOML'
id = "misc-empty-action"
description = "action step with neither actions nor sources"

[[install]]
backend = "action"
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "'flatpaks' is only valid for backend = \"flatpak\""
  assert_contains "$output" "'packages' is only valid for backend = \"dnf\""
  assert_contains "$output" "unsupported backend 'brew'"
  assert_contains "$output" "has no packages and no sources"
  assert_contains "$output" "has no flatpaks and no sources"
  assert_contains "$output" "has no actions and no sources"
}

@test "units require at least one install step" {
  local sandbox="$TEST_ROOT/sandbox-no-install"
  write_catalog_file "$sandbox" units/misc/absent.toml <<'TOML'
id = "misc-absent"
description = "Unit without any install table"
TOML
  write_catalog_file "$sandbox" units/misc/empty.toml <<'TOML'
id = "misc-empty"
description = "Unit with an empty install array"
install = []
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_equal "2" "$(grep -Fc "at least one [[install]] step is required" <<<"$output")"
}

@test "unit references to sources, requires, and also targets must resolve" {
  local sandbox="$TEST_ROOT/sandbox-references"
  write_catalog_file "$sandbox" units/misc/dangling.toml <<'TOML'
id = "misc-dangling"
description = "Unit with unresolved references"
requires = ["misc-nope"]

[[install]]
backend = "dnf"
sources = ["vendor:missing"]
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/basement.toml <<'TOML'
id = "misc-basement"
description = "Base unit that a choice tries to select"

[base]
order = 10

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/chooser.toml <<'TOML'
id = "misc-chooser"
description = "Choice with invalid also targets"

[choice]
category = "misc"
id = "chooser"
label = "Chooser"
description = "Choice fixture"
also = ["misc-ghost", "misc-basement"]

[[install]]
backend = "dnf"
packages = ["hello"]
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "unknown source id 'vendor:missing'"
  assert_contains "$output" "unknown required unit 'misc-nope'"
  assert_contains "$output" "unknown unit 'misc-ghost' in [choice] also"
  assert_contains "$output" "base unit 'misc-basement' must not be selected by a choice"
}

@test "duplicate unit ids and duplicate base orders fail validation" {
  local sandbox="$TEST_ROOT/sandbox-duplicates"
  write_catalog_file "$sandbox" units/misc/first.toml <<'TOML'
id = "misc-dup"
description = "First unit claiming the id"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/second.toml <<'TOML'
id = "misc-dup"
description = "Second unit claiming the id"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/order-a.toml <<'TOML'
id = "misc-order-a"
description = "First unit claiming base order 11"

[base]
order = 11

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/order-b.toml <<'TOML'
id = "misc-order-b"
description = "Second unit claiming base order 11"

[base]
order = 11

[[install]]
backend = "dnf"
packages = ["hello"]
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "duplicate unit id 'misc-dup'"
  assert_contains "$output" "duplicate base order 11"
}

@test "a unit cannot declare both base and choice tables" {
  local sandbox="$TEST_ROOT/sandbox-base-choice"
  write_catalog_file "$sandbox" units/misc/both.toml <<'TOML'
id = "misc-both"
description = "Unit declaring base and choice together"

[base]
order = 10

[choice]
category = "misc"
id = "both"
label = "Both"
description = "Choice fixture"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "a unit cannot declare both [base] and [choice]"
}

@test "units under catalog/units/base/ must declare a base table" {
  local sandbox="$TEST_ROOT/sandbox-baseless"
  make_minimal_sandbox "$sandbox"
  write_catalog_file "$sandbox" units/base/optionalish.toml <<'TOML'
id = "base-optionalish"
description = "Base-tree unit missing its base table"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "units under catalog/units/base/ must declare a [base] table"
}

@test "source project is required for copr and artifact kinds and forbidden elsewhere" {
  local sandbox="$TEST_ROOT/sandbox-project-scope"
  make_minimal_sandbox "$sandbox"
  write_catalog_file "$sandbox" sources/copr/no-project.toml <<'TOML'
id = "copr:test/no-project"
kind = "copr"
label = "COPR without a project"
description = "COPR fixture missing project"
gpg_policy = "copr-plugin"
reason = "Test fixture"
TOML
  write_catalog_file "$sandbox" sources/artifact/no-project.toml <<'TOML'
id = "artifact:no-project"
kind = "artifact"
label = "Artifact without a project"
description = "Artifact fixture missing project"
gpg_policy = "pinned-commit"
reason = "Test fixture"
TOML
  write_catalog_file "$sandbox" sources/vendor/stray-project.toml <<'TOML'
id = "vendor:stray-project"
kind = "vendor"
label = "Vendor with a stray project"
project = "acme/stray"
description = "Vendor fixture declaring project"
gpg_policy = "repo-gpg-key"
reason = "Test fixture"
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "'project' is required for copr sources"
  assert_contains "$output" "'project' is required for artifact sources"
  assert_contains "$output" "'project' is only valid for copr and artifact sources"
}

@test "source trust metadata rejects invalid kinds and policies" {
  local sandbox="$TEST_ROOT/sandbox-trust"
  make_minimal_sandbox "$sandbox"
  write_catalog_file "$sandbox" sources/terra/no-exception.toml <<'TOML'
id = "terra-fixture"
kind = "terra"
label = "Terra without a bootstrap exception"
description = "Terra fixture"
gpg_policy = "unsigned-bootstrap"
reason = "Test fixture"
TOML
  write_catalog_file "$sandbox" sources/vendor/bad-policy.toml <<'TOML'
id = "vendor:bad-policy"
kind = "vendor"
label = "Vendor with a made-up policy"
description = "Vendor fixture"
gpg_policy = "gpgville"
reason = "Test fixture"
TOML
  write_catalog_file "$sandbox" sources/vendor/bad-kind.toml <<'TOML'
id = "vendor:bad-kind"
kind = "brew"
label = "Source with a made-up kind"
description = "Vendor fixture"
gpg_policy = "repo-gpg-key"
reason = "Test fixture"
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "unsigned-bootstrap sources must set bootstrap_exception = true"
  assert_contains "$output" "invalid gpg_policy 'gpgville'"
  assert_contains "$output" "unsupported source kind 'brew'"
}

@test "choice ids are unique per category and default must be a boolean" {
  local sandbox="$TEST_ROOT/sandbox-choice-ids"
  write_catalog_file "$sandbox" units/misc/dup-a.toml <<'TOML'
id = "misc-dup-a"
description = "First unit claiming the choice id"

[choice]
category = "misc"
id = "dup"
label = "Dup A"
description = "Choice fixture"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/dup-b.toml <<'TOML'
id = "misc-dup-b"
description = "Second unit claiming the choice id"

[choice]
category = "misc"
id = "dup"
label = "Dup B"
description = "Choice fixture"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/bad-default.toml <<'TOML'
id = "misc-bad-default"
description = "Choice with a non-boolean default"

[choice]
category = "misc"
id = "bad-default"
label = "Bad default"
default = 2
description = "Choice fixture"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "duplicate choice 'dup' in category 'misc'"
  assert_contains "$output" "'default' must be a boolean"
}

@test "choice categories reject names reserved as runtime aliases" {
  local sandbox="$TEST_ROOT/sandbox-choice-category-aliases"
  write_catalog_file "$sandbox" units/misc/browser.toml <<'TOML'
id = "misc-browser"
description = "Choice using the singular browser alias"

[choice]
category = "browser"
id = "browser"
label = "Browser"
description = "Choice fixture"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/source.toml <<'TOML'
id = "misc-source"
description = "Choice using the singular source alias"

[choice]
category = "source"
id = "source"
label = "Source"
description = "Choice fixture"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "category 'browser' is a runtime alias; use 'browsers'"
  assert_contains "$output" "category 'source' is a runtime alias; use 'sources'"
}

@test "catalog strings must not contain tabs or newlines" {
  local sandbox="$TEST_ROOT/sandbox-clean-strings"
  write_catalog_file "$sandbox" units/misc/tabby.toml <<'TOML'
id = "misc-tabby"
description = "tab\there"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML
  write_catalog_file "$sandbox" units/misc/multiline.toml <<'TOML'
id = "misc-multiline"
description = "Choice label with a newline"

[choice]
category = "misc"
id = "multiline"
label = "Line\nbreak"
description = "Choice fixture"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML

  run catalog_validate "$sandbox"
  [ "$status" -ne 0 ]
  assert_contains "$output" "'description' must not contain tabs or newlines"
  assert_contains "$output" "'label' must not contain tabs or newlines"
}

@test "load_source_descriptor maps compiled source fields" {
  load_source_descriptor vendor:brave
  assert_equal "vendor:brave" "$SOURCE_ID"
  assert_equal "vendor" "$SOURCE_KIND"
  assert_equal "Brave Browser RPM Repository" "$SOURCE_LABEL"
  assert_equal "" "$SOURCE_PROJECT"
  assert_equal "0" "$SOURCE_REQUIRED"
  assert_equal "repo-gpg-key" "$SOURCE_GPG_POLICY"
  assert_equal "0" "$SOURCE_BOOTSTRAP_EXCEPTION"
  assert_equal "Official Brave RPM repository" "$SOURCE_DESCRIPTION"
  assert_equal "Provides optional Brave browser package" "$SOURCE_REASON"

  load_source_descriptor copr:atim/starship
  assert_equal "copr" "$SOURCE_KIND"
  assert_equal "atim/starship" "$SOURCE_PROJECT"
  assert_equal "1" "$SOURCE_REQUIRED"
  assert_equal "copr-plugin" "$SOURCE_GPG_POLICY"

  run load_source_descriptor no-such-source
  [ "$status" -ne 0 ]
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

@test "load_bundle_descriptor maps compiled unit fields" {
  load_bundle_descriptor browsers-brave
  assert_equal "browsers-brave" "$BUNDLE_ID"
  assert_equal "0" "$BUNDLE_BASE"
  assert_equal "" "$BUNDLE_BASE_ORDER"
  assert_equal "0" "$BUNDLE_BASE_EARLY"
  assert_equal "0" "$BUNDLE_MINIMAL_DESKTOP_SKIP"
  assert_equal "" "$BUNDLE_DEPENDENCIES"
  assert_equal "vendor:brave" "$BUNDLE_SOURCE_IDS"
  assert_equal "" "$BUNDLE_CONFIG_COMPONENTS"
  assert_equal "dnf" "$BUNDLE_BACKENDS"
  assert_equal "Brave browser bundle for Fedora" "$BUNDLE_DESCRIPTION"

  load_bundle_descriptor base-bootstrap
  assert_equal "1" "$BUNDLE_BASE"
  assert_equal "10" "$BUNDLE_BASE_ORDER"
  assert_equal "1" "$BUNDLE_BASE_EARLY"
  assert_equal "core,shell" "$BUNDLE_CONFIG_COMPONENTS"

  load_bundle_descriptor browsers-firefox
  assert_equal "browsers-firefox-pywalfox" "$BUNDLE_DEPENDENCIES"

  bundle_exists browsers-brave
  run bundle_exists no-such-bundle
  [ "$status" -ne 0 ]
  run load_bundle_descriptor no-such-bundle
  [ "$status" -ne 0 ]
}

@test "bundle steps expose backend, sources, and payload items per step" {
  assert_equal $'0\tdnf\tvendor:brave' "$(bundle_steps browsers-brave)"
  assert_equal "brave-browser" "$(bundle_step_items browsers-brave 0)"
  assert_equal "brave-browser" "$(bundle_items browsers-brave)"

  assert_equal $'0\tflatpak\tflathub' "$(bundle_steps office-pinta)"
  assert_equal "com.github.PintaProject.Pinta" "$(bundle_step_items office-pinta 0)"

  assert_equal $'0\taction\tartifact:claude-code' "$(bundle_steps ai-claude-code)"
  assert_equal "claude-code" "$(bundle_step_items ai-claude-code 0)"
}

@test "a multi-step sandbox unit exposes ordered steps and a backend union" {
  local sandbox="$TEST_ROOT/sandbox-multi-step"
  mkdir -p "$sandbox/lib"
  cp "$ROOT_DIR/lib/catalog.py" "$sandbox/lib/catalog.py"
  write_catalog_file "$sandbox" units/misc/multi.toml <<'TOML'
id = "misc-multi"
description = "Two-step unit crossing backends"

[[install]]
backend = "dnf"
packages = ["zebra", "apple"]

[[install]]
backend = "flatpak"
flatpaks = ["org.example.App"]
TOML

  local original_root="$ROOT_DIR"
  ROOT_DIR="$sandbox"
  catalog_reset_cache

  load_bundle_descriptor misc-multi
  assert_equal "dnf,flatpak" "$BUNDLE_BACKENDS"
  assert_equal $'0\tdnf\t\n1\tflatpak\t' "$(bundle_steps misc-multi)"
  assert_equal $'apple\nzebra' "$(bundle_step_items misc-multi 0)"
  assert_equal "org.example.App" "$(bundle_step_items misc-multi 1)"
  assert_equal $'apple\norg.example.App\nzebra' "$(bundle_items misc-multi)"

  ROOT_DIR="$original_root"
  catalog_reset_cache
}

@test "a new catalog base unit joins the derived base set at its declared order" {
  local sandbox="$TEST_ROOT/sandbox-base-order"
  copy_repo_catalog_sandbox "$sandbox"
  write_catalog_file "$sandbox" units/base/zz-test.toml <<'TOML'
id = "base-zz-test"
description = "Sandbox base unit for derivation tests"

[base]
order = 15

[[install]]
backend = "dnf"
packages = ["hello"]
TOML

  local original_root="$ROOT_DIR"
  ROOT_DIR="$sandbox"
  catalog_reset_cache
  catalog_ensure_loaded

  assert_equal "base-bootstrap" "${BASE_BUNDLE_IDS[0]}"
  assert_equal "base-zz-test" "${BASE_BUNDLE_IDS[1]}"
  assert_equal "base-source-rpmfusion-free" "${BASE_BUNDLE_IDS[2]}"
  array_contains base-bootstrap "${EARLY_BASE_BUNDLE_IDS[@]}"

  ROOT_DIR="$original_root"
  catalog_reset_cache
}

@test "catalog_ensure_loaded dies when the catalog fails validation" {
  local sandbox="$TEST_ROOT/sandbox-invalid-load"
  copy_repo_catalog_sandbox "$sandbox"
  write_catalog_file "$sandbox" units/base/zz-test.toml <<'TOML'
id = "base-zz-test"
description = "Sandbox base unit missing its base table"

[[install]]
backend = "dnf"
packages = ["hello"]
TOML

  load_invalid_sandbox() {
    ROOT_DIR="$sandbox"
    catalog_reset_cache
    catalog_ensure_loaded
  }

  run load_invalid_sandbox
  [ "$status" -ne 0 ]
  assert_contains "$output" "units under catalog/units/base/ must declare a [base] table"
  assert_contains "$output" "Catalog validation failed"
}

@test "compiled catalog directories are isolated between Bash processes" {
  local current_dir child_dir
  current_dir="$(catalog_compiled_dir)"
  child_dir="$({
    CACHE_DIR="$CACHE_DIR" ROOT_DIR="$ROOT_DIR" bash -c '
      set -Eeuo pipefail
      source "$ROOT_DIR/lib/catalog.sh"
      catalog_compiled_dir
    '
  })"

  [[ "$current_dir" == "$CACHE_DIR"/catalog-compiled.* ]]
  [[ "$child_dir" == "$CACHE_DIR"/catalog-compiled.* ]]
  [ "$current_dir" != "$child_dir" ]
}

@test "catalog_validate_action_items passes on the repository catalog" {
  catalog_ensure_loaded
  [ "${#CATALOG_ACTION_ITEMS[@]}" -gt 0 ]
  array_contains docker "${CATALOG_ACTION_ITEMS[@]}"
  catalog_validate_action_items
}

@test "catalog_validate_action_items rejects unregistered action payloads" {
  local sandbox="$TEST_ROOT/sandbox-bad-action"
  mkdir -p "$sandbox/lib"
  cp "$ROOT_DIR/lib/catalog.py" "$sandbox/lib/catalog.py"
  write_catalog_file "$sandbox" units/misc/bad-action.toml <<'TOML'
id = "misc-bad-action"
description = "Payload referencing an unregistered action"

[[install]]
backend = "action"
actions = ["not-a-registered-action"]
TOML

  validate_sandbox_actions() {
    ROOT_DIR="$sandbox"
    catalog_reset_cache
    catalog_validate_action_items
  }

  run validate_sandbox_actions
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown custom action 'not-a-registered-action'"
}

@test "choice_field splits compiled rows preserving empty fields" {
  assert_equal "empty" "$(choice_field $'empty\tEmpty choice\t0\t\tNo units required' 1)"
  assert_equal "" "$(choice_field $'empty\tEmpty choice\t0\t\tNo units required' 4)"
  assert_equal "No units required" "$(choice_field $'empty\tEmpty choice\t0\t\tNo units required' 5)"
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

  record="$(choice_record gaming steam)"
  assert_equal "gaming-steam-free,gaming-steam-nonfree" "$(choice_field "$record" 4)"

  assert_equal "" "$(choice_record ai no-such-choice)"
}

@test "normal installer defaults to every optional choice except Firefox-only browsers" {
  local category
  assert_equal "firefox" "$(default_choice_ids browsers)"
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

@test "unit ids are unique, non-empty, and round-trip through their compiled rows" {
  local unit_file_count id_count unique_count bundle_id
  unit_file_count="$(find "$ROOT_DIR/catalog/units" -type f -name '*.toml' | wc -l | tr -d ' ')"
  id_count="$(list_bundle_ids | wc -l | tr -d ' ')"
  unique_count="$(list_bundle_ids | sort -u | wc -l | tr -d ' ')"

  [ "$id_count" -gt 0 ]
  assert_equal "$unit_file_count" "$id_count"
  assert_equal "$id_count" "$unique_count"

  while IFS= read -r bundle_id; do
    [[ -n "$bundle_id" ]]
    load_bundle_descriptor "$bundle_id"
    assert_equal "$bundle_id" "$BUNDLE_ID"
    [[ -n "$BUNDLE_DESCRIPTION" ]]
  done < <(list_bundle_ids)
}

@test "base membership derives from unit metadata and stays out of wizard choices" {
  catalog_ensure_loaded
  [ "${#BASE_BUNDLE_IDS[@]}" -gt 0 ]

  local bundle_id base_count=0
  while IFS= read -r bundle_id; do
    load_bundle_descriptor "$bundle_id"
    [[ "$BUNDLE_BASE" == "1" ]] && base_count=$((base_count + 1))
  done < <(list_bundle_ids)
  assert_equal "$base_count" "${#BASE_BUNDLE_IDS[@]}"

  for bundle_id in "${BASE_BUNDLE_IDS[@]}"; do
    load_bundle_descriptor "$bundle_id"
    assert_equal "1" "$BUNDLE_BASE"
    [[ -n "$BUNDLE_BASE_ORDER" ]]
  done
  for bundle_id in "${EARLY_BASE_BUNDLE_IDS[@]}"; do
    array_contains "$bundle_id" "${BASE_BUNDLE_IDS[@]}"
  done
  for bundle_id in "${MINIMAL_DESKTOP_SKIP_BUNDLE_IDS[@]}"; do
    array_contains "$bundle_id" "${BASE_BUNDLE_IDS[@]}"
  done

  local category units_csv unit_id _choice_id _label _default _description
  for category in $(category_names); do
    while IFS=$'\t' read -r _choice_id _label _default units_csv _description; do
      [[ -n "$_choice_id" ]] || continue
      while IFS= read -r unit_id; do
        load_bundle_descriptor "$unit_id"
        assert_equal "0" "$BUNDLE_BASE"
      done < <(split_csv "$units_csv")
    done <"$(choice_catalog_path "$category")"
  done
}

@test "every managed config component is referenced by a catalog unit" {
  local bundle_id component referenced=$'\n' known=$'\n'

  while IFS= read -r component; do
    known+="${component}"$'\n'
  done < <(awk -F'\t' '$1 !~ /^#/ && $1 != "" {print $1}' "$ROOT_DIR/config/managed-config.tsv" | sort -u)

  while IFS= read -r bundle_id; do
    load_bundle_descriptor "$bundle_id"
    [[ -n "$BUNDLE_CONFIG_COMPONENTS" ]] || continue
    while IFS= read -r component; do
      if [[ "$known" != *$'\n'"$component"$'\n'* ]]; then
        printf 'unit %s references unknown managed config component: %s\n' "$bundle_id" "$component" >&2
        return 1
      fi
      referenced+="${component}"$'\n'
    done < <(split_csv "$BUNDLE_CONFIG_COMPONENTS")
  done < <(list_bundle_ids)

  while IFS= read -r component; do
    if [[ "$referenced" != *$'\n'"$component"$'\n'* ]]; then
      printf 'orphan managed config component not referenced by any unit: %s\n' "$component" >&2
      return 1
    fi
  done < <(awk -F'\t' '$1 !~ /^#/ && $1 != "" {print $1}' "$ROOT_DIR/config/managed-config.tsv" | sort -u)
}

@test "source id catalog contains each descriptor exactly once" {
  local expected_count actual_count unique_count
  expected_count="$(find "$ROOT_DIR/catalog/sources" -type f -name '*.toml' | wc -l | tr -d ' ')"
  actual_count="$(list_source_ids | wc -l | tr -d ' ')"
  unique_count="$(list_source_ids | sort -u | wc -l | tr -d ' ')"

  assert_equal "$expected_count" "$actual_count"
  assert_equal "$actual_count" "$unique_count"
}

@test "every source carries complete trust metadata" {
  local source_id
  while IFS= read -r source_id; do
    load_source_descriptor "$source_id"
    [[ -n "$SOURCE_KIND" ]]
    [[ -n "$SOURCE_LABEL" ]]
    [[ -n "$SOURCE_DESCRIPTION" ]]
    [[ -n "$SOURCE_GPG_POLICY" ]]
    [[ -n "$SOURCE_REASON" ]]
    [[ "$SOURCE_REQUIRED" == "0" || "$SOURCE_REQUIRED" == "1" ]]
    [[ "$SOURCE_BOOTSTRAP_EXCEPTION" == "0" || "$SOURCE_BOOTSTRAP_EXCEPTION" == "1" ]]
    case "$SOURCE_KIND" in
      copr | artifact)
        [[ -n "$SOURCE_PROJECT" ]]
        ;;
      *)
        [[ -z "$SOURCE_PROJECT" ]]
        ;;
    esac
  done < <(list_source_ids)

  load_source_descriptor terra
  assert_equal "unsigned-bootstrap" "$SOURCE_GPG_POLICY"
  assert_equal "1" "$SOURCE_BOOTSTRAP_EXCEPTION"
}

@test "choice descriptions explain purpose without package source wording" {
  local category choice_id label default_flag units_csv description
  for category in $(category_names); do
    while IFS=$'\t' read -r choice_id label default_flag units_csv description; do
      [[ -n "$choice_id" ]] || continue
      if grep -Eiq '(RPM|COPR|Flatpak|Flathub|Homebrew|Fedora|repository)' <<<"$description"; then
        printf 'package source wording in %s description: %s\n' "$choice_id" "$description" >&2
        return 1
      fi
    done <"$(choice_catalog_path "$category")"
  done
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
  done < <(grep -oE '`(dotfiles|templates|config|catalog|lib|modules)/[^`]*`' "$doc" | tr -d '`' | sort -u)
}

@test "dotfiles layering doc seed rows exist in managed-config.tsv" {
  local policy="$ROOT_DIR/config/managed-config.tsv"
  local path
  for path in \
    '~/.config/ghostty/themes/noctalia' \
    '~/.config/niri/cfg/display.kdl' \
    '~/.config/niri/noctalia.kdl' \
    '~/.config/starship.toml'; do
    if ! awk -F'\t' -v p="$path" '$2==p && $3=="seed-if-missing" && $4=="preserve" {found=1} END {exit !found}' "$policy"; then
      printf 'missing seed-if-missing/preserve row for %s\n' "$path" >&2
      return 1
    fi
  done

  awk -F'\t' -v p='~/.config/noctalia/config.toml' '$2==p && $3=="seed-if-missing" {found=1} END {exit !found}' "$policy"
}
