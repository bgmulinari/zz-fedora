#!/usr/bin/env bash
set -Eeuo pipefail

# Runtime bootstrap: repository defaults, XDG/state paths, global flag
# defaults, and sourcing of the shared libraries. Existing call sites keep
# working by sourcing only this file.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../config/defaults.sh
source "$ROOT_DIR/config/defaults.sh"
# shellcheck source=./log.sh
source "$ROOT_DIR/lib/log.sh"
# shellcheck source=./util.sh
source "$ROOT_DIR/lib/util.sh"
# shellcheck source=./profile.sh
source "$ROOT_DIR/lib/profile.sh"
# shellcheck source=./catalog.sh
source "$ROOT_DIR/lib/catalog.sh"
# shellcheck source=./selections.sh
source "$ROOT_DIR/lib/selections.sh"
# shellcheck source=./desktop-defaults.sh
source "$ROOT_DIR/lib/desktop-defaults.sh"

# Derive the base-install bundle sets from bundle metadata so every consumer
# of EARLY_BASE_BUNDLE_IDS/BASE_BUNDLE_IDS sees the catalog-backed values.
load_base_bundle_catalog

STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/zz-fedora}"
CACHE_DIR="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz-fedora}"
CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zz-fedora}"
# Normalize env overrides once at assignment: everything downstream (path
# prefix matches, the chown_state_path_to_owner walk) relies on these roots
# carrying no trailing slashes.
normalize_dir_var STATE_DIR
normalize_dir_var CACHE_DIR
normalize_dir_var CONFIG_DIR

LOG_DIR="${LOG_DIR:-$STATE_DIR/logs}"
normalize_dir_var LOG_DIR
PLAN_DIR="$STATE_DIR/plan"
SAVED_SELECTIONS="$CONFIG_DIR/selections.conf"
# shellcheck disable=SC2034  # Consumed by lib/idempotency.sh.
LOCK_FILE="$STATE_DIR/install.lock"
LOG_FILE="${LOG_FILE:-}"
STATE_OWNER_USER="${STATE_OWNER_USER:-}"

# When install.sh runs as root on behalf of a non-root state owner (sudo
# elevation or the installer-ISO add-on), directories created in root context
# under the state tree must be handed to that owner as they are created, or
# later user-context writes (dotfile backups, saved selections) fail mid-run
# before the exit-time restore_state_ownership pass.
state_owner_fixup_required() {
  # The fork-free owner check runs first so normal user-owned runs return
  # without spawning any id lookups.
  [[ -n "${STATE_OWNER_USER:-}" && "$STATE_OWNER_USER" != "root" ]] || return 1
  [[ "$EUID" -eq 0 ]] || return 1
  id "$STATE_OWNER_USER" >/dev/null 2>&1
}

state_owner_group() {
  id -gn "$STATE_OWNER_USER" 2>/dev/null
}

# Chown a path and its ancestors up to the containing state root to the state
# owner. Chown to the current owner is a no-op, so repeated calls stay
# idempotent.
chown_state_path_to_owner() {
  local path="$1"
  state_owner_fixup_required || return 0
  normalize_dir_var path
  local owner_group state_root
  owner_group="$(state_owner_group)" || return 0
  for state_root in "$STATE_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$LOG_DIR"; do
    # Roots are normalized at assignment; normalize again so a reassigned
    # override with trailing slashes cannot break the equality check that
    # terminates the walk, and never treat / as a root.
    normalize_dir_var state_root
    [[ "$state_root" != "/" ]] || continue
    [[ "$path" == "$state_root" || "$path" == "$state_root"/* ]] || continue
    while :; do
      # -h keeps a symlink leaf (preserved by cp -a backups) from
      # dereferencing to a target outside the state tree. A failed handoff
      # is warned once so a later user-context failure leaves a trail;
      # log.sh may not be fully initialized here, so write stderr directly.
      if ! chown -h "$STATE_OWNER_USER:$owner_group" "$path" 2>/dev/null; then
        if [[ "${STATE_OWNER_CHOWN_WARNED:-0}" -eq 0 ]]; then
          STATE_OWNER_CHOWN_WARNED=1
          printf 'WARN: could not hand %s to %s; later user-context writes under the state tree may fail\n' \
            "$path" "$STATE_OWNER_USER" >&2
        fi
      fi
      [[ "$path" == "$state_root" ]] && break
      path="$(dirname "$path")"
      # Hard stop: the walk must never reach the filesystem root, and a
      # relative path must never spin on `dirname . = .`.
      [[ "$path" == "/" || "$path" == "." ]] && break
    done
    return 0
  done
  return 0
}

ensure_state_dirs() {
  mkdir -p "$STATE_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$LOG_DIR" "$PLAN_DIR"
  # PLAN_DIR is excluded from the handoff: plan_reset recreates it in
  # installer context, nothing writes under it from user context mid-run,
  # and the exit-time restore_state_ownership pass hands it over with the
  # rest of STATE_DIR.
  local dir
  for dir in "$STATE_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$LOG_DIR"; do
    chown_state_path_to_owner "$dir"
  done
}

ensure_state_dirs

# Shared runtime state protocol. These globals are declared here so every lib
# and module sees one instance; the writers/readers are:
# - WARNING_MESSAGES / INFO_MESSAGES: appended by lib/planner.sh and modules
#   while planning; drained for display by lib/planner.sh and lib/tui.sh.
# - PLAN_MODULES: populated by lib/planner.sh; read by install.sh and
#   lib/tui.sh to render the plan.
# - ACTIVE_STEP_LABEL/ID/CURRENT/TOTAL/STARTED_AT: driven by the step runner
#   in install.sh; read by lib/log.sh and the failure summary for context.
# - LAST_COMMAND_CONTEXT: written by lib/idempotency.sh and lib/log.sh to
#   describe the most recent external command for failure reporting.
# shellcheck disable=SC2034
declare -ag WARNING_MESSAGES=()
# shellcheck disable=SC2034
declare -ag INFO_MESSAGES=()
# shellcheck disable=SC2034
declare -ag PLAN_MODULES=()

COMMAND="${COMMAND:-$DEFAULT_COMMAND}"
TARGET_USER="${TARGET_USER:-$DEFAULT_TARGET_USER}"
TARGET_HOME="${TARGET_HOME:-}"
MODE="${MODE:-$DEFAULT_COMMAND}"
# Externally-settable overrides carry the ZZ_ prefix; the short names below
# are the internal working globals, seeded here from the ZZ_* environment and
# then updated by CLI flag parsing. The unprefixed names are not read from the
# caller's environment. Several are consumed only by later-sourced libraries
# and modules, hence the SC2034 suppressions.
DRY_RUN="${ZZ_DRY_RUN:-0}"
# shellcheck disable=SC2034
ASSUME_YES="${ZZ_ASSUME_YES:-0}"
# shellcheck disable=SC2034
USE_SAVED_SELECTIONS=0
# shellcheck disable=SC2034
SKIP_DOTFILES="${ZZ_SKIP_DOTFILES:-0}"
# shellcheck disable=SC2034
STOW_ADOPT=0
NO_TUI="${ZZ_NO_TUI:-0}"
# shellcheck disable=SC2034
INSTALL_WEAK_DEPS="${ZZ_INSTALL_WEAK_DEPS:-0}"
# shellcheck disable=SC2034
VERIFY_INSTALLS="${ZZ_VERIFY_INSTALLS:-1}"
PLAN_FORMAT=text
# shellcheck disable=SC2034
COMMAND_PREVIEW=0
DESKTOP_APP_PROFILE="${DESKTOP_APP_PROFILE:-$DEFAULT_DESKTOP_APP_PROFILE}"
PREFERRED_BROWSER="${PREFERRED_BROWSER:-}"
LOCK_ACQUIRED="${LOCK_ACQUIRED:-0}"
LOCK_FD="${LOCK_FD:-}"
FAILURE_SUMMARY_PRINTED="${FAILURE_SUMMARY_PRINTED:-0}"
IN_FATAL_HANDLER="${IN_FATAL_HANDLER:-0}"
ACTIVE_STEP_LABEL="${ACTIVE_STEP_LABEL:-}"
ACTIVE_STEP_ID="${ACTIVE_STEP_ID:-}"
ACTIVE_STEP_CURRENT="${ACTIVE_STEP_CURRENT:-0}"
ACTIVE_STEP_TOTAL="${ACTIVE_STEP_TOTAL:-0}"
ACTIVE_STEP_STARTED_AT="${ACTIVE_STEP_STARTED_AT:-}"
LAST_COMMAND_CONTEXT="${LAST_COMMAND_CONTEXT:-}"
