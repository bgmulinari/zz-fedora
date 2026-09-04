#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/bgmulinari/zz-fedora.git"
INSTALL_DIR="${HOME}/.zz"
FORWARD_ARGS=()
BOOTSTRAP_REF=""
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
  local packages="ca-certificates curl git gum python3 dnf5-plugins"
  printf 'ZZ Fedora bootstrap\n'
  printf 'This will install Fedora bootstrap packages, clone or update %s, and then launch the installer.\n' "$INSTALL_DIR"
  if [[ -n "$BOOTSTRAP_REF" ]]; then
    printf 'Updates: origin branch %s (--ref)\n' "$BOOTSTRAP_REF"
  else
    printf 'Updates: current upstream Git branch\n'
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
        printf '%s\n' '--repo is not supported; ZZ is installed and updated from the official Git repository.' >&2
        exit 1
        ;;
      --ref)
        if [[ $# -lt 2 || -z "${2:-}" || "${2:0:1}" == "-" ]]; then
          printf '%s\n' '--ref requires an origin branch name.' >&2
          exit 1
        fi
        BOOTSTRAP_REF="$2"
        shift 2
        ;;
      --ref=*)
        BOOTSTRAP_REF="${1#--ref=}"
        [[ -n "$BOOTSTRAP_REF" ]] || {
          printf '%s\n' '--ref requires an origin branch name.' >&2
          exit 1
        }
        shift
        ;;
      --dir)
        printf '%s\n' '--dir is not supported; ZZ is installed and updated from ~/.zz.' >&2
        exit 1
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
    run sudo dnf install -y ca-certificates curl git gum python3 dnf5-plugins
  else
    run dnf install -y ca-certificates curl git gum python3 dnf5-plugins
  fi
}

clone_or_update_repo() {
  if [[ -n "$BOOTSTRAP_REF" ]] && ! git check-ref-format --branch "$BOOTSTRAP_REF" >/dev/null 2>&1; then
    printf 'Invalid branch name for --ref: %s\n' "$BOOTSTRAP_REF" >&2
    exit 1
  fi
  if [[ -d "$INSTALL_DIR" && ! -d "$INSTALL_DIR/.git" ]]; then
    if [[ -f "$INSTALL_DIR/config/iso-payload.conf" ]]; then
      local snapshot_backup
      snapshot_backup="${INSTALL_DIR}.iso-snapshot.$(date +%Y%m%d%H%M%S)"
      if [[ "$DRY_RUN" -eq 1 ]]; then
        printf 'DRY-RUN: move ISO snapshot %s -> %s\n' "$INSTALL_DIR" "$snapshot_backup"
      else
        mv "$INSTALL_DIR" "$snapshot_backup"
        printf 'Moved prior ISO snapshot to %s before cloning the Git repository.\n' "$snapshot_backup"
      fi
    else
      printf 'Refusing to clone into existing non-Git directory: %s\n' "$INSTALL_DIR" >&2
      exit 1
    fi
  fi
  if [[ ! -d "$INSTALL_DIR/.git" ]]; then
    local -a clone_args=(--filter=blob:none --depth=1)
    [[ -n "$BOOTSTRAP_REF" ]] && clone_args+=(--branch "$BOOTSTRAP_REF")
    run git clone "${clone_args[@]}" "$REPO_URL" "$INSTALL_DIR"
  else
    local existing_origin
    existing_origin="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
    [[ -n "$existing_origin" ]] || {
      printf 'Refusing to use %s because it has no origin remote.\n' "$INSTALL_DIR" >&2
      exit 1
    }
    [[ "$existing_origin" == "$REPO_URL" ]] || {
      printf 'Refusing to use %s because origin is %s, expected %s.\n' "$INSTALL_DIR" "$existing_origin" "$REPO_URL" >&2
      exit 1
    }
  fi
  if [[ "$DRY_RUN" -eq 0 && -n "$(git -C "$INSTALL_DIR" status --porcelain)" ]]; then
    printf 'Refusing to update %s because it has uncommitted changes. Stash, move, or discard them before bootstrapping again.\n' "$INSTALL_DIR" >&2
    exit 1
  fi
  run git -C "$INSTALL_DIR" fetch --prune origin
  switch_to_bootstrap_ref || return 1
  update_current_ref
}

# Check out the branch requested with --ref on an existing install. The
# bootstrap clone is a single-branch shallow clone whose fetch refspec only
# covers its original branch, so the requested branch is registered in the
# refspec (letting later `fetch --prune origin` runs keep updating it) and
# fetched explicitly before switching to it.
switch_to_bootstrap_ref() {
  [[ -n "$BOOTSTRAP_REF" ]] || return 0
  local current_branch refspec already_on_ref=0
  current_branch="$(git -C "$INSTALL_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [[ "$current_branch" == "$BOOTSTRAP_REF" ]] && already_on_ref=1
  refspec="+refs/heads/$BOOTSTRAP_REF:refs/remotes/origin/$BOOTSTRAP_REF"
  if ! git -C "$INSTALL_DIR" config --get-all remote.origin.fetch 2>/dev/null |
    grep -Fxq -e "$refspec" -e '+refs/heads/*:refs/remotes/origin/*'; then
    run git -C "$INSTALL_DIR" config --add remote.origin.fetch "$refspec"
  fi
  run git -C "$INSTALL_DIR" fetch origin "$refspec" || {
    printf 'Could not fetch branch %s from origin.\n' "$BOOTSTRAP_REF" >&2
    return 1
  }
  [[ "$already_on_ref" -eq 1 ]] && return 0
  if git -C "$INSTALL_DIR" show-ref --verify --quiet "refs/heads/$BOOTSTRAP_REF"; then
    run git -C "$INSTALL_DIR" switch "$BOOTSTRAP_REF"
  else
    run git -C "$INSTALL_DIR" switch --track "origin/$BOOTSTRAP_REF"
  fi
}

update_current_ref() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: keep current/default checkout in %s\n' "$INSTALL_DIR"
    return 0
  fi

  local current_branch upstream current_commit upstream_commit updated_commit
  current_branch="$(git -C "$INSTALL_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "$current_branch" ]]; then
    printf 'Refusing to bootstrap from %s because it is on a detached HEAD.\n' "$INSTALL_DIR" >&2
    return 1
  fi

  upstream="$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z "$upstream" ]] && git -C "$INSTALL_DIR" show-ref --verify --quiet "refs/remotes/origin/$current_branch"; then
    upstream="origin/$current_branch"
  fi
  if [[ -z "$upstream" ]]; then
    printf 'Refusing to bootstrap branch %s because it has no upstream branch.\n' "$current_branch" >&2
    return 1
  fi
  [[ "$upstream" == origin/* ]] || {
    printf 'Refusing to bootstrap branch %s from non-origin upstream %s.\n' \
      "$current_branch" "$upstream" >&2
    return 1
  }

  current_commit="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
  upstream_commit="$(git -C "$INSTALL_DIR" rev-parse "$upstream")"
  [[ "$current_commit" == "$upstream_commit" ]] && return 0
  if ! git -C "$INSTALL_DIR" merge-base --is-ancestor "$current_commit" "$upstream_commit"; then
    printf 'Refusing to update %s because it contains commits not present in %s.\n' \
      "$INSTALL_DIR" "$upstream" >&2
    printf 'Keep development commits in a separate checkout before updating the product tree.\n' >&2
    return 1
  fi
  run git -C "$INSTALL_DIR" merge --ff-only "$upstream"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    updated_commit="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
    [[ "$updated_commit" == "$upstream_commit" ]] || {
      printf 'Failed to converge %s to %s.\n' "$INSTALL_DIR" "$upstream" >&2
      return 1
    }
  fi
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
