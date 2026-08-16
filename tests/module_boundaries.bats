#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
}

# Collect function names defined in a shell file, one per line.
functions_defined_in() {
  grep -hoE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$1" | sed 's/()$//'
}

@test "every module file defines an entrypoint matching its NN prefix" {
  local module_file base nn
  for module_file in "$ROOT_DIR"/modules/*.sh; do
    base="$(basename "$module_file" .sh)"
    nn="${base%%-*}"
    grep -qE "^module_${nn}_[a-zA-Z0-9_]+\(\)" "$module_file" || {
      printf 'module file %s defines no module_%s_* entrypoint\n' "$module_file" "$nn" >&2
      return 1
    }
  done
}

@test "module entrypoint functions live in the module file with the same NN" {
  local module_file base nn stray
  for module_file in "$ROOT_DIR"/modules/*.sh; do
    base="$(basename "$module_file" .sh)"
    nn="${base%%-*}"
    stray="$(functions_defined_in "$module_file" | grep -E '^module_[0-9]+_' | grep -vE "^module_${nn}_" || true)"
    if [[ -n "$stray" ]]; then
      printf 'module file %s defines entrypoints for another step number:\n%s\n' "$module_file" "$stray" >&2
      return 1
    fi
  done
}

@test "modules do not call functions defined in other modules" {
  local module_file other_file function_name violations=""
  for module_file in "$ROOT_DIR"/modules/*.sh; do
    for other_file in "$ROOT_DIR"/modules/*.sh; do
      [[ "$module_file" == "$other_file" ]] && continue
      while IFS= read -r function_name; do
        [[ -n "$function_name" ]] || continue
        if grep -nE "(^|[^a-zA-Z0-9_])${function_name}([^a-zA-Z0-9_(]|\$|\()" "$module_file" \
          | grep -vE "^[0-9]+:${function_name}\(\)" >/dev/null; then
          violations+="$(basename "$module_file") calls ${function_name} defined in $(basename "$other_file")"$'\n'
        fi
      done < <(functions_defined_in "$other_file")
    done
  done
  if [[ -n "$violations" ]]; then
    printf 'cross-module function calls must move to lib/:\n%s' "$violations" >&2
    return 1
  fi
}

@test "install step table rows map to real module entrypoints and predicates" {
  local raw row step_id label function_name predicate failure_policy description nn
  local -a rows=() module_files=()
  mapfile -t rows < <(sed -n '/^declare -ag INSTALL_STEP_TABLE=(/,/^)/p' "$ROOT_DIR/install.sh" | sed '1d;$d')
  [ "${#rows[@]}" -gt 0 ]

  for raw in "${rows[@]}"; do
    raw="${raw#"${raw%%[![:space:]]*}"}"
    eval "row=${raw}"
    IFS=$'\t' read -r step_id label function_name predicate failure_policy description <<<"$row"
    [ -n "$step_id" ]
    [ -n "$label" ]
    [ -n "$description" ]
    [[ "$failure_policy" == "fatal" || "$failure_policy" == "continue" ]] || {
      printf 'step %s has unsupported failure policy: %s\n' "$step_id" "$failure_policy" >&2
      return 1
    }
    grep -qE "^${predicate}\(\)" "$ROOT_DIR/install.sh" || {
      printf 'step %s references unknown predicate: %s\n' "$step_id" "$predicate" >&2
      return 1
    }

    [[ "$function_name" == module_* ]] || {
      printf 'step %s does not use a module entrypoint: %s\n' "$step_id" "$function_name" >&2
      return 1
    }
    nn="${function_name#module_}"
    nn="${nn%%_*}"
    module_files=("$ROOT_DIR/modules/${nn}"-*.sh)
    [[ -f "${module_files[0]}" ]] || {
      printf 'step %s references %s but no modules/%s-*.sh file exists\n' "$step_id" "$function_name" "$nn" >&2
      return 1
    }
    grep -qE "^${function_name}\(\)" "${module_files[0]}" || {
      printf 'step %s entrypoint %s is not defined in %s\n' "$step_id" "$function_name" "${module_files[0]}" >&2
      return 1
    }
  done
}

# One root list shared by every "defined/invoked only in one place" invariant
# below, so a new source root cannot silently fall out of one test's coverage.
installer_source_roots() {
  printf '%s\n' \
    "$ROOT_DIR/lib" \
    "$ROOT_DIR/modules" \
    "$ROOT_DIR/bin" \
    "$ROOT_DIR/scripts" \
    "$ROOT_DIR/install.sh" \
    "$ROOT_DIR/bootstrap.sh"
}

assert_defined_only_in() {
  local owner="$1" symbol="$2" matches
  local -a roots
  mapfile -t roots < <(installer_source_roots)
  matches="$(grep -rlE "^${symbol}=" "${roots[@]}" | sort)"
  assert_equal "$owner" "$matches"
}

@test "installer runtime invokes Python only through SYSTEM_PYTHON" {
  # Homebrew's python@3.x arrives as an unrequested transitive dependency of
  # other formulae, and the installer cannot assume the caller's PATH order,
  # so a bare `python3` in command position is not guaranteed to resolve to
  # the interpreter bootstrap.sh installs. The pattern covers python3 at the
  # start of a command (line start, `;`, `&`, `|`, `(`, `$(`, backtick) and
  # after the wrapper words this repository runs commands through; package
  # name lists (`dnf install ... python3`) end the line or precede another
  # package, so requiring trailing whitespace keeps them out.
  local raw invocations status=0
  local -a roots
  mapfile -t roots < <(installer_source_roots)
  raw="$(grep -rnE \
    '((^|[;&|(`]|\$\()[[:space:]]*|(run_cmd|run_cmd_as_root|run|sudo|exec|env|xargs|command|timeout|if|elif|while|until|then|else|do)[[:space:]]+|run_cmd_as_user[[:space:]]+[^[:space:]]+[[:space:]]+)python3[[:space:]]' \
    "${roots[@]}")" || status=$?
  # grep exits 1 on "no matches" and >1 on a real error (missing root,
  # unreadable file); a broken scan must fail the test, not pass it.
  [[ "$status" -le 1 ]] || {
    printf 'python3 invocation scan failed with status %d\n' "$status" >&2
    return 1
  }
  invocations="$(grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' <<<"$raw" || true)"
  if [[ -n "$invocations" ]]; then
    printf 'invoke Python through "$SYSTEM_PYTHON", not a bare python3:\n%s\n' "$invocations" >&2
    return 1
  fi
}

@test "SYSTEM_PYTHON is defined only in lib/common.sh" {
  assert_defined_only_in "$ROOT_DIR/lib/common.sh" 'SYSTEM_PYTHON'
}

@test "dotnet install-script pins are defined only in lib/dotnet.sh" {
  local pin
  for pin in DOTNET_INSTALL_COMMIT DOTNET_INSTALL_SHA256; do
    assert_defined_only_in "$ROOT_DIR/lib/dotnet.sh" "$pin"
  done
}
