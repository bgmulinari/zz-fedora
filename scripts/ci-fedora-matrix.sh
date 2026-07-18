#!/usr/bin/env bash
set -Eeuo pipefail

# Emit the CI Fedora container matrix as a GitHub Actions output line, for
# example: fedora=["44", "latest"]
#
# The matrix covers the minimum supported Fedora release and fedora:latest.
# While the minimum supported release is also the latest stable release, both
# tags point at the same Docker Hub image and the two legs would run the
# identical suite twice, so the latest leg is dropped for as long as the
# published amd64 image digests match (the CI containers are amd64). If the
# digests cannot be resolved, both legs are kept: a redundant run is safer
# than losing latest-release coverage.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/defaults.sh
source "$ROOT_DIR/config/defaults.sh"

# The amd64 image digest is compared instead of the tag's top-level manifest
# digest so both lookups always use the same field: the top-level digest has
# historically been absent from this API, and its images[] fallback ordering
# is not stable across tags.
fedora_tag_digest() {
  local tag="$1"
  local digest
  digest="$(
    curl -fsSL --connect-timeout 5 --max-time 15 --retry 3 \
      "https://hub.docker.com/v2/repositories/library/fedora/tags/$tag" |
      jq -er 'first(.images[] | select(.architecture == "amd64") | .digest)'
  )" || return 1
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

warn_unresolved() {
  local message='could not resolve Docker Hub tag digests; keeping both matrix legs'
  printf '%s\n' "$message" >&2
  # A workflow annotation keeps a persistent fallback visible on the run
  # summary; stderr only, because the step pipes stdout into GITHUB_OUTPUT.
  [[ -z "${GITHUB_ACTIONS:-}" ]] || printf '::warning::%s\n' "$message" >&2
}

matrix="[\"$MINIMUM_FEDORA_RELEASE\", \"latest\"]"
if minimum_digest="$(fedora_tag_digest "$MINIMUM_FEDORA_RELEASE")" &&
  latest_digest="$(fedora_tag_digest latest)"; then
  if [[ "$minimum_digest" == "$latest_digest" ]]; then
    printf 'fedora:latest matches fedora:%s; dropping the duplicate latest leg\n' \
      "$MINIMUM_FEDORA_RELEASE" >&2
    matrix="[\"$MINIMUM_FEDORA_RELEASE\"]"
  fi
else
  warn_unresolved
fi

printf 'fedora=%s\n' "$matrix"
