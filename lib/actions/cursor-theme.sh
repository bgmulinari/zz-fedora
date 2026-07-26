#!/usr/bin/env bash
set -Eeuo pipefail

# Pinned desktop cursor theme custom action.

DESKTOP_CURSOR_THEME_BASE_NAME="Qogir"
DESKTOP_CURSOR_THEME_SIZE=24
DESKTOP_CURSOR_THEME_COMMIT="c633057ba0d27a504b3255144071c9691ed0264a"
DESKTOP_CURSOR_THEME_ARCHIVE_SHA256="4e13a959ddae29c95eac6d339217565df88e5a1ff3dfdfc1c1dc9bce83a3719a"
DESKTOP_CURSOR_THEME_ARCHIVE_URL="https://github.com/vinceliuice/Qogir-icon-theme/archive/${DESKTOP_CURSOR_THEME_COMMIT}.tar.gz"

desktop_cursor_theme_name() {
  printf '%s-%s\n' "$DESKTOP_CURSOR_THEME_BASE_NAME" "$DESKTOP_CURSOR_THEME_COMMIT"
}

desktop_cursor_theme_dir() {
  printf '%s\n' "$TARGET_HOME/.local/share/icons/$(desktop_cursor_theme_name)"
}

desktop_cursor_theme_installed() {
  local theme_dir marker niri_config theme_name
  theme_dir="$(desktop_cursor_theme_dir)"
  marker="$theme_dir/.zz-source-commit"
  niri_config="$theme_dir/zz-niri.kdl"
  theme_name="$(desktop_cursor_theme_name)"

  [[ -d "$theme_dir/cursors" ]] || return 1
  [[ -s "$theme_dir/LICENSE" ]] || return 1
  [[ -s "$theme_dir/index.theme" ]] || return 1
  [[ -s "$niri_config" ]] || return 1
  [[ -s "$theme_dir/cursors/default" ]] || return 1
  [[ -e "$theme_dir/cursors/left_ptr" ]] || return 1
  [[ -f "$marker" ]] || return 1
  [[ "$(<"$marker")" == "$DESKTOP_CURSOR_THEME_COMMIT" ]] || return 1
  grep -Fx "Name=Qogir Cursors" "$theme_dir/index.theme" >/dev/null 2>&1 &&
    grep -Fx "    xcursor-theme \"$theme_name\"" "$niri_config" >/dev/null 2>&1 &&
    grep -Fx "    xcursor-size $DESKTOP_CURSOR_THEME_SIZE" "$niri_config" >/dev/null 2>&1
}

install_desktop_cursor_theme() {
  local theme_dir theme_name
  theme_dir="$(desktop_cursor_theme_dir)"
  theme_name="$(desktop_cursor_theme_name)"

  if desktop_cursor_theme_installed; then
    log_info "$DESKTOP_CURSOR_THEME_BASE_NAME cursor theme already installed at $theme_dir"
    return 0
  fi
  if [[ (-e "$theme_dir" || -L "$theme_dir") && ! -f "$theme_dir/.zz-source-commit" ]]; then
    die "Cursor theme destination already exists and is not installer-managed: $theme_dir"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: install %s cursor theme at commit %s -> %s\n' \
      "$DESKTOP_CURSOR_THEME_BASE_NAME" "$DESKTOP_CURSOR_THEME_COMMIT" "$theme_dir"
    printf 'DRY-RUN: verify sha256 %s\n' "$DESKTOP_CURSOR_THEME_ARCHIVE_SHA256"
    return 0
  fi

  log_progress "Installing $DESKTOP_CURSOR_THEME_BASE_NAME cursor theme"
  run_cmd_as_user "$TARGET_USER" bash -c '
    set -Eeuo pipefail

    destination="$1"
    archive_url="$2"
    archive_sha256="$3"
    commit="$4"
    theme_name="$5"
    theme_size="$6"
    archive_root="Qogir-icon-theme-$commit"
    destination_parent="${destination%/*}"
    mkdir -p "$destination_parent"
    staging="$(mktemp -d "$destination_parent/.zz-cursor-theme.XXXXXX")"
    archive="$staging/source.tar.gz"
    payload="$staging/theme"
    previous="$staging/previous"

    cleanup() {
      if [[ ! -e "$destination" && ! -L "$destination" ]] &&
        [[ -e "$previous" || -L "$previous" ]]; then
        mv "$previous" "$destination" >/dev/null 2>&1 || true
      fi
      rm -rf -- "$staging"
    }
    trap cleanup EXIT

    curl -fsSL \
      --retry 5 \
      --retry-delay 2 \
      --retry-all-errors \
      --connect-timeout 15 \
      "$archive_url" \
      -o "$archive"
    printf "%s  %s\n" "$archive_sha256" "$archive" | sha256sum -c -

    mkdir -p "$payload"
    tar -xzf "$archive" \
      -C "$payload" \
      --strip-components=4 \
      "$archive_root/src/cursors/dist"
    tar -xzf "$archive" \
      -C "$payload" \
      --strip-components=3 \
      "$archive_root/src/cursors/LICENSE"
    printf "%s\n" "$commit" >"$payload/.zz-source-commit"
    printf "cursor {\n    xcursor-theme \"%s\"\n    xcursor-size %s\n}\n" \
      "$theme_name" "$theme_size" >"$payload/zz-niri.kdl"

    test -s "$payload/LICENSE"
    test -s "$payload/index.theme"
    test -s "$payload/zz-niri.kdl"
    test -s "$payload/cursors/default"
    test -e "$payload/cursors/left_ptr"
    grep -Fx "Name=Qogir Cursors" "$payload/index.theme" >/dev/null

    if [[ -e "$destination" || -L "$destination" ]]; then
      mv "$destination" "$previous"
    fi
    if ! mv "$payload" "$destination"; then
      if [[ -e "$previous" || -L "$previous" ]]; then
        mv "$previous" "$destination"
      fi
      exit 1
    fi
  ' _ \
    "$theme_dir" \
    "$DESKTOP_CURSOR_THEME_ARCHIVE_URL" \
    "$DESKTOP_CURSOR_THEME_ARCHIVE_SHA256" \
    "$DESKTOP_CURSOR_THEME_COMMIT" \
    "$theme_name" \
    "$DESKTOP_CURSOR_THEME_SIZE"

  desktop_cursor_theme_installed ||
    die "$DESKTOP_CURSOR_THEME_BASE_NAME cursor theme installation did not pass verification."
}

register_action "desktop-cursor-theme" install_desktop_cursor_theme desktop_cursor_theme_installed
