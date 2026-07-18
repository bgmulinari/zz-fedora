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
  local minimum_release="$3"
  [[ "$minimum_release" =~ ^[0-9]+$ ]] || {
    iso_err "invalid MINIMUM_FEDORA_RELEASE configuration: ${minimum_release:-unset}"
    return 1
  }
  [[ "$release" =~ ^[0-9]+$ ]] || {
    iso_err "invalid Fedora release in input ISO: ${release:-unknown}"
    return 1
  }
  ((10#$release >= 10#$minimum_release)) || {
    iso_err "unsupported Fedora release in input ISO: $release (minimum: $minimum_release)"
    return 1
  }
  [[ "$architecture" == "x86_64" ]] || {
    iso_err "unsupported architecture in input ISO: $architecture (supported: x86_64)"
    return 1
  }
}

iso_render_release_template() {
  local template="$1"
  local destination="$2"
  sed \
    -e "s/@FEDORA_RELEASE@/$fedora_release/g" \
    -e "s/@FEDORA_ARCH@/$fedora_arch/g" \
    "$template" >"$destination"
}

iso_write_checkout_stamp() {
  local repo_dir="$1"
  local destination_file="$2"
  local revision dirty
  revision="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf 'unknown')"
  dirty=0
  git -C "$repo_dir" diff --quiet --ignore-submodules -- 2>/dev/null || dirty=1
  git -C "$repo_dir" diff --cached --quiet --ignore-submodules -- 2>/dev/null || dirty=1
  mkdir -p "$(dirname "$destination_file")"
  {
    printf 'format=1\n'
    printf 'git_revision=%s\n' "$revision"
    printf 'worktree_changes=%s\n' "$dirty"
  } >"$destination_file"
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

iso_download_file() {
  local url="$1"
  local destination="$2"
  local label="$3"

  if ! command -v curl >/dev/null 2>&1; then
    iso_err "missing required command: curl"
    return 1
  fi

  local partial_file="${destination}.part"
  local download_status
  mkdir -p "$(dirname "$destination")"
  printf 'Downloading %s to %s\n' "$label" "$destination"
  if curl \
    --fail \
    --location \
    --retry 3 \
    --output "$partial_file" \
    "$url"; then
    :
  else
    download_status=$?
    rm -f "$partial_file"
    iso_err "failed to download $label: $url"
    return "$download_status"
  fi
  mv -f "$partial_file" "$destination"
  printf 'Downloaded %s: %s\n' "$label" "$destination"
}

iso_download_cached_file() {
  local url="$1"
  local destination="$2"
  local label="$3"

  if [[ -f "$destination" ]]; then
    printf 'Using cached %s: %s\n' "$label" "$destination"
    return 0
  fi

  iso_download_file "$url" "$destination" "$label"
}

iso_download_cached_input() {
  iso_download_cached_file "$1" "$2" "input ISO"
}

iso_ensure_verified_cached_input() {
  local url="$1"
  local destination="$2"
  local expected_sha256="$3"
  local verification_status

  if [[ -f "$destination" ]]; then
    printf 'Using cached input ISO: %s\n' "$destination"
    if iso_verify_sha256 "$destination" "$expected_sha256"; then
      return 0
    fi
    iso_err "cached input ISO failed verification; downloading a replacement"
    rm -f "$destination"
  fi

  iso_download_cached_input "$url" "$destination"
  if iso_verify_sha256 "$destination" "$expected_sha256"; then
    return 0
  else
    verification_status=$?
  fi
  rm -f "$destination"
  iso_err "removed downloaded input ISO after checksum verification failure"
  return "$verification_status"
}

iso_resolve_latest_everything() {
  local releases_file="$1"
  local architecture="$2"

  [[ -f "$releases_file" ]] || {
    iso_err "Fedora release metadata not found: $releases_file"
    return 1
  }

  jq -er --arg architecture "$architecture" '
    [
      .[]
      | select(
          .variant == "Everything"
          and .subvariant == "Everything"
          and .arch == $architecture
          and (
            .link
            | type == "string"
              and test("^https://download\\.fedoraproject\\.org/pub/fedora/linux/releases/[0-9]+/Everything/")
          )
        )
      | select(.version | type == "string" and test("^[0-9]+$"))
    ]
    | if length == 0 then error("no matching Fedora Everything release") else . end
    | max_by(.version | tonumber)
    | [.version, .arch, .link, .sha256, .size]
    | @tsv
  ' "$releases_file" || {
    iso_err "could not resolve the latest Fedora Everything $architecture release"
    return 1
  }
}

iso_certificate_fingerprint() {
  local certificate_file="$1"
  [[ -f "$certificate_file" ]] || {
    iso_err "Fedora release certificate not found: $certificate_file"
    return 1
  }

  # An fpr record documents the pub or sub record directly before it; only
  # primary-key fingerprints count, so subkeys neither trip the one-key check
  # nor hide a second concatenated certificate.
  local -a fingerprints=()
  mapfile -t fingerprints < <(
    gpg --batch --show-keys --with-colons "$certificate_file" 2>/dev/null |
      awk -F: '
        $1 == "pub" { primary = 1; next }
        $1 == "fpr" && primary { print $10 }
        { primary = 0 }
      '
  )
  [[ "${#fingerprints[@]}" -gt 0 ]] || {
    iso_err "could not read Fedora release certificate fingerprint: $certificate_file"
    return 1
  }
  [[ "${#fingerprints[@]}" -eq 1 ]] || {
    iso_err "Fedora release certificate contains more than one key: $certificate_file"
    return 1
  }
  [[ "${fingerprints[0]}" =~ ^[A-Fa-f0-9]{40}$ ]] || {
    iso_err "could not read Fedora release certificate fingerprint: $certificate_file"
    return 1
  }
  printf '%s\n' "${fingerprints[0]^^}"
}

iso_verified_sha256_from_checksum() {
  local checksum_file="$1"
  local keyring_file="$2"
  local expected_signer="$3"
  local input_name="$4"

  [[ -f "$checksum_file" ]] || {
    iso_err "checksum file not found: $checksum_file"
    return 1
  }
  [[ -f "$keyring_file" ]] || {
    iso_err "Fedora OpenPGP keyring not found: $keyring_file"
    return 1
  }
  [[ "$expected_signer" =~ ^[A-Fa-f0-9]{40}$ ]] || {
    iso_err "invalid expected checksum signer fingerprint: $expected_signer"
    return 1
  }

  local verification_dir verified_checksums status_file verification_status
  verification_dir="$(mktemp -d)"
  verified_checksums="$verification_dir/verified-checksums"
  status_file="$verification_dir/gpg-status"
  if gpgv \
    --keyring "$keyring_file" \
    --status-fd 3 \
    --output "$verified_checksums" \
    "$checksum_file" \
    3>"$status_file"; then
    :
  else
    verification_status=$?
    rm -rf "$verification_dir"
    iso_err "Fedora checksum signature verification failed: $checksum_file"
    return "$verification_status"
  fi

  # VALIDSIG reports the fingerprint of the key that made the signature in
  # field 3 and the primary-key fingerprint in its final field; a signature
  # from a signing subkey of the expected key must also be accepted.
  if ! awk -v signer="${expected_signer^^}" '
    $1 == "[GNUPG:]" && $2 == "VALIDSIG" &&
      (toupper($3) == signer || toupper($NF) == signer) { found = 1 }
    END { exit !found }
  ' "$status_file"; then
    rm -rf "$verification_dir"
    iso_err "checksum signature is not from expected Fedora signer: ${expected_signer^^}"
    return 1
  fi

  local expected_hash
  expected_hash="$(awk -v input_name="$input_name" '
    {
      prefix = "SHA256 (" input_name ") = "
      if (index($0, prefix) == 1) {
        print substr($0, length(prefix) + 1)
      }
    }
  ' "$verified_checksums")"
  rm -rf "$verification_dir"

  [[ "$expected_hash" =~ ^[A-Fa-f0-9]{64}$ ]] || {
    iso_err "verified checksum does not contain one SHA-256 for: $input_name"
    return 1
  }
  printf '%s\n' "${expected_hash,,}"
}

# Resolves the latest stable Fedora Everything release for the requested
# architecture, downloads its netinst ISO into cache_dir, and verifies it
# against Fedora's signed checksum. An optional externally provided SHA-256 is
# cross-checked against the signed value before any ISO download starts. Sets
# resolved_release, resolved_arch, default_input_iso, and default_input_sha256
# for the caller.
iso_prepare_default_input() {
  local cache_dir="$1"
  local architecture="$2"
  local minimum_release="$3"
  local release_key_dir="$4"
  local provided_sha256="${5:-}"

  local metadata_url="https://fedoraproject.org/releases.json"
  local metadata_file="$cache_dir/fedora-releases.json"
  local keyring_url="https://fedoraproject.org/fedora.gpg"
  local keyring_file="$cache_dir/fedora.gpg"

  iso_download_file "$metadata_url" "$metadata_file" "Fedora release metadata"
  local release_record
  release_record="$(iso_resolve_latest_everything "$metadata_file" "$architecture")"
  # Split with mapfile: IFS tab-splitting would collapse an empty field and
  # shift every later field into the wrong variable.
  local -a release_fields=()
  mapfile -t -d $'\t' release_fields < <(printf '%s' "$release_record")
  [[ "${#release_fields[@]}" -eq 5 ]] || {
    iso_err "Fedora release metadata returned a malformed release record"
    return 1
  }
  resolved_release="${release_fields[0]}"
  resolved_arch="${release_fields[1]}"
  local metadata_input_url="${release_fields[2]}"
  local metadata_sha256="${release_fields[3]}"
  local metadata_size="${release_fields[4]}"

  [[ "$resolved_arch" == "$architecture" ]] || {
    iso_err "Fedora release metadata returned unexpected architecture: ${resolved_arch:-unknown}"
    return 1
  }
  iso_validate_supported_platform "$resolved_release" "$resolved_arch" "$minimum_release"
  local expected_input_url_prefix="https://download.fedoraproject.org/pub/fedora/linux/releases/${resolved_release}/Everything/${resolved_arch}/iso/"
  [[ "$metadata_input_url" == "$expected_input_url_prefix"* ]] || {
    iso_err "Fedora release metadata returned unexpected download URL: ${metadata_input_url:-missing}"
    return 1
  }
  [[ "$metadata_sha256" =~ ^[A-Fa-f0-9]{64}$ ]] || {
    iso_err "Fedora release metadata returned an invalid SHA-256"
    return 1
  }
  [[ "$metadata_size" =~ ^[0-9]+$ ]] || {
    iso_err "Fedora release metadata returned an invalid ISO size"
    return 1
  }

  local input_basename="${metadata_input_url##*/}"
  local input_pattern="^Fedora-Everything-netinst-${resolved_arch}-([0-9]+)-([0-9]+\.[0-9]+)\.iso$"
  [[ "$input_basename" =~ $input_pattern ]] || {
    iso_err "Fedora release metadata returned an unexpected Everything filename: $input_basename"
    return 1
  }
  [[ "${BASH_REMATCH[1]}" == "$resolved_release" ]] || {
    iso_err "Fedora release metadata version does not match its Everything filename"
    return 1
  }
  local compose_version="${BASH_REMATCH[2]}"
  local checksum_basename="Fedora-Everything-${resolved_release}-${compose_version}-${resolved_arch}-CHECKSUM"
  local checksum_url="${metadata_input_url%/*}/$checksum_basename"
  local checksum_file="$cache_dir/$checksum_basename"
  local release_certificate="$release_key_dir/RPM-GPG-KEY-fedora-${resolved_release}-primary"
  local checksum_signer
  checksum_signer="$(iso_certificate_fingerprint "$release_certificate")"

  printf 'Resolved latest Fedora Everything release: %s %s\n' "$resolved_release" "$resolved_arch"
  local checksum_was_cached=0
  if [[ -f "$checksum_file" ]]; then
    checksum_was_cached=1
  fi
  iso_download_cached_file "$checksum_url" "$checksum_file" "Fedora checksum"
  iso_download_file "$keyring_url" "$keyring_file" "Fedora OpenPGP keyring"

  local verification_status=0
  default_input_sha256="$(iso_verified_sha256_from_checksum \
    "$checksum_file" \
    "$keyring_file" \
    "$checksum_signer" \
    "$input_basename")" || verification_status=$?
  if [[ "$verification_status" -ne 0 && "$checksum_was_cached" -eq 1 ]]; then
    iso_err "cached Fedora checksum failed verification; downloading a replacement"
    rm -f "$checksum_file"
    iso_download_file "$checksum_url" "$checksum_file" "Fedora checksum"
    verification_status=0
    default_input_sha256="$(iso_verified_sha256_from_checksum \
      "$checksum_file" \
      "$keyring_file" \
      "$checksum_signer" \
      "$input_basename")" || verification_status=$?
  fi
  if [[ "$verification_status" -ne 0 ]]; then
    rm -f "$checksum_file"
    iso_err "removed Fedora checksum after signature verification failure"
    return "$verification_status"
  fi
  printf 'Verified Fedora checksum signature: %s\n' "$checksum_signer"

  if [[ "$default_input_sha256" != "${metadata_sha256,,}" ]]; then
    iso_err "Fedora's signed checksum does not match its release metadata"
    return 1
  fi
  if [[ -n "$provided_sha256" && "${provided_sha256,,}" != "$default_input_sha256" ]]; then
    iso_err "provided input SHA-256 does not match Fedora's signed checksum"
    return 1
  fi

  default_input_iso="$cache_dir/$input_basename"
  iso_ensure_verified_cached_input "$metadata_input_url" "$default_input_iso" "$default_input_sha256"
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

  iso_write_checkout_stamp "$repo_dir" "$destination/config/iso-payload.conf"
}
