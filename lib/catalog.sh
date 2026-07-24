#!/usr/bin/env bash
set -Eeuo pipefail

# Compiled-catalog access layer. The catalog itself lives under catalog/ as
# TOML (one unit or source per file); lib/catalog.py is the single authority
# on that format and compiles it into flat TSVs. This layer runs the compile
# lazily on first access, loads the TSVs into Bash arrays, and exposes the
# lookup API used by the planner, wizard, and modules. No other Bash code
# parses catalog data.

CATALOG_LOADED=0
CATALOG_CACHE_INSTANCE_ID="${BASHPID:-$$}"
declare -Ag CATALOG_BUNDLE_ROW=()   # bundle id -> full bundles.tsv row
declare -Ag CATALOG_SOURCE_ROW=()   # source id -> full sources.tsv row
declare -Ag CATALOG_BUNDLE_STEPS=() # bundle id -> newline-joined "idx\tbackend\tsources"
declare -Ag CATALOG_STEP_ITEMS=()   # "bundle id\x1fidx" -> newline-joined items
declare -ag CATALOG_SOURCE_IDS=()
declare -ag CATALOG_CATEGORIES=()
declare -ag CATALOG_ACTION_ITEMS=()
declare -ag BASE_BUNDLE_IDS=()
declare -ag EARLY_BASE_BUNDLE_IDS=()
declare -ag MINIMAL_DESKTOP_SKIP_BUNDLE_IDS=()

catalog_compiled_dir() {
  # Every top-level Bash process gets its own compiled snapshot. Command
  # substitutions inherit the instance id captured when this file was
  # sourced, so their generated paths remain visible to the parent shell.
  printf '%s/catalog-compiled.%s\n' "$CACHE_DIR" "$CATALOG_CACHE_INSTANCE_ID"
}

catalog_cleanup_cache() {
  local compiled_dir
  compiled_dir="$(catalog_compiled_dir)"
  case "$compiled_dir" in
    "$CACHE_DIR"/catalog-compiled.*)
      rm -rf -- "$compiled_dir" || true
      ;;
  esac
}

# Tests point ROOT_DIR at sandbox catalogs mid-process; resetting drops every
# in-memory table so the next access recompiles from the new root.
catalog_reset_cache() {
  CATALOG_LOADED=0
  CATALOG_BUNDLE_ROW=()
  CATALOG_SOURCE_ROW=()
  CATALOG_BUNDLE_STEPS=()
  CATALOG_STEP_ITEMS=()
  CATALOG_SOURCE_IDS=()
  CATALOG_CATEGORIES=()
  CATALOG_ACTION_ITEMS=()
  BASE_BUNDLE_IDS=()
  EARLY_BASE_BUNDLE_IDS=()
  MINIMAL_DESKTOP_SKIP_BUNDLE_IDS=()
}

catalog_ensure_loaded() {
  [[ "$CATALOG_LOADED" -eq 1 ]] && return 0
  command -v python3 >/dev/null 2>&1 ||
    die "python3 is required to load the catalog; install it and rerun (bootstrap.sh installs it on fresh systems)"

  local compiled_dir
  compiled_dir="$(catalog_compiled_dir)"
  rm -rf "$compiled_dir"
  mkdir -p "$compiled_dir"
  python3 "$ROOT_DIR/lib/catalog.py" --root "$ROOT_DIR" compile --out "$compiled_dir" ||
    die "Catalog validation failed; fix the errors above and rerun"

  local line id early skip
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    CATALOG_BUNDLE_ROW["${line%%$'\t'*}"]="$line"
  done <"$compiled_dir/bundles.tsv"

  while IFS=$'\t' read -r id early skip; do
    [[ -n "$id" ]] || continue
    BASE_BUNDLE_IDS+=("$id")
    [[ "$early" == "1" ]] && EARLY_BASE_BUNDLE_IDS+=("$id")
    [[ "$skip" == "1" ]] && MINIMAL_DESKTOP_SKIP_BUNDLE_IDS+=("$id")
  done <"$compiled_dir/base.tsv"

  local step_index backend step_sources
  while IFS=$'\t' read -r id step_index backend step_sources; do
    [[ -n "$id" ]] || continue
    if [[ -n "${CATALOG_BUNDLE_STEPS[$id]:-}" ]]; then
      CATALOG_BUNDLE_STEPS["$id"]+=$'\n'"$step_index"$'\t'"$backend"$'\t'"$step_sources"
    else
      CATALOG_BUNDLE_STEPS["$id"]="$step_index"$'\t'"$backend"$'\t'"$step_sources"
    fi
  done <"$compiled_dir/steps.tsv"

  local item key
  while IFS=$'\t' read -r id step_index backend item; do
    [[ -n "$id" ]] || continue
    key="$id"$'\x1f'"$step_index"
    if [[ -n "${CATALOG_STEP_ITEMS[$key]:-}" ]]; then
      CATALOG_STEP_ITEMS["$key"]+=$'\n'"$item"
    else
      CATALOG_STEP_ITEMS["$key"]="$item"
    fi
    [[ "$backend" == "action" ]] && append_unique CATALOG_ACTION_ITEMS "$item"
  done <"$compiled_dir/items.tsv"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    id="${line%%$'\t'*}"
    CATALOG_SOURCE_IDS+=("$id")
    CATALOG_SOURCE_ROW["$id"]="$line"
  done <"$compiled_dir/sources.tsv"

  while IFS= read -r id; do
    [[ -n "$id" ]] && CATALOG_CATEGORIES+=("$id")
  done <"$compiled_dir/categories.list"

  CATALOG_LOADED=1
}

load_bundle_descriptor() {
  local bundle_id="$1"
  catalog_ensure_loaded
  local row="${CATALOG_BUNDLE_ROW[$bundle_id]:-}"
  [[ -n "$row" ]] || return 1
  # Tab is IFS whitespace, so empty TSV fields would collapse under a
  # tab-IFS read; swap in a non-whitespace separator first.
  row="${row//$'\t'/$'\x1f'}"
  # shellcheck disable=SC2034  # Descriptor globals are consumed by the planner, modules, and tui.
  IFS=$'\x1f' read -r \
    BUNDLE_ID \
    BUNDLE_BASE \
    BUNDLE_BASE_ORDER \
    BUNDLE_BASE_EARLY \
    BUNDLE_MINIMAL_DESKTOP_SKIP \
    BUNDLE_DEPENDENCIES \
    BUNDLE_SOURCE_IDS \
    BUNDLE_CONFIG_COMPONENTS \
    BUNDLE_BACKENDS \
    BUNDLE_DESCRIPTION <<<"$row"
}

bundle_exists() {
  catalog_ensure_loaded
  [[ -n "${CATALOG_BUNDLE_ROW[$1]:-}" ]]
}

list_bundle_ids() {
  catalog_ensure_loaded
  printf '%s\n' "${!CATALOG_BUNDLE_ROW[@]}" | sort
}

# Prints one line per install step of the bundle: "index\tbackend\tsources".
bundle_steps() {
  local bundle_id="$1"
  catalog_ensure_loaded
  local steps="${CATALOG_BUNDLE_STEPS[$bundle_id]:-}"
  [[ -n "$steps" ]] && printf '%s\n' "$steps"
  return 0
}

# Prints the payload items of one install step, one per line.
bundle_step_items() {
  local bundle_id="$1"
  local step_index="$2"
  catalog_ensure_loaded
  local items="${CATALOG_STEP_ITEMS[$bundle_id$'\x1f'$step_index]:-}"
  [[ -n "$items" ]] && printf '%s\n' "$items"
  return 0
}

# Prints every payload item of the bundle across all steps, sorted unique.
bundle_items() {
  local bundle_id="$1"
  catalog_ensure_loaded
  local step_index _backend _sources
  while IFS=$'\t' read -r step_index _backend _sources; do
    [[ -n "$step_index" ]] || continue
    bundle_step_items "$bundle_id" "$step_index"
  done < <(bundle_steps "$bundle_id") | sort -u
}

load_source_descriptor() {
  local source_id="$1"
  catalog_ensure_loaded
  local row="${CATALOG_SOURCE_ROW[$source_id]:-}"
  [[ -n "$row" ]] || return 1
  row="${row//$'\t'/$'\x1f'}"
  # shellcheck disable=SC2034  # Source globals are consumed by fedora.sh, readiness.sh, and the planner.
  IFS=$'\x1f' read -r \
    SOURCE_ID \
    SOURCE_KIND \
    SOURCE_LABEL \
    SOURCE_PROJECT \
    SOURCE_REQUIRED \
    SOURCE_GPG_POLICY \
    SOURCE_BOOTSTRAP_EXCEPTION \
    SOURCE_DESCRIPTION \
    SOURCE_REASON <<<"$row"
}

list_source_ids() {
  catalog_ensure_loaded
  printf '%s\n' "${CATALOG_SOURCE_IDS[@]:-}"
}

# Custom-action payloads can only be checked against the Bash action registry,
# which lib/catalog.py cannot see; the planner calls this after loading.
catalog_validate_action_items() {
  catalog_ensure_loaded
  local action
  for action in "${CATALOG_ACTION_ITEMS[@]:-}"; do
    [[ -n "$action" ]] || continue
    action_registered "$action" ||
      die "Unknown custom action '$action' in the catalog: no register_action row declares it (see lib/actions/*.sh)"
  done
}

normalize_category_name() {
  case "$1" in
    browser) printf 'browsers\n' ;;
    source) printf 'sources\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

category_names() {
  catalog_ensure_loaded
  printf '%s\n' "${CATALOG_CATEGORIES[@]:-}"
}

choice_catalog_path() {
  local category
  category="$(normalize_category_name "$1")"
  catalog_ensure_loaded
  printf '%s/choices/%s.tsv\n' "$(catalog_compiled_dir)" "$category"
}

default_choice_ids() {
  local catalog
  catalog="$(choice_catalog_path "$1")"
  [[ -f "$catalog" ]] || return 0
  awk -F'\t' 'NF==5 && $3 == 1 {print $1}' "$catalog"
}

all_choice_ids() {
  local catalog
  catalog="$(choice_catalog_path "$1")"
  [[ -f "$catalog" ]] || return 0
  awk -F'\t' 'NF==5 {print $1}' "$catalog"
}

choice_record() {
  local category="$1"
  local choice_id="$2"
  local catalog
  catalog="$(choice_catalog_path "$category")"
  [[ -f "$catalog" ]] || return 1
  awk -F'\t' -v choice_id="$choice_id" 'NF==5 && $1 == choice_id {print $0}' "$catalog"
}

choice_field() {
  local line="$1"
  local field_index="$2"
  local -a fields=()
  line="${line//$'\t'/$'\x1f'}"
  IFS=$'\x1f' read -r -a fields <<<"$line"
  printf '%s\n' "${fields[$((field_index - 1))]:-}"
}
