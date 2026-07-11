#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/bgmulinari/zz-fedora.git"
REF=""
INSTALL_DIR="${HOME}/zz-fedora"
FORWARD_ARGS=()
DRY_RUN=0
ASSUME_YES=0
NO_TUI=0

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

require_fedora_host() {
  [[ -f /etc/os-release ]] || {
    printf 'Unsupported system: /etc/os-release not found\n' >&2
    exit 1
  }
  local platform_id
  platform_id="$(awk -F= '$1=="ID"{gsub(/"/, "", $2); print tolower($2)}' /etc/os-release)"
  [[ "$platform_id" == "fedora" ]] || {
    printf 'ZZ Fedora requires Fedora Linux; detected: %s\n' "${platform_id:-unknown}" >&2
    exit 1
  }
}

need_sudo() {
  [[ "$EUID" -eq 0 ]] && return 1
  command -v sudo >/dev/null 2>&1 || {
    printf 'sudo is required when not running as root\n' >&2
    exit 1
  }
  return 0
}

bootstrap_notice() {
  local packages="ca-certificates curl git gum bats dnf-plugins-core dnf5-plugins"
  printf 'ZZ Fedora bootstrap\n'
  printf 'This will install Fedora bootstrap packages, clone or update %s, and then launch the installer.\n' "$INSTALL_DIR"
  if [[ -n "$REF" ]]; then
    printf 'Ref: %s\n' "$REF"
  else
    printf 'Ref: current/default checkout\n'
  fi
  printf 'Packages: %s\n' "$packages"
}

bootstrap_confirm() {
  if [[ "$ASSUME_YES" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  if command -v gum >/dev/null 2>&1 && [[ "$NO_TUI" -eq 0 && -t 0 && -t 1 ]]; then
    gum confirm --prompt.foreground "" --selected.background 12 "Continue with bootstrap?"
    return $?
  fi

  local input_fd=0
  if [[ ! -t 0 ]]; then
    if [[ -r /dev/tty ]]; then
      input_fd=9
      exec 9</dev/tty
    else
      printf 'Bootstrap confirmation requires an interactive terminal. Re-run with --yes to skip confirmation.\n' >&2
      exit 1
    fi
  fi

  local reply=""
  if ! IFS= read -r -u "$input_fd" -p "Continue with bootstrap? [y/N] " reply; then
    reply=""
  fi
  [[ "$input_fd" -eq 9 ]] && exec 9<&-
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        REPO_URL="$2"
        shift 2
        ;;
      --ref)
        REF="$2"
        shift 2
        ;;
      --dir)
        INSTALL_DIR="$2"
        shift 2
        ;;
      --yes)
        ASSUME_YES=1
        FORWARD_ARGS+=("--yes")
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        FORWARD_ARGS+=("--dry-run")
        shift
        ;;
      --no-tui)
        NO_TUI=1
        FORWARD_ARGS+=("--no-tui")
        shift
        ;;
      *)
        FORWARD_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

bootstrap_fedora() {
  if need_sudo; then
    run sudo dnf install -y ca-certificates curl git gum bats dnf-plugins-core dnf5-plugins
  else
    run dnf install -y ca-certificates curl git gum bats dnf-plugins-core dnf5-plugins
  fi
}

clone_or_update_repo() {
  if [[ ! -d "$INSTALL_DIR/.git" ]]; then
    run git clone --filter=blob:none "$REPO_URL" "$INSTALL_DIR"
  fi
  if [[ "$DRY_RUN" -eq 0 && -n "$(git -C "$INSTALL_DIR" status --porcelain)" ]]; then
    printf 'Refusing to update %s because it has uncommitted changes. Commit, stash, or move them before bootstrapping again.\n' "$INSTALL_DIR" >&2
    exit 1
  fi
  run git -C "$INSTALL_DIR" fetch --all --tags --prune
  if [[ -n "$REF" ]]; then
    checkout_ref
  else
    update_current_ref
  fi
}

checkout_ref() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run git -C "$INSTALL_DIR" checkout "$REF"
    return 0
  fi

  if git -C "$INSTALL_DIR" show-ref --verify --quiet "refs/remotes/origin/$REF"; then
    run git -C "$INSTALL_DIR" checkout -B "$REF" "origin/$REF"
    return 0
  fi

  if git -C "$INSTALL_DIR" rev-parse --verify --quiet "$REF^{commit}" >/dev/null; then
    run git -C "$INSTALL_DIR" checkout "$REF"
    return 0
  fi

  printf 'Could not resolve ref after fetch: %s\n' "$REF" >&2
  exit 1
}

update_current_ref() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: keep current/default checkout in %s\n' "$INSTALL_DIR"
    return 0
  fi

  local current_branch upstream
  current_branch="$(git -C "$INSTALL_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "$current_branch" ]]; then
    printf 'No --ref provided and %s is on a detached HEAD; leaving checkout unchanged.\n' "$INSTALL_DIR"
    return 0
  fi

  upstream="$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z "$upstream" ]] && git -C "$INSTALL_DIR" show-ref --verify --quiet "refs/remotes/origin/$current_branch"; then
    upstream="origin/$current_branch"
  fi
  if [[ -z "$upstream" ]]; then
    printf 'No --ref provided and branch %s has no upstream; leaving checkout unchanged.\n' "$current_branch"
    return 0
  fi

  run git -C "$INSTALL_DIR" merge --ff-only "$upstream"
}

exec_installer() {
  local command="$1"
  shift

  if [[ "$command" == "wizard" && ! -t 0 ]]; then
    if [[ -r /dev/tty ]]; then
      exec "$INSTALL_DIR/install.sh" "$command" "$@" < /dev/tty
    fi
    printf 'Wizard mode needs an interactive terminal. Re-run from a TTY or use --yes for non-interactive install.\n' >&2
    exit 1
  fi

  exec "$INSTALL_DIR/install.sh" "$command" "$@"
}

main() {
  parse_args "$@"
  require_fedora_host
  bootstrap_notice
  if ! bootstrap_confirm; then
    printf 'Bootstrap cancelled.\n'
    exit 0
  fi
  bootstrap_fedora
  clone_or_update_repo
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    exec_installer install --yes "${FORWARD_ARGS[@]}"
  fi
  exec_installer wizard "${FORWARD_ARGS[@]}"
}

main "$@"
