#!/usr/bin/env bash
# Remote runtime loader executed inside Anaconda by the ZZ Fedora add-on
# (iso/anaconda-addon/org_zz_fedora/runtime.py). It refreshes the repository
# snapshot used by the ISO install and is not part of the install.sh path.
set -Eeuo pipefail

ISO_RUNTIME_ARCHIVE_URL="${ZZ_ISO_RUNTIME_ARCHIVE_URL:-https://api.github.com/repos/bgmulinari/zz-fedora/tarball/main}"
ISO_RUNTIME_REF="${ZZ_ISO_RUNTIME_REF:-main}"
ISO_RUNTIME_DIR="${ZZ_ISO_RUNTIME_DIR:-/run/zz-fedora/repository}"
ISO_RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISO_RUNTIME_PATHS_FILE="${ZZ_ISO_RUNTIME_PATHS_FILE:-$ISO_RUNTIME_ROOT/iso/payload-paths.conf}"

iso_runtime_err() {
  printf 'zz-fedora-runtime: %s\n' "$*" >&2
}

iso_runtime_path_is_safe() {
  local runtime_path="$1"
  [[ -n "$runtime_path" && "$runtime_path" != /* ]] || return 1
  [[ "$runtime_path" != "." && "$runtime_path" != ".." ]] || return 1
  [[ "$runtime_path" != ../* && "$runtime_path" != */../* && "$runtime_path" != */.. ]]
}

iso_download_runtime_archive() {
  local destination="$1"
  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --retry 5 \
    --connect-timeout 15 \
    --max-time 300 \
    --header 'User-Agent: zz-fedora-installer' \
    --output "$destination" \
    "$ISO_RUNTIME_ARCHIVE_URL"
}

iso_sync_installer_clock() {
  if command -v chronyc >/dev/null 2>&1 && chronyc tracking >/dev/null 2>&1; then
    chronyc waitsync 30 0 0 1
    return
  fi
  chronyd -q -t 30
}

iso_download_runtime_archive_with_clock_recovery() {
  local destination="$1"
  local download_status
  if iso_download_runtime_archive "$destination"; then
    return 0
  else
    download_status=$?
  fi

  if [[ "$download_status" -ne 60 ]] || ! command -v chronyd >/dev/null 2>&1; then
    return "$download_status"
  fi

  iso_runtime_err "TLS validation failed; synchronizing the installer clock"
  if ! iso_sync_installer_clock; then
    iso_runtime_err "could not synchronize the installer clock"
    return "$download_status"
  fi
  iso_download_runtime_archive "$destination"
}

iso_refresh_runtime() (
  local command
  for command in cp curl tar; do
    command -v "$command" >/dev/null 2>&1 || {
      iso_runtime_err "missing required command: $command"
      return 1
    }
  done

  local destination_parent work_dir archive_dir staged_dir archive_file
  destination_parent="$(dirname "$ISO_RUNTIME_DIR")"
  mkdir -p "$destination_parent"
  work_dir="$(mktemp -d "$destination_parent/.repository-refresh.XXXXXX")"
  archive_dir="$work_dir/archive"
  staged_dir="$work_dir/repository"
  archive_file="$work_dir/repository.tar.gz"
  trap 'rm -rf "$work_dir"' EXIT

  mkdir -p "$archive_dir" "$staged_dir"
  iso_runtime_err "fetching $ISO_RUNTIME_REF"
  iso_download_runtime_archive_with_clock_recovery "$archive_file"

  local archive_root revision
  archive_root="$(tar -tzf "$archive_file" | sed -n '1{s:/$::;p;}')"
  [[ -n "$archive_root" && "$archive_root" != */* ]] || {
    iso_runtime_err "remote archive does not have one top-level directory"
    return 1
  }
  revision="${archive_root##*-}"
  [[ "$revision" =~ ^[0-9A-Fa-f]{7,40}$ ]] || revision=unknown

  tar -xzf "$archive_file" \
    --no-same-owner \
    --strip-components=1 \
    -C "$archive_dir"

  local runtime_paths_file="$archive_dir/iso/payload-paths.conf"
  if [[ ! -f "$runtime_paths_file" ]]; then
    runtime_paths_file="$ISO_RUNTIME_PATHS_FILE"
    iso_runtime_err "remote runtime has no paths manifest; using embedded fallback"
  fi
  [[ -f "$runtime_paths_file" ]] || {
    iso_runtime_err "missing ISO payload paths manifest: $runtime_paths_file"
    return 1
  }
  local -a runtime_paths=()
  mapfile -t runtime_paths < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$runtime_paths_file")
  [[ "${#runtime_paths[@]}" -gt 0 ]] || {
    iso_runtime_err "ISO payload paths manifest is empty: $runtime_paths_file"
    return 1
  }
  local runtime_path staged_parent
  for runtime_path in "${runtime_paths[@]}"; do
    iso_runtime_path_is_safe "$runtime_path" || {
      iso_runtime_err "invalid ISO runtime path: $runtime_path"
      return 1
    }
    [[ -e "$archive_dir/$runtime_path" || -L "$archive_dir/$runtime_path" ]] || continue
    staged_parent="$staged_dir/$(dirname "$runtime_path")"
    mkdir -p "$staged_parent"
    cp -a "$archive_dir/$runtime_path" "$staged_parent/"
  done

  [[ -x "$staged_dir/install.sh" ]] || {
    iso_runtime_err "remote runtime is missing executable install.sh"
    return 1
  }
  [[ -f "$staged_dir/choices/browsers.conf" ]] || {
    iso_runtime_err "remote runtime is missing choices/browsers.conf"
    return 1
  }

  mkdir -p "$staged_dir/config"
  {
    printf 'format=1\n'
    printf 'git_revision=%s\n' "$revision"
    printf 'worktree_changes=0\n'
    printf 'remote_ref=%s\n' "$ISO_RUNTIME_REF"
  } >"$staged_dir/config/iso-payload.conf"
  chmod 0644 "$staged_dir/config/iso-payload.conf"

  rm -rf "$ISO_RUNTIME_DIR"
  mv "$staged_dir" "$ISO_RUNTIME_DIR"
  iso_runtime_err "staged $ISO_RUNTIME_REF revision $revision"
)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  iso_refresh_runtime
fi
