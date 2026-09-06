#!/usr/bin/env bash
# Sync the DMS, Quickshell, and plugin-registry reference checkouts to the
# versions installed on this machine, through the reference-github-repos skill.
#
# Usage: sync_refs.sh [--dms <ref>] [--quickshell <ref>] [--registry <ref>] [--no-registry]
#
# Without arguments the DMS tag comes from `dms version` (v1.6.0 -> v1.6.0) and
# the Quickshell commit from `qs --version` ("revision <sha>"). The registry has
# no installed counterpart and tracks master unless overridden.
set -Eeuo pipefail

SYNC_SCRIPT="${ZZ_REF_SYNC_SCRIPT:-$HOME/.codex/skills/reference-github-repos/scripts/sync_reference_repo.sh}"
REF_ROOT="${ZZ_REF_ROOT:-/files/dev/ref-repos}"

dms_ref=""
qs_ref=""
registry_ref="master"
with_registry=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dms) dms_ref="$2"; shift 2 ;;
    --quickshell) qs_ref="$2"; shift 2 ;;
    --registry) registry_ref="$2"; shift 2 ;;
    --no-registry) with_registry=0; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[[ -x "$SYNC_SCRIPT" || -f "$SYNC_SCRIPT" ]] ||
  { printf 'reference sync script not found: %s\n' "$SYNC_SCRIPT" >&2; exit 1; }

if [[ -z "$dms_ref" ]]; then
  if command -v dms >/dev/null 2>&1; then
    # "dms v1.6.0" -> "v1.6.0"; upstream tags carry the v prefix.
    dms_ref="$(dms version 2>/dev/null | awk 'NR==1 {print $NF}')"
    [[ "$dms_ref" == v* ]] || dms_ref="v$dms_ref"
  fi
  [[ -n "$dms_ref" ]] ||
    { printf 'dms is not installed; pass --dms <tag>\n' >&2; exit 1; }
fi

if [[ -z "$qs_ref" ]]; then
  if command -v qs >/dev/null 2>&1; then
    # "Quickshell 0.3.1 (revision 2d3b3e9c..., distributed by ...)"
    qs_ref="$(qs --version 2>/dev/null | sed -n 's/.*revision \([0-9a-f]\{7,40\}\).*/\1/p' | head -n1)"
  fi
  [[ -n "$qs_ref" ]] ||
    { printf 'could not read the Quickshell revision; pass --quickshell <commit>\n' >&2; exit 1; }
fi

sync() {
  local repo="$1" ref="$2"
  printf '\n== %s @ %s ==\n' "$repo" "$ref"
  bash "$SYNC_SCRIPT" "$repo" "$ref"
}

sync AvengeMedia/DankMaterialShell "$dms_ref"
sync quickshell-mirror/quickshell "$qs_ref"

# Proc.runCommand, most qs.Widgets components, and the shared services live in
# the dank-qml-common submodule, which a shallow reference clone does not
# populate. Sync it as its own checkout at the exact commit the DMS tree pins.
dms_dir="$REF_ROOT/AvengeMedia/DankMaterialShell"
common_ref="$(git -C "$dms_dir" ls-tree HEAD dank-qml-common 2>/dev/null | awk '$2 == "commit" {print $3}')"
if [[ -n "$common_ref" ]]; then
  sync AvengeMedia/dank-qml-common "$common_ref" ||
    printf 'dank-qml-common sync failed; Proc/widget sources will be unavailable\n' >&2
else
  printf 'no dank-qml-common submodule pinned in %s; skipping\n' "$dms_ref" >&2
fi
if [[ "$with_registry" -eq 1 ]]; then
  sync AvengeMedia/dms-plugin-registry "$registry_ref" ||
    printf 'registry sync failed; continuing without it\n' >&2
fi

schema_upstream="$dms_dir/quickshell/PLUGINS/plugin-schema.json"
schema_local="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets/plugin-schema.json"
if [[ -f "$schema_upstream" && -f "$schema_local" ]] && ! cmp -s "$schema_upstream" "$schema_local"; then
  printf '\nNOTE: the bundled plugin-schema.json differs from %s; refresh it with:\n  cp %q %q\n' \
    "$dms_ref" "$schema_upstream" "$schema_local" >&2
fi

cat <<EOF

Reference checkouts:
  DMS         $dms_dir
  Common      $REF_ROOT/AvengeMedia/dank-qml-common  (Proc, qs.Widgets, shared services)
  Quickshell  $REF_ROOT/quickshell-mirror/quickshell
  Registry    $REF_ROOT/AvengeMedia/dms-plugin-registry
Upstream plugin skill:
  $dms_dir/.agents/skills/dms-plugin-dev/SKILL.md
EOF
