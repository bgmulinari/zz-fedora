#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
  setup_fake_bin
  source_core
  source_modules
  # shellcheck source=../lib/choices.sh
  source "$ROOT_DIR/lib/choices.sh"
  TARGET_USER="$(id -un)"
  TARGET_HOME="$TEST_ROOT/home"
  PREFERRED_BROWSER="firefox"
}

# A saved selection file with the given category overrides, the way a
# finished install leaves one.
save_test_selections() {
  local selection category values
  reset_test_selections
  for selection in "$@"; do
    category="${selection%%=*}"
    values="${selection#*=}"
    set_category_override "$category" "$values"
  done
  save_selections
}

# The steps a real change runs that a test cannot: package transactions and
# the configuration convergence. Selections and plans are still real.
stub_apply_steps() {
  apply_units_focused() { printf 'APPLY: %s\n' "$*"; }
  module_60_user_config() { :; }
  module_80_post_actions() { :; }
  run_cmd_as_root() { printf 'ROOT: %s\n' "$*"; }
  # Session commands are recorded in a file too: the shell probes discard
  # their output.
  run_cmd_as_user() { shift; printf 'USER: %s\n' "$*" | tee -a "$TEST_ROOT/user-commands.log"; }
  run_user_login_shell() { printf 'USER-SHELL: %s\n' "$1"; }
  fedora_package_installed() { return 0; }
  fedora_package_dependents() { :; }
  choice_item_present() { return 0; }
}

@test "choice references resolve by bare id, category/id, and category=id" {
  run resolve_choice_ref zed
  [ "$status" -eq 0 ]
  assert_equal $'dev\tzed' "$output"

  run resolve_choice_ref browsers/brave
  [ "$status" -eq 0 ]
  assert_equal $'browsers\tbrave' "$output"

  run resolve_choice_ref office=pinta
  [ "$status" -eq 0 ]
  assert_equal $'office\tpinta' "$output"

  run resolve_choice_ref browser/brave
  [ "$status" -eq 0 ]
  assert_equal $'browsers\tbrave' "$output"

  run resolve_choice_ref does-not-exist
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown choice 'does-not-exist'"

  run resolve_choice_ref dev/pinta
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown choice 'pinta' in category 'dev'"
}

@test "add-choice dry run applies only the new choice's units and leaves the saved selections alone" {
  save_test_selections "dev=vscode" "browsers=firefox"
  load_saved_selections
  parse_select_arg dev=zed
  COMMAND=add-choice
  DRY_RUN=1

  run run_without_bats_debug_trap apply_choice_additions
  [ "$status" -eq 0 ]
  local applied="$output"
  assert_contains "$applied" "Adding Development choice: Zed"
  assert_contains "$applied" "Installing units: dev-zed"
  run grep -E 'dnf install .* zed$' <<<"$applied"
  [ "$status" -eq 0 ]
  # The focused transaction carries the new unit only, not the rest of the
  # saved selection.
  run grep -E 'dnf install .* code$' <<<"$applied"
  [ "$status" -ne 0 ]
  assert_file_contains "$SAVED_SELECTIONS" "select.dev=vscode"
  refute_saved_choice dev zed
  # The full plan is what remains in the plan directory afterwards.
  assert_plan_has "$PLAN_DIR/bundles.list" "dev-vscode"
  assert_plan_has "$PLAN_DIR/bundles.list" "dev-zed"
}

@test "add-choice saves the enlarged selection and skips units the base already carries" {
  save_test_selections "dev=vscode"
  load_saved_selections
  parse_select_arg dev=zed
  COMMAND=add-choice
  DRY_RUN=0
  stub_apply_steps

  run run_without_bats_debug_trap apply_choice_additions
  [ "$status" -eq 0 ]
  assert_contains "$output" "APPLY: dev-zed"
  assert_file_contains "$SAVED_SELECTIONS" "select.dev=vscode,zed"
  assert_file_contains "$SAVED_SELECTIONS" "preferred_browser=firefox"

  # An unknown choice is refused before anything runs.
  load_saved_selections
  parse_select_arg dev=nope
  run run_without_bats_debug_trap apply_choice_additions
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown choice 'nope' in category 'dev'"

  # A change that fails before its units are in place is not remembered as
  # done: zz update zz never installs optional software on its own.
  save_test_selections "dev=vscode"
  load_saved_selections
  parse_select_arg dev=lazydocker
  apply_units_focused() { return 1; }
  run run_without_bats_debug_trap apply_choice_additions
  [ "$status" -ne 0 ]
  assert_file_contains "$SAVED_SELECTIONS" "select.dev=vscode"
  refute_saved_choice dev lazydocker
}

@test "remove-choice uninstalls a tap-qualified Homebrew formula" {
  save_test_selections "media=codecs,cliamp"
  load_saved_selections
  parse_select_arg media=cliamp
  COMMAND=remove-choice
  DRY_RUN=0
  stub_apply_steps

  run run_without_bats_debug_trap apply_choice_removals
  [ "$status" -eq 0 ]
  assert_contains "$output" "Removing Media choice: cliamp"
  assert_contains "$output" "USER-SHELL: brew list 'bjarneo/cliamp/cliamp' >/dev/null 2>&1 && brew uninstall 'bjarneo/cliamp/cliamp' || true"
  refute_contains "$output" "Left in place"
  assert_file_contains "$SAVED_SELECTIONS" "select.media=codecs"
  refute_saved_choice media cliamp
}

@test "remove-choice keeps a package that installed software outside the choice still needs" {
  save_test_selections "media=codecs,cliamp"
  load_saved_selections
  parse_select_arg media=cliamp
  COMMAND=remove-choice
  DRY_RUN=0
  stub_apply_steps
  fedora_package_dependents() {
    [[ "$1" == "gcc" ]] && printf 'gcc-c++\nannobin-plugin-gcc\n'
    return 0
  }

  run run_without_bats_debug_trap apply_choice_removals
  [ "$status" -eq 0 ]
  assert_contains "$output" "Keeping package still needed by gcc-c++, annobin-plugin-gcc: gcc"
  refute_contains "$output" "dnf remove"
  # The formula itself still leaves.
  assert_contains "$output" "brew uninstall 'bjarneo/cliamp/cliamp'"
  refute_saved_choice media cliamp
}

@test "dependency pruning keeps a chain that ends in installed software outside the set" {
  # c (outside the set) needs b, b needs a, and a needs lone: once b stays
  # for c, a stays for b and lone stays for a, so nothing leaves.
  fedora_package_dependents() {
    case "$1" in
      a) printf 'b\n' ;;
      b) printf 'c\n' ;;
      lone) printf 'a\n' ;;
    esac
    return 0
  }
  local -a removals=(a b lone)

  run_without_bats_debug_trap prune_dependent_package_removals removals

  assert_equal "0" "${#removals[@]}"

  # Without the outside dependent the whole chain leaves together.
  fedora_package_dependents() {
    case "$1" in
      a) printf 'b\n' ;;
      lone) printf 'a\n' ;;
    esac
    return 0
  }
  removals=(a b lone)
  run_without_bats_debug_trap prune_dependent_package_removals removals
  assert_equal "a b lone" "${removals[*]}"

  removals=(a b)
  fedora_package_dependents() { [[ "$1" == "a" ]] && printf 'b\n'; return 0; }
  run_without_bats_debug_trap prune_dependent_package_removals removals
  assert_equal "a b" "${removals[*]}"

  removals=(a)
  fedora_package_dependents() { printf 'z\n'; }
  run_without_bats_debug_trap prune_dependent_package_removals removals
  assert_equal "0" "${#removals[@]}"

  # An arch-qualified spec in the set still counts as leaving.
  removals=(a.x86_64 b)
  fedora_package_dependents() { [[ "$1" == "b" ]] && printf 'a\n'; return 0; }
  run_without_bats_debug_trap prune_dependent_package_removals removals
  assert_equal "a.x86_64 b" "${removals[*]}"
}

@test "installed dependents are read from rpm's test removal" {
  setup_fake_bin
  write_fake_command rpm <<'EOF2'
#!/usr/bin/env bash
[[ "$*" == "-e --test --allmatches gcc" ]] || exit 1
cat >&2 <<'MSG'
error: Failed dependencies:
	gcc = 16.2.1-2.fc44 is needed by (installed) gcc-c++-16.2.1-2.fc44.x86_64
	gcc is needed by (installed) annobin-plugin-gcc-12.99-1.fc44.x86_64
	gcc is needed by (installed) gcc-c++-16.2.1-2.fc44.x86_64
MSG
exit 1
EOF2
  PATH="$FAKE_BIN:$PATH"

  run fedora_package_dependents gcc
  [ "$status" -eq 0 ]
  assert_equal $'annobin-plugin-gcc\ngcc-c++' "$output"

  write_fake_command rpm <<'EOF2'
#!/usr/bin/env bash
exit 0
EOF2
  run fedora_package_dependents gcc
  [ "$status" -eq 0 ]
  assert_equal "" "$output"
}

@test "remove-choice removes what no remaining choice needs and unsaves the choice" {
  save_test_selections "office=onlyoffice,pinta" "dotnet=sdk,ef" "ai=agent-usage" "dev=lazydocker"
  load_saved_selections
  parse_select_arg office=pinta
  parse_select_arg dotnet=sdk
  parse_select_arg ai=agent-usage
  parse_select_arg dev=lazydocker
  COMMAND=remove-choice
  DRY_RUN=0
  stub_apply_steps

  run run_without_bats_debug_trap apply_choice_removals
  [ "$status" -eq 0 ]
  assert_contains "$output" "Removing Office choice: Pinta"
  assert_contains "$output" "ROOT: flatpak uninstall -y com.github.PintaProject.Pinta"
  refute_contains "$output" "org.onlyoffice.desktopeditors"
  # The SDK unit stays because the EF Core tool choice still requires it.
  assert_contains "$output" "Keeping unit still selected elsewhere: dotnet-sdk"
  # Base packages never leave with a choice: python3 runs the installer.
  assert_contains "$output" "Keeping package still planned: python3"
  refute_contains "$output" "dnf remove"
  # Homebrew actions have a removal; the plugin is unloaded from the shell
  # before its product link goes.
  assert_contains "$output" "USER-SHELL: brew list 'lazydocker' >/dev/null 2>&1 && brew uninstall 'lazydocker' || true"
  assert_file_contains "$TEST_ROOT/user-commands.log" "USER: dms ipc call plugins disable agentUsage"
  assert_file_contains "$SAVED_SELECTIONS" "select.office=onlyoffice"
  assert_file_contains "$SAVED_SELECTIONS" "select.dotnet=ef"
  assert_file_contains "$SAVED_SELECTIONS" "select.ai="
  refute_saved_choice office pinta
  refute_saved_choice dev lazydocker
  refute_plan_has "$PLAN_DIR/bundles.list" "office-pinta"
  assert_plan_has "$PLAN_DIR/bundles.list" "dotnet-sdk"
}

@test "remove-choice drops the docker group for Sudoless Docker while the engine choice stays" {
  save_test_selections "dev=docker,docker-sudoless"
  load_saved_selections
  parse_select_arg dev=docker-sudoless
  COMMAND=remove-choice
  DRY_RUN=0
  stub_apply_steps
  docker_group_member() { return 0; }

  run run_without_bats_debug_trap apply_choice_removals
  [ "$status" -eq 0 ]
  assert_contains "$output" "ROOT: gpasswd -d $TARGET_USER docker"
  assert_contains "$output" "Keeping unit still selected elsewhere: dev-docker"
  refute_contains "$output" "Left in place, no automatic removal exists for: action docker-group"
  assert_file_contains "$SAVED_SELECTIONS" "select.dev=docker"
  refute_saved_choice dev docker-sudoless
  assert_plan_has "$PLAN_DIR/actions/actions.list" "docker-post-install"
  refute_plan_has "$PLAN_DIR/actions/actions.list" "docker-group"
}

@test "remove-choice uninstalls a .NET global tool while the SDK choice stays" {
  save_test_selections "dotnet=sdk,ef,powershell"
  load_saved_selections
  parse_select_arg dotnet=ef
  COMMAND=remove-choice
  DRY_RUN=0
  stub_apply_steps
  mkdir -p "$TARGET_HOME/.dotnet"
  printf '#!/usr/bin/env bash\n' >"$TARGET_HOME/.dotnet/dotnet"
  chmod +x "$TARGET_HOME/.dotnet/dotnet"

  run run_without_bats_debug_trap apply_choice_removals
  [ "$status" -eq 0 ]
  assert_contains "$output" "USER: $TARGET_HOME/.dotnet/dotnet tool uninstall -g dotnet-ef"
  refute_contains "$output" "tool uninstall -g powershell"
  assert_contains "$output" "Keeping unit still selected elsewhere: dotnet-sdk"
  refute_contains "$output" "Left in place, no automatic removal exists for"
  assert_file_contains "$SAVED_SELECTIONS" "select.dotnet=sdk,powershell"
  refute_file_contains "$SAVED_SELECTIONS" "select.dotnet=sdk,ef"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-sdk"
  assert_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-tool:powershell"
  refute_plan_has "$PLAN_DIR/actions/actions.list" "dotnet-tool:dotnet-ef"
}

@test "remove-choice reports actions without a removal and clears a removed preferred browser" {
  save_test_selections "browsers=firefox,brave" "dev=docker"
  load_saved_selections
  parse_select_arg browsers=firefox
  parse_select_arg dev=docker
  COMMAND=remove-choice
  DRY_RUN=1

  run run_without_bats_debug_trap apply_choice_removals
  [ "$status" -eq 0 ]
  local removed="$output"
  assert_contains "$removed" "Removing the preferred browser"
  assert_contains "$removed" "Left in place, no automatic removal exists for: action docker"
  run grep -E 'dnf remove -y .*firefox' <<<"$removed"
  [ "$status" -eq 0 ]
  assert_contains "$removed" "Run zz defaults"
  # Dry run: the saved selections are untouched.
  assert_file_contains "$SAVED_SELECTIONS" "select.browsers=firefox,brave"
  assert_file_contains "$SAVED_SELECTIONS" "preferred_browser=firefox"
}

@test "installed state matches a tap-qualified Homebrew action by its bare formula name" {
  # brew list prints bare names; priming is faked so no package tool runs.
  CHOICE_STATE_PRIMED=1
  INSTALLED_BREW_FORMULAE[cliamp]=1
  INSTALLED_RPM_NAMES[gcc]=1

  run action_present "brew:bjarneo/cliamp/cliamp"
  [ "$status" -eq 0 ]
  run action_present "brew:bjarneo/cliamp/missing"
  [ "$status" -ne 0 ]
  run choice_installed media cliamp
  [ "$status" -eq 0 ]
}

@test "npm global packages install, register, and uninstall in the user's ~/.local prefix" {
  local prefix="$TARGET_HOME/.local"
  DRY_RUN=1

  run install_npm_global_package "@openai/codex"
  [ "$status" -eq 0 ]
  assert_contains "$output" "DRY-RUN: npm install -g --prefix $prefix @openai/codex"
  refute_contains "$output" "sudo"

  run remove_choice_action "npm-global:@openai/codex"
  [ "$status" -eq 0 ]
  assert_contains "$output" "DRY-RUN: npm uninstall -g --prefix $prefix @openai/codex"
  refute_contains "$output" "sudo"

  run verify_npm_global_package "@openai/codex"
  [ "$status" -ne 0 ]
  mkdir -p "$prefix/lib/node_modules/@openai/codex" "$prefix/lib/node_modules/typescript"
  touch "$prefix/lib/node_modules/@openai/codex/package.json" "$prefix/lib/node_modules/typescript/package.json"
  run verify_npm_global_package "@openai/codex"
  [ "$status" -eq 0 ]
  run npm_global_packages
  [ "$status" -eq 0 ]
  assert_equal $'@openai/codex\ntypescript' "$(sort <<<"$output")"
}

@test "installed state requires a unit's product links, not only its packages" {
  choice_item_present() { return 0; }

  # The Proton Manager unit's packages are base packages, so the plugin
  # link and its desktop entry are what tell an installed choice apart.
  run choice_installed gaming proton-manager
  [ "$status" -ne 0 ]

  mkdir -p "$TARGET_HOME/.config/DankMaterialShell/plugins" "$TARGET_HOME/.local/share/applications"
  ln -s "$ROOT_DIR/dotfiles/dms/.config/DankMaterialShell/plugins/ProtonManager" \
    "$TARGET_HOME/.config/DankMaterialShell/plugins/ProtonManager"
  run choice_installed gaming proton-manager
  [ "$status" -ne 0 ]

  ln -s "$ROOT_DIR/dotfiles/dms/.config/DankMaterialShell/plugins/ProtonManager/proton-manager.desktop" \
    "$TARGET_HOME/.local/share/applications/proton-manager.desktop"
  run choice_installed gaming proton-manager
  [ "$status" -eq 0 ]

  # A unit without managed configuration is judged by its packages alone.
  run choice_installed dev zed
  [ "$status" -eq 0 ]
}

@test "zz app lists choices with their state and refuses unknown choices" {
  local name
  for name in rpm flatpak brew npm; do
    make_fake_command "$name" 1
  done

  run env -i HOME="$TEST_ROOT/home" PATH="$FAKE_BIN:/usr/bin:/bin" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    TARGET_HOME="$TEST_ROOT/home" DESKTOP_APP_PROFILE=full \
    bash "$ROOT_DIR/bin/zz" app list --json
  [ "$status" -eq 0 ]
  [[ "${output:0:1}" == "[" ]]
  # Without saved selections the defaults are what counts as selected; the
  # installed state comes from the package tools, faked absent here.
  assert_equal "dev" "$(jq -r '.[] | select(.id == "zed") | .category' <<<"$output")"
  # Nested choices carry their parent so a picker can group them.
  assert_equal "" "$(jq -r '.[] | select(.id == "zed") | .parent' <<<"$output")"
  assert_equal "docker" "$(jq -r '.[] | select(.id == "docker-sudoless") | .parent' <<<"$output")"
  assert_equal "sdk" "$(jq -r '.[] | select(.id == "ef") | .parent' <<<"$output")"
  assert_equal "Development" "$(jq -r '.[] | select(.id == "zed") | .category_label' <<<"$output")"
  assert_equal "true" "$(jq -r '.[] | select(.id == "zed") | .selected' <<<"$output")"
  assert_equal "false" "$(jq -r '.[] | select(.id == "zed") | .installed' <<<"$output")"
  assert_equal "false" "$(jq -r '.[] | select(.id == "brave") | .selected' <<<"$output")"
  assert_equal "dev-zed" "$(jq -r '.[] | select(.id == "zed") | .units[0]' <<<"$output")"

  run env -i HOME="$TEST_ROOT/home" PATH="$FAKE_BIN:/usr/bin:/bin" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    TARGET_HOME="$TEST_ROOT/home" DESKTOP_APP_PROFILE=full \
    bash "$ROOT_DIR/bin/zz" app list
  [ "$status" -eq 0 ]
  assert_contains "$output" "[Development]"
  assert_contains "$output" "dev/zed"
  assert_contains "$output" "selected, missing"

  run bash "$ROOT_DIR/bin/zz" app install does-not-exist --dry-run
  [ "$status" -ne 0 ]
  assert_contains "$output" "Unknown choice 'does-not-exist'"

  run bash "$ROOT_DIR/bin/zz" app --help
  [ "$status" -eq 0 ]
  assert_contains "$output" "zz app install <choice>"
  assert_contains "$output" "--yes"
}

@test "zz app asks before installing or removing unless told otherwise" {
  # A declined prompt, or no answer at all, changes nothing and exits clean.
  run bash -c "printf 'n\n' | bash '$ROOT_DIR/bin/zz' app remove office/pinta"
  [ "$status" -eq 0 ]
  assert_contains "$output" "About to remove:"
  assert_contains "$output" "Pinta (Office, office/pinta)"
  assert_contains "$output" "Proceed? [y/N]"
  assert_contains "$output" "Cancelled."
  refute_contains "$output" "Log file:"

  run bash -c "bash '$ROOT_DIR/bin/zz' app install zed brave </dev/null"
  [ "$status" -eq 0 ]
  assert_contains "$output" "About to install:"
  assert_contains "$output" "Zed (Development, dev/zed)"
  assert_contains "$output" "Brave (Browsers, browsers/brave)"
  assert_contains "$output" "Cancelled."

  # Dry runs never prompt; they reach the installer, which reports the
  # missing saved selections in this empty home.
  run env -i HOME="$TEST_ROOT/home" PATH="$FAKE_BIN:/usr/bin:/bin" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/bin/zz" app install zed --dry-run
  [ "$status" -ne 0 ]
  refute_contains "$output" "Proceed?"
  assert_contains "$output" "Saved selections not found"

  run env -i HOME="$TEST_ROOT/home" PATH="$FAKE_BIN:/usr/bin:/bin" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" LOG_DIR="$LOG_DIR" \
    bash "$ROOT_DIR/bin/zz" app remove zed --yes
  [ "$status" -ne 0 ]
  refute_contains "$output" "Proceed?"
  assert_contains "$output" "Saved selections not found"
}
