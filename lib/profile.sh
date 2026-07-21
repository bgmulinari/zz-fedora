#!/usr/bin/env bash
set -Eeuo pipefail

# Desktop-app-profile resolution: decides whether the install targets a full
# or minimal desktop app set and which base bundles that implies.

desktop_app_profile_value() {
  case "${DESKTOP_APP_PROFILE:-auto}" in
    auto|full|minimal)
      printf '%s\n' "${DESKTOP_APP_PROFILE:-auto}"
      ;;
    *)
      die "Unsupported desktop app profile: $DESKTOP_APP_PROFILE"
      ;;
  esac
}

existing_full_desktop_detected() {
  local current_desktop="${XDG_CURRENT_DESKTOP:-}"
  local desktop_session="${DESKTOP_SESSION:-}"
  local lowered marker

  lowered="$(printf '%s:%s\n' "$current_desktop" "$desktop_session" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    *gnome*|*kde*|*plasma*)
      return 0
      ;;
  esac

  for marker in \
    /usr/share/wayland-sessions/gnome.desktop \
    /usr/share/xsessions/gnome.desktop \
    /usr/share/wayland-sessions/plasma.desktop \
    /usr/share/xsessions/plasma.desktop; do
    [[ -f "$marker" ]] && return 0
  done

  for marker in gnome-shell plasmashell startplasma-wayland startplasma-x11; do
    command -v "$marker" >/dev/null 2>&1 && return 0
  done

  return 1
}

resolved_desktop_app_profile() {
  local profile
  profile="$(desktop_app_profile_value)"
  if [[ "$profile" == "auto" ]]; then
    if existing_full_desktop_detected; then
      printf 'minimal\n'
    else
      printf 'full\n'
    fi
    return 0
  fi
  printf '%s\n' "$profile"
}

minimal_desktop_skips_bundle() {
  array_contains "$1" "${MINIMAL_DESKTOP_SKIP_BUNDLE_IDS[@]:-}"
}

effective_base_bundle_ids() {
  local profile bundle_id
  catalog_ensure_loaded
  profile="$(resolved_desktop_app_profile)"

  for bundle_id in "${BASE_BUNDLE_IDS[@]:-}"; do
    if [[ "$profile" == "minimal" ]] && minimal_desktop_skips_bundle "$bundle_id"; then
      continue
    fi
    printf '%s\n' "$bundle_id"
  done
}
