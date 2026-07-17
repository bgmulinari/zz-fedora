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

STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/zz-fedora}"
CACHE_DIR="${CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zz-fedora}"
CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zz-fedora}"

LOG_DIR="${LOG_DIR:-$STATE_DIR/logs}"
PLAN_DIR="$STATE_DIR/plan"
SAVED_SELECTIONS="$CONFIG_DIR/selections.conf"
# shellcheck disable=SC2034  # Consumed by lib/idempotency.sh.
LOCK_FILE="$STATE_DIR/install.lock"
LOG_FILE="${LOG_FILE:-}"
STATE_OWNER_USER="${STATE_OWNER_USER:-}"

mkdir -p "$STATE_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$LOG_DIR"

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
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
USE_SAVED_SELECTIONS="${USE_SAVED_SELECTIONS:-0}"
SKIP_DOTFILES="${SKIP_DOTFILES:-0}"
STOW_ADOPT="${STOW_ADOPT:-0}"
NO_TUI="${NO_TUI:-0}"
INSTALL_WEAK_DEPS="${INSTALL_WEAK_DEPS:-0}"
VERIFY_INSTALLS="${VERIFY_INSTALLS:-1}"
PLAN_FORMAT="${PLAN_FORMAT:-text}"
COMMAND_PREVIEW="${COMMAND_PREVIEW:-0}"
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

ensure_state_dirs() {
  mkdir -p \
    "$STATE_DIR" \
    "$CACHE_DIR" \
    "$CONFIG_DIR" \
    "$LOG_DIR" \
    "$PLAN_DIR"
}
