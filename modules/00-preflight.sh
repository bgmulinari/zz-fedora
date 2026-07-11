#!/usr/bin/env bash
set -Eeuo pipefail

module_00_preflight() {
  local git_checkout=0
  log_progress "Checking shell, repository, and operating system"
  [[ "${BASH_VERSINFO[0]}" -ge 4 ]] || die "Bash 4+ is required"
  [[ -f /etc/os-release ]] || [[ "$COMMAND" == "print-plan" || "$COMMAND" == "check" || "$COMMAND" == "list-choices" || "$COMMAND" == "list-sources" ]] || die "/etc/os-release not found"
  if [[ -d "$ROOT_DIR/.git" || -f "$ROOT_DIR/.git" ]]; then
    git_checkout=1
  elif command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_checkout=1
  fi
  [[ "$git_checkout" -eq 1 || -f "$ROOT_DIR/config/iso-payload.conf" ]] \
    || die "Repository root is neither a Git checkout nor a verified ISO payload: $ROOT_DIR"
  log_progress "Checking target user and home directory"
  id "$TARGET_USER" >/dev/null 2>&1 || die "Target user does not exist: $TARGET_USER"
  [[ -d "$TARGET_HOME" ]] || die "Target home does not exist: $TARGET_HOME"
  log_progress "Checking privilege helper availability"
  if [[ "$EUID" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required unless running as root"
  fi
  if [[ "$COMMAND" == "wizard" ]]; then
    have_cmd gum || die "gum is required for wizard mode"
  fi
  if [[ "$DRY_RUN" -ne 1 && "$COMMAND" != "print-plan" && "$COMMAND" != "check" && "$COMMAND" != "list-choices" && "$COMMAND" != "list-sources" ]]; then
    have_cmd dnf || die "dnf is required for Fedora installs"
  fi
  log_progress "Acquiring installer lock"
  acquire_lock
  if [[ "$DRY_RUN" -ne 1 && "$COMMAND" != "print-plan" && "$COMMAND" != "check" && "$COMMAND" != "list-choices" && "$COMMAND" != "list-sources" ]]; then
    log_progress "Refreshing elevated command credentials"
    start_sudo_keepalive
  fi
  printf 'Platform: Fedora Linux\n'
  printf 'Target user: %s\n' "$TARGET_USER"
  printf 'Target home: %s\n' "$TARGET_HOME"
  printf 'Mode: %s\n' "$COMMAND"
  printf 'Dry-run: %s\n' "$DRY_RUN"
  printf 'Desktop app profile: %s\n' "$(resolved_desktop_app_profile)"
  printf 'Selected profiles: base\n'
  printf 'Selected choices:\n'
  local category
  for category in $(category_names); do
    printf '  %s=%s\n' "$category" "$(join_by , $(effective_choice_ids "$category"))"
  done
}
