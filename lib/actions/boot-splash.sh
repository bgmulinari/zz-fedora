#!/usr/bin/env bash
set -Eeuo pipefail

# Plymouth graphical boot splash custom action. The packages come from the
# base-boot-splash dnf bundle (packages/official/boot-splash.pkgs); this action
# covers the two pieces a package install alone cannot: the rhgb/quiet kernel
# arguments (Anaconda only adds them when Plymouth was part of the original
# install transaction, so minimal installs lack them) and an initramfs rebuild
# (installing Plymouth after the kernel leaves the existing initramfs without
# the splash and the graphical LUKS passphrase prompt).

BOOT_SPLASH_KERNEL_ARGS="rhgb quiet"
BOOT_SPLASH_MODULES_ROOT="/lib/modules"
BOOT_SPLASH_BOOT_DIR="/boot"
BOOT_SPLASH_DRACUT_CONF="/etc/dracut.conf"
BOOT_SPLASH_DRACUT_CONF_DIR="/etc/dracut.conf.d"
BOOT_SPLASH_INITRAMFS_STATE=""

boot_splash_action_skipped() {
  local skip_file="$PLAN_DIR/system-skips.tsv"
  [[ -f "$skip_file" ]] || return 1
  awk -F'\t' '$1 == "action" && $2 == "boot-splash" { found = 1 } END { exit !found }' "$skip_file"
}

# An explicit plymouth omission in the host's dracut configuration means the
# administrator does not want a splash; it also doubles as the opt-out knob.
boot_splash_dracut_omits_plymouth() {
  local conf_file
  for conf_file in "$BOOT_SPLASH_DRACUT_CONF" "$BOOT_SPLASH_DRACUT_CONF_DIR"/*.conf; do
    [[ -f "$conf_file" ]] || continue
    if grep -E '^[[:space:]]*omit_dracutmodules' "$conf_file" 2>/dev/null | grep -q plymouth; then
      return 0
    fi
  done
  return 1
}

# Sets BOOT_SPLASH_INITRAMFS_STATE (memoized until refreshed):
#   ready       every bootable kernel's initramfs contains Plymouth
#   stale       at least one bootable kernel needs an initramfs rebuild
#   unsupported no vmlinuz/initramfs layout under /boot to inspect (UKI,
#               systemd-boot, or container runs without /boot)
# Kernels are keyed on /boot/vmlinuz-<version> so leftover module trees from
# removed kernels do not count, and a bootable kernel with a missing image is
# stale rather than silently skipped. The lsinitrd listing is captured, not
# piped into grep -q, so an early match cannot SIGPIPE the producer under
# pipefail and misreport a ready image.
boot_splash_initramfs_state() {
  [[ -n "$BOOT_SPLASH_INITRAMFS_STATE" ]] && return 0
  local modules_dir version image listing found=0 stale=0
  for modules_dir in "$BOOT_SPLASH_MODULES_ROOT"/*/; do
    [[ -d "$modules_dir" ]] || continue
    version="$(basename "$modules_dir")"
    [[ -f "$BOOT_SPLASH_BOOT_DIR/vmlinuz-$version" ]] || continue
    found=1
    image="$BOOT_SPLASH_BOOT_DIR/initramfs-$version.img"
    if [[ ! -f "$image" ]]; then
      stale=1
      break
    fi
    if ! listing="$(lsinitrd "$image" 2>/dev/null)"; then
      stale=1
      break
    fi
    if [[ "$listing" != *plymouthd* ]]; then
      stale=1
      break
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    BOOT_SPLASH_INITRAMFS_STATE="unsupported"
  elif [[ "$stale" -eq 1 ]]; then
    BOOT_SPLASH_INITRAMFS_STATE="stale"
  else
    BOOT_SPLASH_INITRAMFS_STATE="ready"
  fi
}

boot_splash_refresh_initramfs_state() {
  BOOT_SPLASH_INITRAMFS_STATE=""
  boot_splash_initramfs_state
}

# Every kernel entry must carry both arguments for the splash to survive
# kernel selection; grubby runs directly because the installer is root here.
boot_splash_kernel_args_configured() {
  local info
  info="$(grubby --info=ALL 2>/dev/null)" || return 1
  printf '%s\n' "$info" | awk '
    BEGIN { entries = 0; ok = 1 }
    /^args=/ {
      entries++
      if ($0 !~ /[" ]rhgb[" ]/ || $0 !~ /[" ]quiet[" ]/) ok = 0
    }
    END { exit (entries > 0 && ok) ? 0 : 1 }
  '
}

ensure_boot_splash_kernel_args() {
  if boot_splash_kernel_args_configured; then
    log_info "Kernel arguments already include: $BOOT_SPLASH_KERNEL_ARGS"
    return 0
  fi
  log_progress "Adding boot splash kernel arguments: $BOOT_SPLASH_KERNEL_ARGS"
  run_cmd_as_root grubby --update-kernel=ALL --args="$BOOT_SPLASH_KERNEL_ARGS"
}

# dracut targets every installed kernel rather than uname -r so the rebuild
# also works from the installer ISO chroot, where the running kernel is the
# installer's, not the installed system's.
ensure_boot_splash_initramfs() {
  boot_splash_initramfs_state
  if [[ "$BOOT_SPLASH_INITRAMFS_STATE" == "ready" ]]; then
    log_info "Initramfs already contains the Plymouth boot splash"
    return 0
  fi
  log_progress "Rebuilding the initramfs with the Plymouth boot splash"
  run_cmd_as_root dracut -f --regenerate-all || return 1
  boot_splash_refresh_initramfs_state
  [[ "$BOOT_SPLASH_INITRAMFS_STATE" == "ready" ]] \
    || die "Initramfs rebuild completed but the Plymouth boot splash could not be confirmed in the rebuilt images."
}

install_boot_splash() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: ensure boot splash kernel arguments: %s\n' "$BOOT_SPLASH_KERNEL_ARGS"
    printf 'DRY-RUN: rebuild the initramfs when it lacks the Plymouth boot splash\n'
    return 0
  fi
  if boot_splash_dracut_omits_plymouth; then
    log_warn "dracut configuration omits the plymouth module; skipping boot splash setup for this system."
    record_system_skip action boot-splash "dracut configuration omits the plymouth module"
    return 0
  fi
  if ! have_cmd grubby || ! have_cmd lsinitrd; then
    log_warn "grubby or lsinitrd is unavailable; skipping boot splash setup for this system."
    record_system_skip action boot-splash "grubby or lsinitrd unavailable"
    return 0
  fi
  boot_splash_initramfs_state
  if [[ "$BOOT_SPLASH_INITRAMFS_STATE" == "unsupported" ]]; then
    log_warn "No standard kernel and initramfs layout found under $BOOT_SPLASH_BOOT_DIR; skipping boot splash setup."
    record_system_skip action boot-splash "no standard initramfs layout under $BOOT_SPLASH_BOOT_DIR"
    return 0
  fi
  ensure_boot_splash_kernel_args || return 1
  ensure_boot_splash_initramfs
}

verify_boot_splash() {
  boot_splash_action_skipped && return 0
  boot_splash_kernel_args_configured || return 1
  boot_splash_initramfs_state
  [[ "$BOOT_SPLASH_INITRAMFS_STATE" == "ready" ]]
}

register_action "boot-splash" install_boot_splash verify_boot_splash
