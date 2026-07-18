#!/usr/bin/env bash
# Build-time helpers shared by the ISO build and VM test scripts. This library
# runs on the developer machine only; iso/lib/runtime-loader.sh is the piece
# that runs inside Anaconda.
set -Eeuo pipefail

iso_err() {
  printf '%s: %s\n' "${ISO_TOOL_NAME:-zz-fedora-iso}" "$*" >&2
}

iso_extract_fedora_metadata() {
  local input_iso="$1"
  local metadata_dir discinfo
  metadata_dir="$(mktemp -d)"
  discinfo="$metadata_dir/.discinfo"
  xorriso -osirrox on -indev "$input_iso" -extract /.discinfo "$discinfo" >/dev/null 2>&1 || {
    rm -rf "$metadata_dir"
    iso_err "could not extract /.discinfo from input ISO"
    return 1
  }
  fedora_release="$(sed -n '2p' "$discinfo")"
  fedora_arch="$(sed -n '3p' "$discinfo")"
  rm -rf "$metadata_dir"
  [[ -n "$fedora_release" && -n "$fedora_arch" ]] || {
    iso_err "could not determine Fedora release and architecture from input ISO"
    return 1
  }
}

iso_validate_supported_platform() {
  local release="$1"
  local architecture="$2"
  [[ "$release" == "44" ]] || {
    iso_err "unsupported Fedora release in input ISO: $release (supported: 44)"
    return 1
  }
  [[ "$architecture" == "x86_64" ]] || {
    iso_err "unsupported architecture in input ISO: $architecture (supported: x86_64)"
    return 1
  }
}

iso_verify_sha256() {
  local input_iso="$1"
  local expected="$2"
  [[ "$expected" =~ ^[A-Fa-f0-9]{64}$ ]] || {
    iso_err "invalid SHA-256 value: $expected"
    return 1
  }
  local actual
  actual="$(sha256sum "$input_iso" | awk '{print $1}')"
  [[ "${actual,,}" == "${expected,,}" ]] || {
    iso_err "input ISO checksum mismatch: expected $expected, got $actual"
    return 1
  }
  printf 'Verified input SHA-256: %s\n' "$actual"
}

iso_stage_tracked_runtime_payload() {
  local repo_dir="$1"
  local destination="$2"
  local runtime_paths_file="$repo_dir/iso/payload-paths.conf"
  [[ -f "$runtime_paths_file" ]] || {
    iso_err "missing ISO payload paths manifest: $runtime_paths_file"
    return 1
  }
  local -a runtime_paths=()
  mapfile -t runtime_paths < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$runtime_paths_file")
  [[ "${#runtime_paths[@]}" -gt 0 ]] || {
    iso_err "ISO payload paths manifest is empty: $runtime_paths_file"
    return 1
  }

  rm -rf "$destination"
  mkdir -p "$destination"
  (
    cd "$repo_dir"
    while IFS= read -r -d '' tracked_path; do
      [[ -e "$tracked_path" || -L "$tracked_path" ]] || continue
      printf '%s\0' "$tracked_path"
    done < <(git ls-files -z -- "${runtime_paths[@]}")
  ) | rsync -a --from0 --files-from=- "$repo_dir/" "$destination/"

  [[ -x "$destination/install.sh" ]] || {
    iso_err "staged payload is missing executable install.sh"
    return 1
  }
  [[ -x "$destination/iso/lib/runtime-loader.sh" ]] || {
    iso_err "staged payload is missing executable iso/lib/runtime-loader.sh"
    return 1
  }
  [[ ! -e "$destination/.git" ]] || {
    iso_err "staged payload unexpectedly contains .git"
    return 1
  }

  local revision dirty
  revision="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  dirty=0
  git -C "$repo_dir" diff --quiet --ignore-submodules -- 2>/dev/null || dirty=1
  git -C "$repo_dir" diff --cached --quiet --ignore-submodules -- 2>/dev/null || dirty=1
  mkdir -p "$destination/config"
  {
    printf 'format=1\n'
    printf 'git_revision=%s\n' "$revision"
    printf 'worktree_changes=%s\n' "$dirty"
  } >"$destination/config/iso-payload.conf"
}
