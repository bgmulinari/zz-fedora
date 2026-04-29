#!/usr/bin/env bash
set -Eeuo pipefail

native_backend_for_distro() {
  case "$1" in
    fedora) printf 'dnf\n' ;;
    arch) printf 'pacman\n' ;;
    *) die "Unsupported distro for native backend: $1" ;;
  esac
}

package_file_for_backend() {
  case "$1" in
    dnf) printf '%s/packages/dnf.pkgs\n' "$PLAN_DIR" ;;
    pacman) printf '%s/packages/pacman.pkgs\n' "$PLAN_DIR" ;;
    aur) printf '%s/packages/aur.pkgs\n' "$PLAN_DIR" ;;
    flatpak) printf '%s/flatpak/apps.flatpaks\n' "$PLAN_DIR" ;;
    action) printf '%s/actions/actions.list\n' "$PLAN_DIR" ;;
    *) die "Unsupported plan package backend: $1" ;;
  esac
}

prereq_file_for_backend() {
  case "$1" in
    dnf) printf '%s/prereqs/dnf.pkgs\n' "$PLAN_DIR" ;;
    pacman) printf '%s/prereqs/pacman.pkgs\n' "$PLAN_DIR" ;;
    aur) printf '%s/prereqs/aur.pkgs\n' "$PLAN_DIR" ;;
    flatpak) printf '%s/prereqs/flatpak.flatpaks\n' "$PLAN_DIR" ;;
    action) printf '%s/prereqs/actions.list\n' "$PLAN_DIR" ;;
    *) die "Unsupported prereq backend: $1" ;;
  esac
}

backend_prerequisite_backend() {
  case "$1" in
    dnf|pacman|aur|action) return 1 ;;
    flatpak) native_backend_for_distro "$DISTRO" ;;
    *) die "Unsupported backend: $1" ;;
  esac
}

backend_prerequisite_items() {
  case "$1" in
    dnf|pacman|aur|action) return 0 ;;
    flatpak)
      manifest_entries "$ROOT_DIR/packages/$DISTRO/official/flatpak.pkgs"
      ;;
    *)
      die "Unsupported backend: $1"
      ;;
  esac
}

append_plan_entries() {
  local destination="$1"
  shift
  mkdir -p "$(dirname "$destination")"
  touch "$destination"
  local item
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    if ! grep -Fx "$item" "$destination" >/dev/null 2>&1; then
      printf '%s\n' "$item" >>"$destination"
    fi
  done
  sort -u "$destination" -o "$destination"
}

read_plan_file() {
  local plan_file="$1"
  [[ -f "$plan_file" ]] || return 0
  read_clean_lines "$plan_file" | sort -u
}
