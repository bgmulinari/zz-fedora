#!/usr/bin/env bash
set -Eeuo pipefail

# User-context file helpers built on the shared install_file_if_changed
# primitive: INI-style config edits and the zz launcher symlink.

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
  install_file_if_changed user "$temp_file" "$file"
  rm -f "$temp_file"
}

install_zz_launcher() {
  local launcher="$TARGET_HOME/.local/bin/zz"
  local target="$ROOT_DIR/bin/zz"
  [[ -x "$target" ]] || return 0

  log_progress "Installing zz launcher"
  run_cmd_as_user "$TARGET_USER" mkdir -p "$(dirname "$launcher")"
  run_cmd_as_user "$TARGET_USER" ln -sfn "$target" "$launcher"
}
