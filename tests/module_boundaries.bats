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

@test "dotnet install-script pins are defined only in lib/dotnet.sh" {
  local pin matches
  for pin in DOTNET_INSTALL_COMMIT DOTNET_INSTALL_SHA256; do
    matches="$(grep -rlE "^${pin}=" \
      "$ROOT_DIR/lib" \
      "$ROOT_DIR/modules" \
      "$ROOT_DIR/bin" \
      "$ROOT_DIR/scripts" \
      "$ROOT_DIR/install.sh" \
      "$ROOT_DIR/bootstrap.sh" | sort)"
    assert_equal "$ROOT_DIR/lib/dotnet.sh" "$matches"
  done
}
