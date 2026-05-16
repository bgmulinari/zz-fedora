#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/bgmulinari/zz-linux-setup.git"
REF="main"
INSTALL_DIR="${HOME}/zz-linux-setup"
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

detect_distro() {
  [[ -f /etc/os-release ]] || {
    printf 'Unsupported system: /etc/os-release not found\n' >&2
    exit 1
  }
  local distro
  distro="$(awk -F= '$1=="ID"{gsub(/"/, "", $2); print tolower($2)}' /etc/os-release)"
  case "$distro" in
    fedora) printf '%s\n' "$distro" ;;
    *) printf 'Unsupported distro: %s\n' "$distro" >&2; exit 1 ;;
  esac
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
  local distro="$1"
  local packages
  case "$distro" in
    fedora) packages="ca-certificates curl git gum dnf-plugins-core dnf5-plugins" ;;
    *) packages="system prerequisites" ;;
  esac

  printf 'ZZ Linux Setup bootstrap\n'
  printf 'This will install bootstrap packages for %s, clone or update %s, and then launch the installer.\n' "$distro" "$INSTALL_DIR"
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
    run sudo dnf install -y ca-certificates curl git gum dnf-plugins-core dnf5-plugins
  else
    run dnf install -y ca-certificates curl git gum dnf-plugins-core dnf5-plugins
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
  checkout_ref
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
  local distro
  distro="$(detect_distro)"
  bootstrap_notice "$distro"
  if ! bootstrap_confirm; then
    printf 'Bootstrap cancelled.\n'
    exit 0
  fi
  case "$distro" in
    fedora) bootstrap_fedora ;;
  esac
  clone_or_update_repo
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    exec_installer install --yes "${FORWARD_ARGS[@]}"
  fi
  exec_installer wizard "${FORWARD_ARGS[@]}"
}

main "$@"
