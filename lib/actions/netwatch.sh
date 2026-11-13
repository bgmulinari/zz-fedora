#!/usr/bin/env bash
set -Eeuo pipefail

# netwatch-capture custom action: grants the Homebrew netwatch binary its
# packet-capture and eBPF capabilities, gated by the netwatch group. The grant
# contract is shared with `zz update brew` via lib/netwatch.sh, which re-applies
# it to the new keg each netwatch upgrade pours.

install_netwatch_capture() {
  log_progress "Granting netwatch capture privileges to the $NETWATCH_GROUP group"
  netwatch_capture_grant "$BREW_PREFIX/bin/netwatch" "$TARGET_USER"
}

verify_netwatch_capture() {
  netwatch_capture_granted "$BREW_PREFIX/bin/netwatch" "$TARGET_USER"
}

register_action "netwatch-capture" install_netwatch_capture verify_netwatch_capture
