#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-linux-setup-hardening.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

run_installer() {
  local name="$1"
  shift
  local case_root="$TEST_ROOT/$name"
  mkdir -p "$case_root"
  XDG_STATE_HOME="$case_root/state" \
  XDG_CACHE_HOME="$case_root/cache" \
  XDG_CONFIG_HOME="$case_root/config" \
  bash "$ROOT_DIR/install.sh" "$@"
}

json_plan="$(run_installer json print-plan --distro fedora --dry-run --format json)"
[[ "${json_plan:0:1}" == "{" ]]
grep -F '"distro":"fedora"' <<<"$json_plan" >/dev/null
grep -F '"selected_bundles":' <<<"$json_plan" >/dev/null
grep -F '"source_details":' <<<"$json_plan" >/dev/null
grep -F '"native_packages":' <<<"$json_plan" >/dev/null
grep -F '"flatpaks":' <<<"$json_plan" >/dev/null
grep -F '"custom_actions":' <<<"$json_plan" >/dev/null
grep -F '"services":' <<<"$json_plan" >/dev/null
grep -F '"stow_packages":' <<<"$json_plan" >/dev/null
grep -F '"managed_files":' <<<"$json_plan" >/dev/null
grep -F '"managed_config_policy":' <<<"$json_plan" >/dev/null
grep -F '"base_rationale":' <<<"$json_plan" >/dev/null
grep -F '"gpg_policy":"unsigned-bootstrap"' <<<"$json_plan" >/dev/null
grep -F '"warnings":' <<<"$json_plan" >/dev/null
! grep -F 'Log file:' <<<"$json_plan" >/dev/null

check_output="$(run_installer check check --distro fedora --dry-run --no-tui)"
grep -F 'Readiness:' <<<"$check_output" >/dev/null
grep -F 'noctalia-v4 command:qs' <<<"$check_output" >/dev/null
grep -F 'managed-config ~/.config/autostart/zz-first-run.desktop: first-run' <<<"$check_output" >/dev/null
grep -F 'Fatal readiness issues:' <<<"$check_output" >/dev/null
grep -F 'package-manager locks' <<<"$check_output" >/dev/null
grep -F 'disk ' <<<"$check_output" >/dev/null
grep -F 'network internet' <<<"$check_output" >/dev/null
grep -F 'portal command:xdg-desktop-portal' <<<"$check_output" >/dev/null
[[ ! -e "$TEST_ROOT/check/config/zz-linux-setup/selections.conf" ]]

grep -F 'register_step base-setup' "$ROOT_DIR/install.sh" | grep -F ' fatal' >/dev/null
grep -F 'register_step optional-packages' "$ROOT_DIR/install.sh" | grep -F ' continue' >/dev/null
! grep -F 'base-bootstrap|base-login-manager' "$ROOT_DIR/modules/30-packages.sh" >/dev/null
grep -F 'EARLY_BASE_BUNDLE_IDS_fedora' "$ROOT_DIR/config/defaults.sh" >/dev/null
grep -F 'base-jetbrains-mono-nerd-font' "$ROOT_DIR/config/defaults.sh" >/dev/null
! grep -F 'shell-zsh' "$ROOT_DIR/choices/fedora/"*.conf >/dev/null

for source_file in "$ROOT_DIR"/sources/fedora/**/*.source; do
  grep -F 'SOURCE_GPG_POLICY=' "$source_file" >/dev/null
  grep -F 'SOURCE_BOOTSTRAP_EXCEPTION=' "$source_file" >/dev/null
  grep -F 'SOURCE_REASON=' "$source_file" >/dev/null
done
grep -F 'SOURCE_GPG_POLICY="unsigned-bootstrap"' "$ROOT_DIR/sources/fedora/terra/terra.source" >/dev/null
grep -F 'SOURCE_BOOTSTRAP_EXCEPTION=1' "$ROOT_DIR/sources/fedora/terra/terra.source" >/dev/null
grep -F $'dnf\tgnome-software\tdefault-app' "$ROOT_DIR/config/base-responsibility.tsv" >/dev/null
grep -F $'dnf\tddcutil\tdesktop-service' "$ROOT_DIR/config/base-responsibility.tsv" >/dev/null
grep -F $'source\tterra\tnoctalia' "$ROOT_DIR/config/base-responsibility.tsv" >/dev/null
grep -F $'~/.config/noctalia/settings.json\tseed-if-missing\tpreserve' "$ROOT_DIR/config/managed-config.tsv" >/dev/null

(
  export XDG_STATE_HOME="$TEST_ROOT/source-state"
  export XDG_CACHE_HOME="$TEST_ROOT/source-cache"
  export XDG_CONFIG_HOME="$TEST_ROOT/source-config"
  export TARGET_USER="${USER:-$(id -un)}"
  export TARGET_HOME="$TEST_ROOT/home"
  mkdir -p "$TARGET_HOME/.config/noctalia" "$TARGET_HOME/.config/niri"
  printf 'existing shell\n' >"$TARGET_HOME/.bashrc"
  printf 'existing templates\n' >"$TARGET_HOME/.config/noctalia/user-templates.toml"

  # shellcheck source=../lib/common.sh
  source "$ROOT_DIR/lib/common.sh"
  # shellcheck source=../lib/packages.sh
  source "$ROOT_DIR/lib/packages.sh"
  # shellcheck source=../lib/sources.sh
  source "$ROOT_DIR/lib/sources.sh"
  # shellcheck source=../lib/files.sh
  source "$ROOT_DIR/lib/files.sh"
  # shellcheck source=../lib/stow.sh
  source "$ROOT_DIR/lib/stow.sh"
  # shellcheck source=../lib/planner.sh
  source "$ROOT_DIR/lib/planner.sh"
  # shellcheck source=../lib/readiness.sh
  source "$ROOT_DIR/lib/readiness.sh"

  DISTRO=fedora
  DRY_RUN=1
  build_plan_from_selections
  grep -F '~/.bashrc' "$PLAN_DIR/files/config-conflicts.tsv" >/dev/null
  grep -F '~/.config/noctalia/user-templates.toml' "$PLAN_DIR/files/config-conflicts.tsv" >/dev/null
  grep -F $'action\tjetbrains-mono-nerd-font-fedora\tbase-jetbrains-mono-nerd-font' "$PLAN_DIR/base-rationale.tsv" >/dev/null
  grep -F $'flatpak\torg.gtk.Gtk3theme.adw-gtk3\tbase-source-flathub\ttheme-font' "$PLAN_DIR/base-rationale.tsv" >/dev/null
  grep -F $'source\tterra\tbase-noctalia\tnoctalia' "$PLAN_DIR/base-rationale.tsv" >/dev/null
  grep -F $'~/.bashrc\tstow\tbackup-before-stow\tshell' "$PLAN_DIR/files/managed-config-policy.tsv" >/dev/null
  grep -F $'~/.config/noctalia/settings.json\tseed-if-missing\tpreserve\tnoctalia-settings' "$PLAN_DIR/files/managed-config-policy.tsv" >/dev/null
  generate_readiness_status
  grep -F $'config-conflict\t~/.bashrc\tconflict\twarn' "$(readiness_file)" >/dev/null
  grep -F $'managed-config\t~/.config/noctalia/settings.json\tseed-if-missing\tinfo' "$(readiness_file)" >/dev/null
)

grep -Fx 'brightnessctl' "$ROOT_DIR/packages/fedora/official/wayland-tools.pkgs" >/dev/null
grep -Fx 'ddcutil' "$ROOT_DIR/packages/fedora/official/wayland-tools.pkgs" >/dev/null
! grep -Fx 'swappy' "$ROOT_DIR/packages/fedora/official/wayland-tools.pkgs" >/dev/null
! grep -Fx 'wf-recorder' "$ROOT_DIR/packages/fedora/official/wayland-tools.pkgs" >/dev/null
grep -Fx 'nm-connection-editor' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'blueman' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'file-roller' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'gnome-disk-utility' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'ImageMagick' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'mpv' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'pwvucontrol' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'tesseract' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'tesseract-langpack-eng' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'simple-scan' "$ROOT_DIR/packages/fedora/official/desktop-apps.pkgs" >/dev/null
grep -Fx 'cups' "$ROOT_DIR/packages/fedora/official/system-services.pkgs" >/dev/null
grep -Fx 'system-config-printer' "$ROOT_DIR/packages/fedora/official/system-services.pkgs" >/dev/null
grep -Fx 'ipp-usb' "$ROOT_DIR/packages/fedora/official/system-services.pkgs" >/dev/null
grep -Fx 'avahi' "$ROOT_DIR/packages/fedora/official/system-services.pkgs" >/dev/null
grep -Fx 'nss-mdns' "$ROOT_DIR/packages/fedora/official/system-services.pkgs" >/dev/null
grep -Fx 'evolution-data-server' "$ROOT_DIR/packages/fedora/official/system-services.pkgs" >/dev/null
grep -Fx '  cups' "$ROOT_DIR/config/defaults.sh" >/dev/null
grep -Fx '  avahi-daemon' "$ROOT_DIR/config/defaults.sh" >/dev/null

grep -F 'noctalia-shell' "$ROOT_DIR/packages/fedora/terra/noctalia.pkgs" >/dev/null
grep -F 'Noctalia v4' "$ROOT_DIR/README.md" >/dev/null

printf 'hardening ok\n'
