#!/usr/bin/env bash
set -Eeuo pipefail

# Compare the live DMS state against the seeded ZZ defaults, and move a
# difference in either direction.
#
# This is the maintainer path for the workflow in docs/dotfiles-layering.md:
# change something in the DMS Settings UI, see what moved, then either keep it
# as a product default or throw it away. It reads the installed shell's own
# specs so an untouched DMS default is never mistaken for a deliberate choice.
#
#   scripts/dms-seed-diff.sh                    # list the differences
#   scripts/dms-seed-diff.sh --apply            # live  -> seed  (promote)
#   scripts/dms-seed-diff.sh --reset            # seed  -> live  (discard)
#   scripts/dms-seed-diff.sh --apply cornerRadius showDock
#   scripts/dms-seed-diff.sh --json             # machine-readable report
#
# --reset rewrites the user's live DMS files, so it backs each one up first and
# then restarts the shell. The restart is not cosmetic: DMS keeps its settings
# in memory and rewrites the file on any later change, so an unrestarted shell
# would quietly undo the reset. Pass --no-restart to skip it when DMS is not
# the running session, and --yes to skip the confirmation prompt.
#
# Exits 1 when differences are found and neither direction was chosen, so it
# can gate a check; exits 0 when the seed and the live state already agree.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=../lib/dms.sh
source "$ROOT_DIR/lib/dms.sh"

require_system_python

DMS_UNIT="dms.service"
resetting=0
restart=1
assume_yes="${ZZ_ASSUME_YES:-0}"
py_args=()

for arg in "$@"; do
  case "$arg" in
    --reset) resetting=1; py_args+=("$arg") ;;
    --no-restart) restart=0 ;;
    --yes | -y) assume_yes=1 ;;
    *) py_args+=("$arg") ;;
  esac
done

# The keys lib/dms.sh renders from a host fact rather than from a seed file.
# Passing them in lets the comparison report an icon-theme or wallpaper change
# and name the helper to edit, instead of silently ignoring it.
TARGET_HOME="${ZZ_DMS_SEED_HOME:-$HOME}"
derived_facts="$(jq -n \
  --arg themeFile "$(dms_theme_file)" \
  --arg iconTheme "$(dms_icon_theme)" \
  --arg wallpaper "$(dms_default_wallpaper)" \
  '{
    settings: {
      customThemeFile: $themeFile,
      iconThemeDark: $iconTheme,
      iconThemeLight: $iconTheme
    },
    session: {wallpaperPath: $wallpaper}
  }')"

BINDS_SEED="$ROOT_DIR/templates/niri/dms-binds.kdl"
BINDS_LIVE="$TARGET_HOME/.config/niri/dms/binds.kdl"

# Parse both sides with DMS's own parser rather than diffing KDL text: DMS
# rewrites the fragment on the first UI edit, re-sorting binds and dropping
# the seed's comments, so a textual diff would report churn forever. Staging
# the seed under a throwaway XDG_CONFIG_HOME is what lets `dms keybinds show`
# read it as though it were the live fragment.
keybind_payloads() {
  local stage
  stage="$(mktemp -d)" || return 1
  mkdir -p "$stage/niri/dms"
  cp "$ROOT_DIR/dotfiles/niri/.config/niri/config.kdl" "$stage/niri/config.kdl"
  cp "$ROOT_DIR/templates/niri/dms-colors.kdl" "$stage/niri/dms/colors.kdl"
  cp "$BINDS_SEED" "$stage/niri/dms/binds.kdl"

  local seed_json live_json
  seed_json="$(XDG_CONFIG_HOME="$stage" dms keybinds show niri 2>/dev/null)" || seed_json=""
  live_json="$(dms keybinds show niri 2>/dev/null)" || live_json=""
  rm -rf "$stage"

  [[ -n "$seed_json" && -n "$live_json" ]] || return 1
  jq -n --argjson seed "$seed_json" --argjson live "$live_json" \
    '{seed: $seed, live: $live}'
}

binds_payload=""
if [[ -r "$BINDS_SEED" && -r "$BINDS_LIVE" ]] && command -v dms >/dev/null 2>&1; then
  binds_payload="$(keybind_payloads)" || binds_payload=""
fi
if [[ -z "$binds_payload" ]]; then
  printf 'note: skipping the keybind comparison (needs the dms CLI and %s).\n' \
    "$BINDS_LIVE" >&2
fi

run_report() {
  "$SYSTEM_PYTHON" "$ROOT_DIR/lib/dms_seed_diff.py" \
    --root "$ROOT_DIR" \
    --home "$TARGET_HOME" \
    --spec-dir "${ZZ_DMS_SPEC_DIR:-$(dms_shell_dir)/Common/settings}" \
    --derived "$derived_facts" \
    --binds "$binds_payload" \
    --binds-seed "$BINDS_SEED" \
    --binds-live "$BINDS_LIVE" \
    "${py_args[@]}"
}

# Reporting, --apply, and --json all end here. A non-zero status means
# differences remain, which is the documented gating signal rather than a
# failure, so it is passed through untouched.
if [[ "$resetting" -eq 0 ]]; then
  run_report || exit $?
  exit 0
fi

dms_running() {
  systemctl --user is-active --quiet "$DMS_UNIT" 2>/dev/null
}

if [[ "$assume_yes" -ne 1 && -t 0 ]]; then
  printf 'This overwrites the live DMS state under %s with the ZZ defaults.\n' \
    "$TARGET_HOME"
  if [[ "$restart" -eq 1 ]] && dms_running; then
    printf 'The %s user unit will be restarted so the change takes effect.\n' \
      "$DMS_UNIT"
  fi
  read -r -p 'Continue? [y/N] ' reply
  [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]] || {
    printf 'Aborted; nothing was changed.\n' >&2
    exit 1
  }
fi

run_report

if [[ "$restart" -eq 0 ]]; then
  printf 'Skipped the %s restart. DMS rewrites its settings from memory, so ' \
    "$DMS_UNIT" >&2
  printf 'restart it before changing anything in the Settings UI.\n' >&2
  exit 0
fi

if dms_running; then
  printf 'Restarting %s so the shell reloads the reset state.\n' "$DMS_UNIT" >&2
  systemctl --user restart "$DMS_UNIT"
else
  printf '%s is not running; nothing to restart.\n' "$DMS_UNIT" >&2
fi
