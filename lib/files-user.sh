#!/usr/bin/env bash
set -Eeuo pipefail

# User-context file primitives: install files into the target user's home
# with backup-before-replace semantics, and edit INI-style config keys.

install_user_file_if_changed() {
  local source_file="$1"
  local destination="$2"
  local mode="${3:-0644}"

  if [[ -f "$destination" ]] && cmp -s "$source_file" "$destination"; then
    log_info "Unchanged file: $destination"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install %s -> %s (mode %s)\n' "$source_file" "$destination" "$mode"
    return 0
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    local backup_root backup_path
    backup_root="$STATE_DIR/backups/$(timestamp)"
    backup_path="$backup_root$destination"
    run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$backup_path")"
    run_cmd_as_user "$TARGET_USER" cp -a "$destination" "$backup_path"
    log_info "Backed up $destination to $backup_path"
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$destination")"
  run_cmd_as_user "$TARGET_USER" install -m "$mode" "$source_file" "$destination"
}

set_ini_key_for_user() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"
  local temp_file

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$file")"
  run_cmd_as_user "$TARGET_USER" touch "$file"
  temp_file="$(mktemp "$CACHE_DIR/ini.XXXXXX")"
  awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN {
      in_section = 0
      section_seen = 0
      key_written = 0
    }
    $0 == "[" section "]" {
      if (in_section && !key_written) {
        print key "=" value
        key_written = 1
      }
      in_section = 1
      section_seen = 1
      print
      next
    }
    /^\[/ {
      if (in_section && !key_written) {
        print key "=" value
        key_written = 1
      }
      in_section = 0
      print
      next
    }
    in_section && $0 ~ "^" key "=" {
      print key "=" value
      key_written = 1
      next
    }
    { print }
    END {
      if (!section_seen) {
        print "[" section "]"
        print key "=" value
      } else if (in_section && !key_written) {
        print key "=" value
      }
    }
  ' "$file" >"$temp_file"
  chmod 0644 "$temp_file"
  install_user_file_if_changed "$temp_file" "$file"
  rm -f "$temp_file"
}

install_zz_launcher() {
  local launcher="$TARGET_HOME/.local/bin/zz"
  local target="$ROOT_DIR/bin/zz"
  [[ -x "$target" ]] || return 0

  log_progress "Installing zz launcher"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install zz launcher %s -> %s\n' "$target" "$launcher"
    return 0
  fi

  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$launcher")"
  run_cmd_as_user "$TARGET_USER" ln -sfn "$target" "$launcher"
}
