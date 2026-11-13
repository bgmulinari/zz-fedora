#!/usr/bin/env bash
set -Eeuo pipefail

# Shared netwatch capture-privilege contract. netwatch needs raw packet capture
# and eBPF process attribution; the Homebrew binary ships without either. The
# grant follows netwatch's own recipe: the real binary becomes root:netwatch
# 0750 and carries file capabilities, so only netwatch group members can run
# it with them. File capabilities live on the inode, and every brew upgrade
# pours a new keg, so the installer custom action (lib/actions/netwatch.sh)
# and the post-install updater (bin/zz.d/update) both apply this contract.
# Both callers provide run_cmd_as_root (lib/idempotency.sh) and DRY_RUN.

NETWATCH_GROUP="netwatch"
NETWATCH_CAPS=(cap_net_raw cap_bpf cap_perfmon)

# netwatch_capture_binary <link> prints the real file behind the netwatch
# command link (bin/netwatch -> Cellar/netwatch/<version>/bin/netwatch).
netwatch_capture_binary() {
  local link="$1" binary
  binary="$(readlink -f -- "$link" 2>/dev/null)" || return 1
  [[ -f "$binary" ]] || return 1
  printf '%s\n' "$binary"
}

netwatch_capture_member() {
  local user="$1"
  id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qxF "$NETWATCH_GROUP"
}

# netwatch_capture_caps_present <binary> succeeds when every required
# capability is in the binary's effective, inheritable, and permitted sets.
netwatch_capture_caps_present() {
  local binary="$1" caps cap
  caps="$(getcap "$binary" 2>/dev/null)" || return 1
  caps="${caps#"$binary"}"
  caps="${caps//[[:space:]]/}"
  [[ "$caps" == *=eip ]] || return 1
  caps=",${caps%=eip},"
  for cap in "${NETWATCH_CAPS[@]}"; do
    [[ "$caps" == *",$cap,"* ]] || return 1
  done
}

# netwatch_capture_granted <link> <user> verifies the whole grant: group
# membership, root:netwatch 0750 ownership, and the file capabilities.
netwatch_capture_granted() {
  local link="$1" user="$2" binary
  binary="$(netwatch_capture_binary "$link")" || return 1
  netwatch_capture_member "$user" || return 1
  [[ "$(stat -c '%U:%G:%a' -- "$binary" 2>/dev/null)" == "root:$NETWATCH_GROUP:750" ]] || return 1
  netwatch_capture_caps_present "$binary"
}

# netwatch_capture_grant <link> <user> applies the grant idempotently. It
# sets NETWATCH_CAPTURE_NEW_MEMBER=1 when <user> was just added to the group,
# because netwatch will not start for them until their next login.
netwatch_capture_grant() {
  local link="$1" user="$2" binary caps
  # shellcheck disable=SC2034  # Consumed by bin/zz.d/update.
  NETWATCH_CAPTURE_NEW_MEMBER=0
  if ! binary="$(netwatch_capture_binary "$link")"; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'DRY-RUN: grant netwatch capture privileges to %s for %s\n' "$link" "$user"
      return 0
    fi
    log_error "netwatch is not installed at $link"
    return 1
  fi
  netwatch_capture_granted "$link" "$user" && return 0

  getent group "$NETWATCH_GROUP" >/dev/null 2>&1 \
    || run_cmd_as_root groupadd --system "$NETWATCH_GROUP"
  if ! netwatch_capture_member "$user"; then
    run_cmd_as_root usermod -aG "$NETWATCH_GROUP" "$user"
    # shellcheck disable=SC2034  # Consumed by bin/zz.d/update.
    NETWATCH_CAPTURE_NEW_MEMBER=1
  fi
  caps="$(IFS=,; printf '%s' "${NETWATCH_CAPS[*]}")"
  run_cmd_as_root chown "root:$NETWATCH_GROUP" "$binary"
  run_cmd_as_root chmod 0750 "$binary"
  run_cmd_as_root setcap "$caps+eip" "$binary"
}
