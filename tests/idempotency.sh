#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-linux-setup-idempotency.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_CONFIG_HOME="$TEST_ROOT/config"
export FLATPAK_REMOTE_WAIT_SECONDS=0
export FLATPAK_REMOTE_RETRY_SECONDS=0
export VERIFY_INSTALLS=0

# shellcheck source=../lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=../lib/idempotency.sh
source "$ROOT_DIR/lib/idempotency.sh"
# shellcheck source=../lib/packages.sh
source "$ROOT_DIR/lib/packages.sh"
# shellcheck source=../lib/sources.sh
source "$ROOT_DIR/lib/sources.sh"
# shellcheck source=../lib/systemd.sh
source "$ROOT_DIR/lib/systemd.sh"
# shellcheck source=../lib/files.sh
source "$ROOT_DIR/lib/files.sh"
# shellcheck source=../lib/stow.sh
source "$ROOT_DIR/lib/stow.sh"
# shellcheck source=../lib/planner.sh
source "$ROOT_DIR/lib/planner.sh"
# shellcheck source=../lib/os.sh
source "$ROOT_DIR/lib/os.sh"
# shellcheck source=../modules/80-post-actions.sh
source "$ROOT_DIR/modules/80-post-actions.sh"
# shellcheck source=../modules/05-bootstrap-tools.sh
source "$ROOT_DIR/modules/05-bootstrap-tools.sh"
# shellcheck source=../modules/30-packages.sh
source "$ROOT_DIR/modules/30-packages.sh"
# shellcheck source=../modules/10-sources.sh
source "$ROOT_DIR/modules/10-sources.sh"
# shellcheck source=../modules/35-custom-actions.sh
source "$ROOT_DIR/modules/35-custom-actions.sh"
# shellcheck source=../modules/40-services.sh
source "$ROOT_DIR/modules/40-services.sh"
# shellcheck source=../modules/90-doctor.sh
source "$ROOT_DIR/modules/90-doctor.sh"

DISTRO="fedora"
TARGET_USER="${USER}"
TARGET_HOME="${HOME}"
DRY_RUN=1
load_adapter
noctalia_dnf_output="$(distro_install_dnf_packages noctalia-shell qt6ct 2>&1)"
grep -F "dnf install -y --setopt=best=False --setopt=install_weak_deps=False noctalia-shell qt6ct" <<<"$noctalia_dnf_output" >/dev/null
regular_dnf_output="$(distro_install_dnf_packages qt6ct 2>&1)"
! grep -F -- "--setopt=best=False" <<<"$regular_dnf_output" >/dev/null
media_codecs_output="$(install_fedora_media_codecs 2>&1)"
grep -F -- "--exclude=gstreamer1-plugins-good-qt6" <<<"$media_codecs_output" >/dev/null
add_category_selection "browser" "zen-copr"
add_category_selection "dev" "vscode,neovim"
add_category_selection "ai" "codex,codex"
add_category_selection "dotnet" "tools"
build_plan_from_selections

[[ "$(grep -Fc 'flathub' "$PLAN_DIR/sources/fedora-flatpak-remotes.list")" -eq 1 ]]
[[ "$(grep -Fc 'vendor:vscode' "$PLAN_DIR/sources/fedora-vendor.list")" -eq 1 ]]
[[ "$(grep -Fc 'firefox' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'python3-pip' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'code' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'starship' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'yazi' "$PLAN_DIR/packages/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'copr:atim/starship' "$PLAN_DIR/sources/fedora-copr.list")" -eq 1 ]]
[[ "$(grep -Fc 'copr:lihaohong/yazi' "$PLAN_DIR/sources/fedora-copr.list")" -eq 1 ]]
[[ "$(grep -Fc 'flatpak' "$PLAN_DIR/prereqs/dnf.pkgs")" -eq 1 ]]
[[ "$(grep -Fc 'gnupg2' "$PLAN_DIR/prereqs/dnf.pkgs")" -eq 1 ]]
[[ "$(sort -u "$PLAN_DIR/services/system-enable-now.list" | wc -l | tr -d ' ')" -eq "$(wc -l <"$PLAN_DIR/services/system-enable-now.list" | tr -d ' ')" ]]
[[ "$(sort -u "$PLAN_DIR/stow/packages.list" | wc -l | tr -d ' ')" -eq "$(wc -l <"$PLAN_DIR/stow/packages.list" | tr -d ' ')" ]]
[[ "$(grep -Fc 'brew:codex' "$PLAN_DIR/actions/actions.list")" -eq 1 ]]
[[ "$(grep -Fc 'dotnet-sdk' "$PLAN_DIR/actions/actions.list")" -eq 1 ]]
[[ "$(grep -Fc 'dotnet-tools' "$PLAN_DIR/actions/actions.list")" -eq 1 ]]
[[ "$(grep -Fc 'jetbrains-mono-nerd-font-fedora' "$PLAN_DIR/actions/actions.list")" -eq 1 ]]
grep -Fx 'shell' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'nvim' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'noctalia' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'vscode' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'shell-starship' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'shell-yazi' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'default-apps' "$PLAN_DIR/stow/packages.list" >/dev/null
[[ -z "$(stow_package_required_command portals || true)" ]]
grep -Fx 'nautilus' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'xdg-terminal-exec' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'fontconfig' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'google-noto-sans-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'google-noto-sans-cjk-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'google-noto-color-emoji-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'fontawesome-6-free-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'yaru-icon-theme' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'qt5ct' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'qt6ct' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'sddm' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx '~/.config/niri/config.kdl' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/nvim/plugin/noctalia.lua' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/plugins.json' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/user-templates.toml' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/templates/icon-theme-accent' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/templates/zsh-syntax-highlighting.zsh' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/Code/User/settings.json' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/environment.d/10-niri-gtk.conf' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.local/bin/noctalia-sync-icon-theme' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.local/share/applications/nvim.desktop' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.local/share/nautilus-python/extensions/open-terminal-here.py' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/Wallpapers/SilentPeaks.jpg' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.cache/noctalia/wallpapers.json' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -F 'spawn "xdg-terminal-exec"' "$ROOT_DIR/dotfiles/niri/.config/niri/cfg/keybinds.kdl" >/dev/null
nautilus_niri_rule="$(
  awk '
    /^window-rule \{/ {
      in_rule = 1
      rule = $0 ORS
      matched = 0
      next
    }
    in_rule {
      rule = rule $0 ORS
      if ($0 ~ /org\\\.gnome\\\.Nautilus\|nautilus/) {
        matched = 1
      }
      if ($0 == "}") {
        if (matched) {
          printf "%s", rule
          exit
        }
        in_rule = 0
      }
    }
  ' "$ROOT_DIR/dotfiles/niri/.config/niri/cfg/rules.kdl"
)"
grep -F 'opacity 0.90' <<<"$nautilus_niri_rule" >/dev/null
grep -F 'draw-border-with-background false' <<<"$nautilus_niri_rule" >/dev/null
grep -F 'blur true' <<<"$nautilus_niri_rule" >/dev/null
! grep -F 'off' <<<"$nautilus_niri_rule" >/dev/null
grep -F 'Exec=xdg-terminal-exec' "$ROOT_DIR/dotfiles/default-apps/.local/share/applications/nvim.desktop" >/dev/null
grep -F 'f"--dir={path}"' "$ROOT_DIR/dotfiles/default-apps/.local/share/nautilus-python/extensions/open-terminal-here.py" >/dev/null
grep -F 'QT_QPA_PLATFORMTHEME=qt6ct' "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-niri-gtk.conf" >/dev/null
grep -F 'TERMINAL=xdg-terminal-exec' "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-niri-gtk.conf" >/dev/null
grep -F 'EDITOR=nvim' "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-niri-gtk.conf" >/dev/null
grep -F 'VISUAL=nvim' "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-niri-gtk.conf" >/dev/null
grep -F 'SUDO_EDITOR=nvim' "$ROOT_DIR/dotfiles/environment/.config/environment.d/10-niri-gtk.conf" >/dev/null

default_apps_home="$TEST_ROOT/default-apps-home"
mkdir -p "$default_apps_home"
TARGET_HOME="$default_apps_home"
TARGET_USER="test-user"
DRY_RUN=0
default_apps_output="$(
  run_cmd_as_user() {
    local user="$1"
    shift
    if [[ "$*" == "sh -c "* ]]; then
      HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
    else
      printf 'user:%s:%s\n' "$user" "$*"
    fi
  }
  configure_default_applications
)"
grep -F 'user:test-user:xdg-mime default nvim.desktop text/plain' <<<"$default_apps_output" >/dev/null
grep -F 'user:test-user:xdg-mime default nvim.desktop application/x-shellscript' <<<"$default_apps_output" >/dev/null
! grep -F 'x-scheme-handler/terminal' <<<"$default_apps_output" >/dev/null
grep -F '# Terminal emulator preference order for xdg-terminal-exec' "$default_apps_home/.config/xdg-terminals.list" >/dev/null
grep -Fx 'com.mitchellh.ghostty.desktop' "$default_apps_home/.config/xdg-terminals.list" >/dev/null
grep -Fx 'Alacritty.desktop' "$default_apps_home/.config/xdg-terminals.list" >/dev/null
grep -Fx 'kitty.desktop' "$default_apps_home/.config/xdg-terminals.list" >/dev/null
DRY_RUN=1
TARGET_USER="${USER}"
TARGET_HOME="${HOME}"

settings_home="$TEST_ROOT/settings-home"
mkdir -p "$settings_home/.config/noctalia"
TARGET_HOME="$settings_home"
DRY_RUN=0
update_noctalia_settings
grep -F '"terminalCommand": "ghostty -e"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"directory": "'"$settings_home"'/Wallpapers"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "ghostty"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "pywalfox"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "starship"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "yazi"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "qt"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "kcolorscheme"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"enableUserTheming": true' "$settings_home/.config/noctalia/settings.json" >/dev/null
DRY_RUN=1
TARGET_HOME="${HOME}"

vscode_settings_home="$TEST_ROOT/vscode-settings-home"
mkdir -p "$vscode_settings_home/.config/noctalia" "$vscode_settings_home/.config/Code/User"
TARGET_HOME="$vscode_settings_home"
DRY_RUN=0
update_noctalia_settings
grep -F '"id": "code"' "$vscode_settings_home/.config/noctalia/settings.json" >/dev/null
DRY_RUN=1
TARGET_HOME="${HOME}"

external_templates_home="$TEST_ROOT/external-templates-home"
mkdir -p "$external_templates_home/.config/noctalia" "$external_templates_home/.config/nvim" "$external_templates_home/.config/zen/profile.default/chrome"
TARGET_HOME="$external_templates_home"
DRY_RUN=0
update_noctalia_settings
grep -F '"enableUserTheming": true' "$external_templates_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "zenBrowser"' "$external_templates_home/.config/noctalia/settings.json" >/dev/null
DRY_RUN=1
TARGET_HOME="${HOME}"

wallpaper_seed_home="$TEST_ROOT/wallpaper-seed-home"
mkdir -p "$wallpaper_seed_home"
TARGET_HOME="$wallpaper_seed_home"
DRY_RUN=0
install_noctalia_wallpaper_state
cmp -s "$ROOT_DIR/assets/wallpapers/SilentPeaks.jpg" "$wallpaper_seed_home/Wallpapers/SilentPeaks.jpg"
grep -F '"defaultWallpaper": "'"$wallpaper_seed_home"'/Wallpapers/SilentPeaks.jpg"' "$wallpaper_seed_home/.cache/noctalia/wallpapers.json" >/dev/null
DRY_RUN=1
TARGET_HOME="${HOME}"

firefox_policy_dir="$TEST_ROOT/firefox/distribution"
FIREFOX_DISTRIBUTION_DIR="$firefox_policy_dir"
DRY_RUN=0
install_firefox_pywalfox_extension_policy
jq -e '.policies.ExtensionSettings["pywalfox@frewacom.org"].installation_mode == "normal_installed"' "$firefox_policy_dir/policies.json" >/dev/null
jq -e '.policies.ExtensionSettings["pywalfox@frewacom.org"].install_url == "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi"' "$firefox_policy_dir/policies.json" >/dev/null
unset FIREFOX_DISTRIBUTION_DIR
DRY_RUN=1

firefox_compat_home="$TEST_ROOT/firefox-compat-home"
mkdir -p "$firefox_compat_home/.config/mozilla/firefox"
printf '[Profile0]\nPath=test.default\nIsRelative=1\n' >"$firefox_compat_home/.config/mozilla/firefox/profiles.ini"
TARGET_HOME="$firefox_compat_home"
DRY_RUN=0
ensure_firefox_profile_compat_for_pywalfox
[[ "$(readlink "$firefox_compat_home/.mozilla/firefox")" == "$firefox_compat_home/.config/mozilla/firefox" ]]
DRY_RUN=1
TARGET_HOME="${HOME}"

touch_target="$TEST_ROOT/should-not-exist"
run_cmd touch "$touch_target"
[[ ! -e "$touch_target" ]]

source_file="$TEST_ROOT/source.conf"
dest_file="$TEST_ROOT/dest.conf"
printf 'alpha\n' >"$source_file"
DRY_RUN=0
file_install_if_changed "$source_file" "$dest_file"
checksum_before="$(sha256sum "$dest_file" | awk '{print $1}')"
file_install_if_changed "$source_file" "$dest_file"
checksum_after="$(sha256sum "$dest_file" | awk '{print $1}')"
[[ "$checksum_before" == "$checksum_after" ]]

fake_home="$TEST_ROOT/home"
mkdir -p "$fake_home"
TARGET_HOME="$fake_home"
printf 'existing bashrc\n' >"$TARGET_HOME/.bashrc"
stow_prepare_known_shell_files
[[ ! -e "$TARGET_HOME/.bashrc" ]]
find "$STATE_DIR/backups" -path '*/home/.bashrc' -type f -print -quit | grep -q .

mkdir -p "$TARGET_HOME/.config/niri" "$TARGET_HOME/.config/noctalia"
printf 'binds {}\n' >"$TARGET_HOME/.config/niri/config.kdl"
printf 'generated colors\n' >"$TARGET_HOME/.config/niri/noctalia.kdl"
printf '{}\n' >"$TARGET_HOME/.config/noctalia/settings.json"
printf 'templates\n' >"$TARGET_HOME/.config/noctalia/user-templates.toml"
stow_prepare_package_conflicts niri
stow_prepare_known_conflicts noctalia
[[ -d "$TARGET_HOME/.config/niri" ]]
grep -Fx 'generated colors' "$TARGET_HOME/.config/niri/noctalia.kdl" >/dev/null
[[ -f "$TARGET_HOME/.config/noctalia/settings.json" ]]
[[ ! -e "$TARGET_HOME/.config/noctalia/user-templates.toml" ]]
find "$STATE_DIR/backups" -path '*/home/.config/niri/config.kdl' -type f -print -quit | grep -q .
find "$STATE_DIR/backups" -path '*/home/.config/noctalia/user-templates.toml' -type f -print -quit | grep -q .

install_starship_config
[[ -f "$TARGET_HOME/.config/starship.toml" ]]
grep -F 'palette = "noctalia"' "$TARGET_HOME/.config/starship.toml" >/dev/null
cat >>"$TARGET_HOME/.config/starship.toml" <<'EOF'
# >>> NOCTALIA STARSHIP PALETTE >>>
[palettes.noctalia]
blue = "#81a1c1"
# <<< NOCTALIA STARSHIP PALETTE <<<
EOF
install_starship_config
grep -F '[palettes.noctalia]' "$TARGET_HOME/.config/starship.toml" >/dev/null

fake_bin="$TEST_ROOT/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/kwriteconfig6" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

file=""
group=""
key=""
value=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --file)
      file="$2"
      shift 2
      ;;
    --group)
      group="$2"
      shift 2
      ;;
    --key)
      key="$2"
      shift 2
      ;;
    *)
      value="$1"
      shift
      ;;
  esac
done
target="$HOME/.config/$file"
mkdir -p "$(dirname "$target")"
if ! grep -Fx "[$group]" "$target" >/dev/null 2>&1; then
  printf '\n[%s]\n' "$group" >>"$target"
fi
printf '%s=%s\n' "$key" "$value" >>"$target"
EOF
chmod +x "$fake_bin/kwriteconfig6"
PATH="$fake_bin:$PATH"
install_qt_theme_config
grep -F "color_scheme_path=$TARGET_HOME/.config/qt5ct/colors/noctalia.conf" "$TARGET_HOME/.config/qt5ct/qt5ct.conf" >/dev/null
grep -F "color_scheme_path=$TARGET_HOME/.config/qt6ct/colors/noctalia.conf" "$TARGET_HOME/.config/qt6ct/qt6ct.conf" >/dev/null
grep -F 'custom_palette=true' "$TARGET_HOME/.config/qt5ct/qt5ct.conf" >/dev/null
grep -F 'style=Fusion' "$TARGET_HOME/.config/qt6ct/qt6ct.conf" >/dev/null
grep -F 'widgetStyle=Fusion' "$TARGET_HOME/.config/kdeglobals" >/dev/null

cat >"$fake_bin/gsettings" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exit 0
EOF
cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exit 0
EOF
cat >"$fake_bin/dbus-update-activation-environment" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
exit 0
EOF
chmod +x "$fake_bin/gsettings" "$fake_bin/systemctl" "$fake_bin/dbus-update-activation-environment"
mkdir -p "$TARGET_HOME/.cache/noctalia" "$TARGET_HOME/.local/share/icons/Yaru-purple"
printf '#9141ac\n' >"$TARGET_HOME/.cache/noctalia/icon-theme-accent"
HOME="$TARGET_HOME" XDG_CACHE_HOME="$TARGET_HOME/.cache" "$ROOT_DIR/dotfiles/noctalia/.local/bin/noctalia-sync-icon-theme"
grep -F 'Theme=Yaru-purple' "$TARGET_HOME/.config/kdeglobals" >/dev/null
grep -F 'icon_theme=Yaru-purple' "$TARGET_HOME/.config/qt5ct/qt5ct.conf" >/dev/null
grep -F 'icon_theme=Yaru-purple' "$TARGET_HOME/.config/qt6ct/qt6ct.conf" >/dev/null
rm -f "$TARGET_HOME/.cache/noctalia/icon-theme-accent"
! HOME="$TARGET_HOME" XDG_CACHE_HOME="$TARGET_HOME/.cache" "$ROOT_DIR/dotfiles/noctalia/.local/bin/noctalia-sync-icon-theme" 2>&1 | grep -F 'No such file or directory' >/dev/null

rm -f "$TARGET_HOME/.config/niri/noctalia.kdl"
install_niri_noctalia_seed_if_missing
grep -F 'focus-ring' "$TARGET_HOME/.config/niri/noctalia.kdl" >/dev/null
printf 'generated colors\n' >"$TARGET_HOME/.config/niri/noctalia.kdl"
install_niri_noctalia_seed_if_missing
grep -Fx 'generated colors' "$TARGET_HOME/.config/niri/noctalia.kdl" >/dev/null

noctalia_template_apply="$TEST_ROOT/template-apply.sh"
cat >"$noctalia_template_apply" <<'EOF'
#!/usr/bin/env bash
case "$1" in
starship)
    # Check if the nested starship config exists first
    if [ -f "$HOME/.config/starship/starship.toml" ]; then
        CONFIG_FILE="$HOME/.config/starship/starship.toml"
    else
    # Fallback to the default path
        CONFIG_FILE="$HOME/.config/starship.toml"
    fi

    # Check if the generated palette file exists
    if [ ! -f "$PALETTE_FILE" ]; then
        echo "Error: Starship palette file not found at $PALETTE_FILE" >&2
        exit 1
    fi
    ;;
esac
EOF
chmod +x "$noctalia_template_apply"
NOCTALIA_TEMPLATE_APPLY_PATH="$noctalia_template_apply"
(
  run_cmd_as_root() {
    "$@"
  }
  patch_noctalia_starship_template_apply_if_needed
)
grep -F 'PALETTE_FILE="$HOME/.cache/noctalia/starship-palette.toml"' "$noctalia_template_apply" >/dev/null

mkdir -p "$TARGET_HOME/.cache/noctalia"
cat >"$TARGET_HOME/.cache/noctalia/starship-palette.toml" <<'EOF'
[palettes.noctalia]
blue = "#89b4fa"
EOF
cat >"$noctalia_template_apply" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case "$1" in
starship)
    PALETTE_FILE="$HOME/.cache/noctalia/starship-palette.toml"
    CONFIG_FILE="$HOME/.config/starship.toml"
    {
        printf '\n# >>> NOCTALIA STARSHIP PALETTE >>>\n'
        cat "$PALETTE_FILE"
        printf '# <<< NOCTALIA STARSHIP PALETTE <<<\n'
    } >>"$CONFIG_FILE"
    ;;
esac
EOF
chmod +x "$noctalia_template_apply"
NOCTALIA_TEMPLATE_APPLY_PATH="$noctalia_template_apply"
(
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }
  apply_noctalia_starship_palette_if_available
)
grep -F '[palettes.noctalia]' "$TARGET_HOME/.config/starship.toml" >/dev/null

optional_plan="$TEST_ROOT/optional.pkgs"
printf 'bad-package\ngood-package\n' >"$optional_plan"
install_attempts=()
distro_install_dnf_packages() {
  install_attempts+=("$*")
  [[ " $* " != *" bad-package "* ]]
}
install_from_plan_file dnf "$optional_plan" optional
[[ "${install_attempts[0]}" == "bad-package good-package" ]]
[[ "${install_attempts[1]}" == "bad-package" ]]
[[ "${install_attempts[2]}" == "good-package" ]]

required_plan="$TEST_ROOT/required.pkgs"
printf 'bad-package\ngood-package\n' >"$required_plan"
install_attempts=()
install_from_plan_file dnf "$required_plan" required && exit 1
[[ "${#install_attempts[@]}" -eq 1 ]]

reset_test_selections() {
  CATEGORY_OVERRIDES=()
  CATEGORY_ADDITIONS=()
  CATEGORY_OVERRIDE_PRESENT=()
  local category
  for category in ai browsers dev dotnet gaming media office; do
    set_category_override "$category" ""
  done
}

assert_base_plan_for_distro() {
  local distro="$1"
  local native_plan="$2"
  local base_var="BASE_BUNDLE_IDS_${distro}"
  local -n base_bundle_ids_ref="$base_var"
  local bundle_id plan_file base_item

  DISTRO="$distro"
  TARGET_HOME="${HOME}"
  DRY_RUN=1
  reset_test_selections
  build_plan_from_selections

  for bundle_id in "${base_bundle_ids_ref[@]}"; do
    grep -Fx "$bundle_id" "$PLAN_DIR/bundles.list" >/dev/null
    load_bundle_descriptor "$distro" "$bundle_id"
    plan_file="$(package_file_for_backend "$BUNDLE_INSTALLER")"
    while IFS= read -r base_item; do
      [[ -n "$base_item" ]] || continue
      grep -Fx "$base_item" "$plan_file" >/dev/null
    done < <(manifest_entries "$ROOT_DIR/$BUNDLE_ITEMS_FILE")
  done

  grep -Fx 'niri' "$native_plan" >/dev/null
  grep -Fx 'sddm' "$native_plan" >/dev/null
  grep -Fx 'zsh' "$native_plan" >/dev/null
  grep -Fx 'noctalia-shell' "$native_plan" >/dev/null
}

assert_required_services_are_base_packages() {
  local distro="$1"
  local native_plan="$2"
  local service_name package_name

  DISTRO="$distro"
  TARGET_HOME="${HOME}"
  DRY_RUN=1
  reset_test_selections
  build_plan_from_selections

  for service_name in "${DEFAULT_SYSTEM_SERVICES[@]}"; do
    package_name="$(service_package_for_distro "$service_name")"
    [[ -n "$package_name" ]]
    grep -Fx "$package_name" "$native_plan" >/dev/null
  done
}

assert_package_module_installs_base_before_optional() {
  local distro="$1"
  local first_base_backend="$2"
  local optional_package="$3"
  shift 3
  local -a required_before_optional=("$@")

  DISTRO="$distro"
  TARGET_HOME="${HOME}"
  DRY_RUN=1
  reset_test_selections
  add_category_selection "dev" "vscode"
  build_plan_from_selections

  package_install_calls=()
  package_install_idempotent() {
    local backend="$1"
    shift
    package_install_calls+=("$backend:$*")
    [[ " $* " != *" $optional_package "* ]]
  }
  module_30_packages
  module_32_optional_packages || true

  [[ "${package_install_calls[0]}" == "$first_base_backend":* ]]
  [[ " ${package_install_calls[0]#*:} " == *" sddm "* ]]
  [[ " ${package_install_calls[0]#*:} " == *" power-profiles-daemon "* ]]

  local optional_index=-1
  local found_optional_retry=0
  local idx call required_item found_required
  for idx in "${!package_install_calls[@]}"; do
    call="${package_install_calls[$idx]}"
    if [[ "$optional_index" -eq -1 && (" $call " == *" $optional_package "* || "$call" == *":$optional_package") ]]; then
      optional_index="$idx"
    fi
    [[ "$call" == *":$optional_package" ]] && found_optional_retry=1
  done
  [[ "$optional_index" -gt 0 ]]
  [[ "$found_optional_retry" -eq 1 ]]

  for required_item in "${required_before_optional[@]}"; do
    found_required=0
    for ((idx = 0; idx < optional_index; idx++)); do
      [[ " ${package_install_calls[$idx]#*:} " == *" $required_item "* ]] && found_required=1
    done
    [[ "$found_required" -eq 1 ]]

    for ((idx = optional_index; idx < ${#package_install_calls[@]}; idx++)); do
      [[ " ${package_install_calls[$idx]#*:} " != *" $required_item "* ]]
    done
  done
}

assert_required_base_package_failure_aborts_base_setup() {
  DISTRO="fedora"
  TARGET_HOME="${HOME}"
  DRY_RUN=0
  reset_test_selections
  build_plan_from_selections

  local output
  output="$(
    package_install_idempotent() {
      local backend="$1"
      shift
      printf 'install:%s:%s\n' "$backend" "$*"
      return 1
    }
    distro_service_exists() {
      printf 'unexpected-service-check:%s\n' "$1"
      return 0
    }
    run_cmd_as_root() {
      printf 'unexpected-cmd:%s\n' "$*"
    }
    module_30_packages
  )" && return 1
  DRY_RUN=1

  grep -F 'install:dnf:' <<<"$output" >/dev/null
  ! grep -F 'unexpected-service-check' <<<"$output" >/dev/null
  ! grep -F 'unexpected-cmd' <<<"$output" >/dev/null
}

assert_niri_readiness_failure_aborts_base_setup() {
  DISTRO="fedora"
  TARGET_HOME="${HOME}"
  DRY_RUN=0
  reset_test_selections
  build_plan_from_selections

  local output
  output="$(
    package_install_idempotent() {
      local backend="$1"
      shift
      printf 'install:%s:%s\n' "$backend" "$*"
      return 0
    }
    command() {
      [[ "$1" == "-v" && "${2:-}" == "niri" ]] && return 1
      builtin command "$@"
    }
    distro_service_exists() {
      return 0
    }
    run_cmd_as_root() {
      printf 'cmd:%s\n' "$*"
    }
    enable_required_system_service_now() {
      printf 'service:%s\n' "$1"
    }
    module_30_packages
  )" && return 1
  DRY_RUN=1

  grep -F 'install:dnf:' <<<"$output" | grep -F ' niri ' >/dev/null
}

assert_doctor_fails_when_planned_niri_is_not_ready() {
  DISTRO="fedora"
  COMMAND="doctor"
  TARGET_HOME="$TEST_ROOT/doctor-missing-niri-home"
  DRY_RUN=0
  mkdir -p "$TARGET_HOME"
  reset_test_selections
  build_plan_from_selections

  local output
  set +e
  output="$({
    doctor_check_command() {
      if [[ "$1" == "niri" ]]; then
        printf '[warn] missing command %s\n' "$1"
        return 1
      fi
      command -v "$1" >/dev/null 2>&1
    }
    doctor_check_file() {
      if [[ "$1" == "/usr/share/wayland-sessions/niri.desktop" ]]; then
        printf '[warn] missing file %s\n' "$1"
        return 1
      fi
      [[ -f "$1" ]]
    }
    systemctl() {
      [[ "$1" == "is-enabled" && "$2" != "sddm" ]]
    }
    run_cmd_as_root() {
      return 0
    }
    module_90_doctor || printf 'doctor-status:%s\n' "$?"
  } 2>&1)"
  set -e
  DRY_RUN=1
  COMMAND="install"
  TARGET_HOME="${HOME}"

  grep -F 'missing command niri' <<<"$output" >/dev/null
  grep -F 'missing file /usr/share/wayland-sessions/niri.desktop' <<<"$output" >/dev/null
  grep -F 'service not enabled sddm' <<<"$output" >/dev/null
  ! grep -F '.zsh/noctalia-zsh-syntax-highlighting.zsh' <<<"$output" >/dev/null
  grep -F 'Fatal desktop readiness checks failed' <<<"$output" >/dev/null
  grep -F 'doctor-status:1' <<<"$output" >/dev/null
}

assert_login_manager_failure_aborts_base_setup() {
  DISTRO="fedora"
  TARGET_HOME="${HOME}"
  DRY_RUN=0
  reset_test_selections
  build_plan_from_selections

  local output
  output="$(
    package_install_idempotent() {
      local backend="$1"
      shift
      printf 'install:%s:%s\n' "$backend" "$*"
    }
    distro_service_exists() {
      return 1
    }
    run_cmd_as_root() {
      printf 'cmd:%s\n' "$*"
    }
    enable_required_system_service_now() {
      printf 'service:%s\n' "$1"
    }
    module_30_packages
  )" && return 1
  DRY_RUN=1

  grep -F 'install:dnf:' <<<"$output" >/dev/null
  grep -F 'sddm' <<<"$output" >/dev/null
  grep -F 'cmd:systemctl daemon-reload' <<<"$output" >/dev/null
}

assert_missing_required_service_retries_package() {
  DISTRO="fedora"
  TARGET_HOME="${HOME}"
  DRY_RUN=0
  reset_test_selections
  build_plan_from_selections

  local output
  output="$(
    distro_service_exists() {
      [[ "$1" != "power-profiles-daemon" ]]
    }
    package_install_idempotent() {
      printf 'install:%s:%s\n' "$1" "$2"
    }
    run_cmd_as_root() {
      printf 'cmd:%s\n' "$*"
    }
    distro_enable_service_now() {
      printf 'enable:%s\n' "$1"
    }
    configure_base_system_services
  )" && return 1
  DRY_RUN=1

  grep -F 'install:dnf:power-profiles-daemon' <<<"$output" >/dev/null
  grep -F 'cmd:systemctl daemon-reload' <<<"$output" >/dev/null
  grep -F 'enable:NetworkManager' <<<"$output" >/dev/null
}

assert_dotnet_tools_fail_without_sdk() {
  DISTRO="fedora"
  TARGET_HOME="$TEST_ROOT/missing-dotnet-home"
  DRY_RUN=0
  mkdir -p "$TARGET_HOME"
  reset_test_selections
  build_plan_from_selections

  local output
  output="$({
    install_dotnet_sdks() {
      printf 'sdk-install\n'
    }
    install_dotnet_tools
  } 2>&1)" && return 1
  DRY_RUN=1
  TARGET_HOME="${HOME}"

  grep -F "running SDK install before installing tools" <<<"$output" >/dev/null
  grep -F "sdk-install" <<<"$output" >/dev/null
  grep -F ".NET SDK is still not available" <<<"$output" >/dev/null
}

assert_flatpak_remote_repaired_when_present_but_unusable() {
  local output
  output="$({
    remote_present=1
    mktemp() {
      printf '/tmp/flathub-test.gpg\n'
    }
    curl() {
      printf 'curl:%s\n' "$*" >&2
      [[ "$*" == "-fsSL https://flathub.org/repo/flathub.gpg -o /tmp/flathub-test.gpg" ]]
    }
    chmod() {
      printf 'chmod:%s\n' "$*" >&2
    }
    sleep() {
      :
    }
    flatpak() {
      case "${1#--user}" in
        "")
          shift
          ;;
      esac
      case "$1" in
        remotes)
          [[ "$remote_present" -eq 1 ]] && printf 'flathub\n'
          ;;
        remote-ls)
          [[ "$remote_present" -eq 1 && "$remote_fixed" -eq 1 ]]
          ;;
        *)
          return 1
          ;;
      esac
    }
    run_cmd_as_user() {
      printf 'user:%s:%s\n' "$1" "${*:2}"
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
      if [[ "$*" == "flatpak remote-add --no-gpg-verify flathub https://dl.flathub.org/repo/" ]]; then
        remote_fixed=1
        return 0
      fi
      case "$*" in
        "flatpak remote-delete --force flathub")
          remote_present=0
          return 0
          ;;
        "flatpak remote-add --gpg-import=/tmp/flathub-test.gpg flathub https://dl.flathub.org/repo/")
          remote_present=1
          remote_fixed=1
          return 0
          ;;
      esac
      return 1
    }
    remote_fixed=0
    TARGET_USER="test-user"
    DRY_RUN=0
    flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  } 2>&1)"

  grep -F "Flatpak remote 'flathub' is present but not queryable; checking whether Flathub GPG verification settles." <<<"$output" >/dev/null
  grep -F "Flatpak remote 'flathub' is present but not queryable; re-adding it with the Flathub GPG key." <<<"$output" >/dev/null
  grep -F "root:flatpak remote-delete --force flathub" <<<"$output" >/dev/null
  grep -F "root:flatpak remote-add --gpg-import=/tmp/flathub-test.gpg flathub https://dl.flathub.org/repo/" <<<"$output" >/dev/null
  ! grep -F "user:test-user:flatpak --user remote-add" <<<"$output" >/dev/null
}

assert_flathub_repo_enabled_requires_usable_remote() {
  local output
  output="$({
    flatpak() {
      case "${1#--user}" in
        "")
          shift
          ;;
      esac
      case "$1" in
        remotes)
          printf 'flathub\n'
          ;;
        remote-ls)
          return 1
          ;;
        *)
          return 1
          ;;
      esac
    }
    if distro_repo_enabled flathub; then
      printf 'enabled\n'
    else
      printf 'disabled\n'
    fi
  } 2>&1)"

  grep -Fx "disabled" <<<"$output" >/dev/null
}

assert_flathub_setup_uses_official_system_remote() {
  local output
  output="$({
    remote_fixed=0
    flatpak() {
      case "$1" in
        remotes)
          printf 'fedora\n'
          [[ "$remote_fixed" -eq 1 ]] && printf 'flathub\n'
          return 0
          ;;
        remote-ls)
          [[ "$remote_fixed" -eq 1 ]]
          ;;
        *)
          return 1
          ;;
      esac
    }
    run_cmd_as_user() {
      printf 'user:%s:%s\n' "$1" "${*:2}"
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
      if [[ "$*" == "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" ]]; then
        remote_fixed=1
      fi
    }
    TARGET_USER="test-user"
    DRY_RUN=0
    flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  } 2>&1)"

  grep -F "Removing Fedora Flatpak remote before configuring Flathub" <<<"$output" >/dev/null
  grep -F "root:flatpak remote-delete --force fedora" <<<"$output" >/dev/null
  grep -F "root:flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" <<<"$output" >/dev/null
  ! grep -F "user:test-user:flatpak --user remote-add" <<<"$output" >/dev/null
}

assert_flathub_setup_falls_back_to_direct_gpg_import() {
  local output
  output="$({
    remote_fixed=0
    mktemp() {
      printf '/tmp/flathub-test.gpg\n'
    }
    curl() {
      printf 'curl:%s\n' "$*" >&2
      [[ "$*" == "-fsSL https://flathub.org/repo/flathub.gpg -o /tmp/flathub-test.gpg" ]]
    }
    chmod() {
      printf 'chmod:%s\n' "$*" >&2
    }
    sleep() {
      :
    }
    flatpak() {
      case "$1" in
        remotes)
          [[ "$remote_fixed" -eq 1 ]] && printf 'flathub\n'
          return 0
          ;;
        remote-ls)
          [[ "$remote_fixed" -eq 1 ]]
          ;;
        *)
          return 1
          ;;
      esac
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
      if [[ "$*" == "flatpak remote-add --gpg-import=/tmp/flathub-test.gpg flathub https://dl.flathub.org/repo/" ]]; then
        remote_fixed=1
        return 0
      fi
      if [[ "$*" == "flatpak remote-delete --force flathub" ]]; then
        return 0
      fi
      return 1
    }
    TARGET_USER="test-user"
    DRY_RUN=0
    flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  } 2>&1)"

  grep -F "Flatpak remote add failed for 'flathub'; retrying." <<<"$output" >/dev/null
  grep -F "Verified Flathub remote setup failed; importing Flathub GPG key directly and retrying." <<<"$output" >/dev/null
  grep -F "curl:-fsSL https://flathub.org/repo/flathub.gpg -o /tmp/flathub-test.gpg" <<<"$output" >/dev/null
  grep -F "chmod:0644 /tmp/flathub-test.gpg" <<<"$output" >/dev/null
  grep -F "root:flatpak remote-delete --force flathub" <<<"$output" >/dev/null
  grep -F "root:flatpak remote-add --gpg-import=/tmp/flathub-test.gpg flathub https://dl.flathub.org/repo/" <<<"$output" >/dev/null
}

assert_flathub_setup_retries_direct_gpg_import_with_clean_root() {
  local output
  output="$({
    remote_fixed=0
    mktemp() {
      printf '/tmp/flathub-test.gpg\n'
    }
    curl() {
      printf 'curl:%s\n' "$*" >&2
      [[ "$*" == "-fsSL https://flathub.org/repo/flathub.gpg -o /tmp/flathub-test.gpg" ]]
    }
    chmod() {
      printf 'chmod:%s\n' "$*" >&2
    }
    have_cmd() {
      [[ "$1" == "flatpak" ]]
    }
    flatpak() {
      case "$1" in
        remotes)
          [[ "$remote_fixed" -eq 1 ]] && printf 'flathub\n'
          return 0
          ;;
        remote-ls)
          [[ "$remote_fixed" -eq 1 ]]
          ;;
        *)
          return 1
          ;;
      esac
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
      if [[ "$*" == "flatpak remote-delete --force flathub" ]]; then
        return 0
      fi
      return 1
    }
    run_cmd_as_clean_root() {
      printf 'clean-root:%s\n' "$*"
      if [[ "$*" == "flatpak remote-add --gpg-import=/tmp/flathub-test.gpg flathub https://dl.flathub.org/repo/" ]]; then
        remote_fixed=1
        return 0
      fi
      return 1
    }
    TARGET_USER="test-user"
    DRY_RUN=0
    flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  } 2>&1)"

  grep -F "Direct Flathub GPG import failed in the current environment; retrying with a clean root environment." <<<"$output" >/dev/null
  grep -F "clean-root:flatpak remote-add --gpg-import=/tmp/flathub-test.gpg flathub https://dl.flathub.org/repo/" <<<"$output" >/dev/null
}

assert_flatpak_install_aborts_when_remote_remains_unusable() {
  local output
  output="$({
    flatpak_remote_add_if_missing() {
      printf 'remote-bootstrap\n'
      return 1
    }
    flatpak_install_or_update() {
      printf 'install:%s\n' "$1"
    }
    distro_install_flatpaks com.discordapp.Discord org.onlyoffice.desktopeditors
  } 2>&1)" && return 1

  grep -F "remote-bootstrap" <<<"$output" >/dev/null
  ! grep -F "install:com.discordapp.Discord" <<<"$output" >/dev/null
  ! grep -F "install:org.onlyoffice.desktopeditors" <<<"$output" >/dev/null
}

assert_flatpak_install_uses_system_installation() {
  local output
  output="$({
    run_cmd_as_user() {
      printf 'user:%s:%s\n' "$1" "${*:2}"
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
    }
    TARGET_USER="test-user"
    flatpak_install_or_update com.spotify.Client flathub
  } 2>&1)"

  grep -F "root:flatpak install -y --or-update flathub com.spotify.Client" <<<"$output" >/dev/null
  ! grep -F "user:test-user:flatpak --user install" <<<"$output" >/dev/null
}

assert_flatpak_install_retries_flathub_after_gpg_import() {
  local output
  output="$({
    install_attempts=0
    mktemp() {
      printf '/tmp/flathub-test.gpg\n'
    }
    curl() {
      printf 'curl:%s\n' "$*" >&2
      [[ "$*" == "-fsSL https://flathub.org/repo/flathub.gpg -o /tmp/flathub-test.gpg" ]]
    }
    chmod() {
      printf 'chmod:%s\n' "$*" >&2
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
      if [[ "$*" == "flatpak remote-add --no-gpg-verify flathub https://dl.flathub.org/repo/" ]]; then
        remote_fixed=1
        return 0
      fi
      case "$*" in
        "flatpak install -y --or-update flathub com.spotify.Client")
          install_attempts="$((install_attempts + 1))"
          if [[ "$install_attempts" -eq 1 ]]; then
            printf 'GPG: Unable to complete signature verification: GnuPG: General error\n'
            return 1
          fi
          return 0
          ;;
        "flatpak remote-modify --gpg-verify --gpg-import=/tmp/flathub-test.gpg flathub")
          return 0
          ;;
      esac
      return 1
    }
    DRY_RUN=0
    LOG_DIR="$TEST_ROOT/flatpak-retry-logs"
    mkdir -p "$LOG_DIR"
    flatpak_install_or_update com.spotify.Client flathub
  } 2>&1)"

  grep -F "Flatpak install from 'flathub' failed GPG verification; importing Flathub GPG key directly and retrying." <<<"$output" >/dev/null
  grep -F "curl:-fsSL https://flathub.org/repo/flathub.gpg -o /tmp/flathub-test.gpg" <<<"$output" >/dev/null
  grep -F "chmod:0644 /tmp/flathub-test.gpg" <<<"$output" >/dev/null
  grep -F "root:flatpak remote-modify --gpg-verify --gpg-import=/tmp/flathub-test.gpg flathub" <<<"$output" >/dev/null
  grep -F "Flatpak install details for com.spotify.Client:" <<<"$output" >/dev/null
}

assert_flatpak_install_readds_flathub_when_gpg_reimport_fails() {
  local output
  output="$({
    install_attempts=0
    remote_fixed=0
    mktemp() {
      printf '/tmp/flathub-test.gpg\n'
    }
    curl() {
      printf 'curl:%s\n' "$*" >&2
      [[ "$*" == "-fsSL https://flathub.org/repo/flathub.gpg -o /tmp/flathub-test.gpg" ]]
    }
    chmod() {
      printf 'chmod:%s\n' "$*" >&2
    }
    have_cmd() {
      [[ "$1" == "flatpak" ]]
    }
    flatpak() {
      case "$1" in
        remotes)
          [[ "$remote_fixed" -eq 1 ]] && printf 'flathub\n'
          return 0
          ;;
        remote-ls)
          [[ "$remote_fixed" -eq 1 ]]
          ;;
        *)
          return 1
          ;;
      esac
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
      case "$*" in
        "flatpak install -y --or-update flathub com.spotify.Client")
          install_attempts="$((install_attempts + 1))"
          if [[ "$install_attempts" -eq 1 ]]; then
            printf 'GPG: Unable to complete signature verification: GnuPG: General error\n'
            return 1
          fi
          [[ "$remote_fixed" -eq 1 ]] && return 0
          return 1
          ;;
        "flatpak remote-modify --gpg-verify --gpg-import=/tmp/flathub-test.gpg flathub")
          return 1
          ;;
        "flatpak remote-delete --force flathub")
          return 0
          ;;
        "flatpak remote-add --gpg-import=/tmp/flathub-test.gpg flathub https://dl.flathub.org/repo/")
          remote_fixed=1
          return 0
          ;;
        "flatpak remote-add --no-gpg-verify flathub https://dl.flathub.org/repo/")
          remote_fixed=1
          return 0
          ;;
      esac
      return 1
    }
    run_cmd_as_clean_root() {
      printf 'clean-root:%s\n' "$*"
      return 1
    }
    DRY_RUN=0
    LOG_DIR="$TEST_ROOT/flatpak-readd-logs"
    mkdir -p "$LOG_DIR"
    flatpak_install_or_update com.spotify.Client flathub
  } 2>&1)"

  grep -F "Flathub GPG key reimport failed; re-adding the remote with the Flathub GPG key." <<<"$output" >/dev/null
  grep -F "root:flatpak remote-delete --force flathub" <<<"$output" >/dev/null
  grep -F "root:flatpak remote-add --gpg-import=/tmp/flathub-test.gpg flathub https://dl.flathub.org/repo/" <<<"$output" >/dev/null
  grep -F "Flatpak install details for com.spotify.Client:" <<<"$output" >/dev/null
}

assert_dotnet_sdk_fails_when_no_channels_found() {
  local output
  output="$({
    TARGET_HOME="$TEST_ROOT/no-dotnet-channels-home"
    CACHE_DIR="$TEST_ROOT/no-dotnet-channels-cache"
    mkdir -p "$TARGET_HOME" "$CACHE_DIR"
    DRY_RUN=0
    run_cmd() {
      case "$1" in
        curl)
          printf 'download:%s\n' "${*: -1}"
          printf '{}\n' >"${*: -1}"
          ;;
        chmod)
          printf 'chmod:%s\n' "$*"
          ;;
      esac
    }
    dotnet_channel_versions() {
      return 0
    }
    install_dotnet_sdks
  } 2>&1)" && return 1

  grep -F "No active .NET SDK channels were found" <<<"$output" >/dev/null
}

assert_dotnet_sdk_selects_second_lts_floor_and_newer_channels() {
  local output
  output="$({
    TARGET_HOME="$TEST_ROOT/dotnet-channel-floor-home"
    CACHE_DIR="$TEST_ROOT/dotnet-channel-floor-cache"
    mkdir -p "$TARGET_HOME" "$CACHE_DIR"
    DRY_RUN=0
    run_cmd() {
      case "$1" in
        curl)
          if [[ "$*" == *"releases-index.json"* ]]; then
            cat >"${*: -1}" <<'EOF'
{
  "releases-index": [
    { "channel-version": "10.0", "release-type": "lts", "support-phase": "active" },
    { "channel-version": "9.0", "release-type": "sts", "support-phase": "active" },
    { "channel-version": "8.0", "release-type": "lts", "support-phase": "active" }
  ]
}
EOF
          else
            printf '#!/usr/bin/env bash\nexit 0\n' >"${*: -1}"
          fi
          ;;
        chmod)
          chmod 0755 "${@: -1}"
          ;;
      esac
    }
    run_cmd_as_user() {
      local user="$1"
      shift
      printf 'user-cmd:%s\n' "$*"
      mkdir -p "$TARGET_HOME/.dotnet"
      printf '#!/usr/bin/env bash\nexit 0\n' >"$TARGET_HOME/.dotnet/dotnet"
      chmod +x "$TARGET_HOME/.dotnet/dotnet"
    }
    install_dotnet_sdks
  } 2>&1)"

  grep -F "Installing .NET SDK channels: 10.0, 9.0, 8.0" <<<"$output" >/dev/null
  grep -F "user-cmd:bash" <<<"$output" >/dev/null
  grep -F -- "--channel 10.0" <<<"$output" >/dev/null
  grep -F -- "--channel 9.0" <<<"$output" >/dev/null
  grep -F -- "--channel 8.0" <<<"$output" >/dev/null
}

assert_fedora_ms_fonts_installs_refresh_helpers() {
  local output
  output="$({
    rpm() {
      [[ "$1" == "-q" ]] && return 1
      return 0
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
    }
    DISTRO=fedora
    DRY_RUN=0
    install_fedora_ms_fonts
  } 2>&1)"

  grep -F "root:dnf install -y curl cabextract fontconfig mkfontscale xorg-x11-font-utils xset" <<<"$output" >/dev/null
  grep -F "root:env PATH=$CACHE_DIR/ms-fonts-xset." <<<"$output" >/dev/null
  grep -F ":$PATH rpm -i --nodigest --nosignature https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm" <<<"$output" >/dev/null
}

assert_google_chrome_source_imports_key_before_repo_install() {
  local output
  output="$({
    distro_repo_enabled() {
      return 1
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
    }
    DISTRO=fedora
    DRY_RUN=0
    distro_enable_sources vendor:google-chrome
  } 2>&1)"

  grep -F "root:bash -c rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null" <<<"$output" >/dev/null
  grep -F "root:install -Dm0644" <<<"$output" >/dev/null
  grep -F "/etc/default/google-chrome" <<<"$output" >/dev/null
  grep -F "root:install -Dm0644" <<<"$output" >/dev/null
}

assert_terra_source_bootstraps_release_packages_before_importing_key() {
  local output
  output="$({
    distro_repo_enabled() {
      return 1
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
    }
    rpm() {
      [[ "$*" == "-E %fedora" ]] && printf '44\n'
    }
    DISTRO=fedora
    DRY_RUN=0
    distro_enable_sources terra
  } 2>&1)"

  grep -F "root:dnf install -y --nogpgcheck --repofrompath terra-bootstrap,https://repos.fyralabs.com/terra\$releasever --setopt=terra-bootstrap.gpgcheck=0 --setopt=terra-bootstrap.repo_gpgcheck=0 terra-gpg-keys terra-release" <<<"$output" >/dev/null
  grep -F "root:rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-terra44" <<<"$output" >/dev/null
  grep -F "root:dnf config-manager setopt terra.repo_gpgcheck=0" <<<"$output" >/dev/null
}

assert_rpmfusion_source_installs_appstream_metadata() {
  local output
  output="$({
    distro_repo_enabled() {
      return 1
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
    }
    rpm() {
      [[ "$*" == "-E %fedora" ]] && printf '44\n'
    }
    DISTRO=fedora
    DRY_RUN=0
    distro_enable_sources rpmfusion-free
    distro_enable_sources rpmfusion-nonfree
  } 2>&1)"

  grep -F "root:rpm --import https://download1.rpmfusion.org/free/fedora/RPM-GPG-KEY-rpmfusion-free-fedora-2020" <<<"$output" >/dev/null
  grep -F "root:dnf install -y --setopt=localpkg_gpgcheck=1 https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm" <<<"$output" >/dev/null
  grep -F "root:dnf install -y rpmfusion-free-appstream-data" <<<"$output" >/dev/null
  grep -F "root:rpm --import https://download1.rpmfusion.org/nonfree/fedora/RPM-GPG-KEY-rpmfusion-nonfree-fedora-2020" <<<"$output" >/dev/null
  grep -F "root:dnf install -y --setopt=localpkg_gpgcheck=1 https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-44.noarch.rpm" <<<"$output" >/dev/null
  grep -F "root:dnf install -y rpmfusion-nonfree-appstream-data" <<<"$output" >/dev/null
}

assert_rpmfusion_source_refreshes_appstream_when_repo_already_enabled() {
  local output
  output="$({
    distro_repo_enabled() {
      return 0
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
    }
    rpm() {
      [[ "$*" == "-E %fedora" ]] && printf '44\n'
    }
    DISTRO=fedora
    DRY_RUN=0
    distro_enable_sources rpmfusion-free
    distro_enable_sources rpmfusion-nonfree
  } 2>&1)"

  ! grep -F "root:rpm --import https://download1.rpmfusion.org/free/fedora/RPM-GPG-KEY-rpmfusion-free-fedora-2020" <<<"$output" >/dev/null
  ! grep -F "root:rpm --import https://download1.rpmfusion.org/nonfree/fedora/RPM-GPG-KEY-rpmfusion-nonfree-fedora-2020" <<<"$output" >/dev/null
  grep -F "root:dnf install -y rpmfusion-free-appstream-data" <<<"$output" >/dev/null
  grep -F "root:dnf install -y rpmfusion-nonfree-appstream-data" <<<"$output" >/dev/null
}

assert_claude_desktop_source_imports_key_before_repo_install() {
  local output
  output="$({
    distro_repo_enabled() {
      return 1
    }
    run_cmd_as_root() {
      printf 'root:%s\n' "$*"
    }
    DISTRO=fedora
    DRY_RUN=0
    distro_enable_sources vendor:claude-desktop
  } 2>&1)"

  grep -F "root:rpm --import https://pkg.claude-desktop-debian.dev/KEY.gpg" <<<"$output" >/dev/null
  grep -F "root:install -Dm0644" <<<"$output" >/dev/null
  grep -F "/etc/yum.repos.d/claude-desktop.repo" <<<"$output" >/dev/null
}

assert_default_browser_uses_mime_fallback_when_xdg_settings_fails() {
  local output
  output="$({
    run_cmd_as_user() {
      local user="$1"
      shift
      printf 'user:%s:%s\n' "$user" "$*"
      [[ "$1" == "xdg-settings" ]] && return 1
      return 0
    }
    TARGET_USER=test-user
    set_default_browser firefox.desktop
  } 2>&1)"

  grep -F "user:test-user:xdg-mime default firefox.desktop text/html" <<<"$output" >/dev/null
  grep -F "user:test-user:xdg-mime default firefox.desktop x-scheme-handler/http" <<<"$output" >/dev/null
  grep -F "user:test-user:xdg-mime default firefox.desktop x-scheme-handler/https" <<<"$output" >/dev/null
  ! grep -F "Could not set default browser" <<<"$output" >/dev/null
}

assert_homebrew_refreshes_ca_certificates_after_install() {
  local output
  output="$({
    install_homebrew_if_needed() {
      return 0
    }
    run_user_login_shell() {
      printf 'shell:%s\n' "$1"
    }
    DRY_RUN=0
    install_brew_package codex
  } 2>&1)"

  grep -F "shell:brew list 'codex' >/dev/null 2>&1 || brew install 'codex'" <<<"$output" >/dev/null
  grep -F "brew postinstall ca-certificates" <<<"$output" >/dev/null
}

assert_bootstrap_tool_failure_aborts_later_prereqs() {
  local old_plan_dir="$PLAN_DIR"
  PLAN_DIR="$TEST_ROOT/bootstrap-plan"
  mkdir -p "$PLAN_DIR/prereqs"
  printf 'flatpak\nstow\n' >"$PLAN_DIR/prereqs/dnf.pkgs"
  printf 'org.example.App\n' >"$PLAN_DIR/prereqs/flatpak.flatpaks"

  local output
  output="$(
    package_install_idempotent() {
      local backend="$1"
      shift
      printf 'install:%s:%s\n' "$backend" "$*"
      [[ "$backend" != "dnf" ]]
    }
    module_05_bootstrap_tools
  )" && {
    PLAN_DIR="$old_plan_dir"
    return 1
  }

  PLAN_DIR="$old_plan_dir"
  grep -F 'install:dnf:flatpak stow' <<<"$output" >/dev/null
  ! grep -F 'install:flatpak:org.example.App' <<<"$output" >/dev/null
}

assert_required_install_verification_reports_missing_native_package() {
  local old_verify="$VERIFY_INSTALLS"
  local old_dry_run="$DRY_RUN"
  local plan_file="$TEST_ROOT/verify-native.pkgs"
  printf 'missing-native-package\n' >"$plan_file"
  VERIFY_INSTALLS=1
  DRY_RUN=0

  local output
  output="$({
    distro_package_installed() {
      return 1
    }
    verify_required_plan_entries dnf "$plan_file" "base packages"
  } 2>&1)" && {
    VERIFY_INSTALLS="$old_verify"
    DRY_RUN="$old_dry_run"
    return 1
  }

  VERIFY_INSTALLS="$old_verify"
  DRY_RUN="$old_dry_run"
  grep -F 'Required base packages missing after install: missing-native-package' <<<"$output" >/dev/null
}

assert_required_base_action_verification_reports_missing_font() {
  local old_home="$TARGET_HOME"
  local old_dry_run="$DRY_RUN"
  TARGET_HOME="$TEST_ROOT/missing-font-home"
  DRY_RUN=0
  mkdir -p "$TARGET_HOME"

  if verify_custom_action jetbrains-mono-nerd-font-fedora; then
    TARGET_HOME="$old_home"
    DRY_RUN="$old_dry_run"
    return 1
  fi

  mkdir -p "$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerdFont"
  printf 'font\n' >"$TARGET_HOME/.local/share/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf"
  verify_custom_action jetbrains-mono-nerd-font-fedora
  TARGET_HOME="$old_home"
  DRY_RUN="$old_dry_run"
}

assert_first_run_creates_marker_and_removes_hook() {
  DISTRO="fedora"
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/first-run-home"
  DRY_RUN=0
  mkdir -p "$TARGET_HOME/.config/noctalia"
  printf '{}\n' >"$TARGET_HOME/.config/noctalia/settings.json"
  reset_test_selections
  build_plan_from_selections

  run_cmd_as_user() {
    local user="$1"
    shift
    printf 'user:%s:%s\n' "$user" "$*" >>"$TEST_ROOT/first-run-commands.log"
    case "$1" in
      mkdir|rm|sh)
        "$@"
        ;;
      *)
        return 0
        ;;
    esac
  }

  register_first_run_hook
  [[ -f "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]
  grep -F 'Exec='"$TARGET_HOME"'/.local/bin/zz first-run' "$TARGET_HOME/.config/autostart/zz-first-run.desktop" >/dev/null

  module_80_first_run
  [[ -f "$(first_run_marker)" ]]
  [[ ! -e "$TARGET_HOME/.config/autostart/zz-first-run.desktop" ]]
  grep -F 'systemctl --user daemon-reload' "$TEST_ROOT/first-run-commands.log" >/dev/null

  : >"$TEST_ROOT/first-run-commands.log"
  module_80_first_run
  [[ ! -s "$TEST_ROOT/first-run-commands.log" ]]

  DRY_RUN=1
  TARGET_USER="${USER}"
  TARGET_HOME="${HOME}"
}

assert_post_actions_seed_noctalia_settings_before_first_run() {
  DISTRO="fedora"
  TARGET_USER="test-user"
  TARGET_HOME="$TEST_ROOT/post-actions-home"
  DRY_RUN=0
  mkdir -p "$TARGET_HOME"
  reset_test_selections
  add_category_selection "browser" "zen-copr"
  add_category_selection "dev" "vscode,neovim"
  build_plan_from_selections

  install_zz_launcher() { :; }
  configure_default_applications() { :; }
  patch_noctalia_starship_template_apply_if_needed() { :; }
  install_noctalia_wallpaper_state() { :; }
  install_starship_config() { :; }
  install_niri_noctalia_seed_if_missing() { :; }
  install_qt_theme_config() { :; }
  install_pywalfox_native_host() { :; }
  install_vscode_noctalia_extension() { :; }
  register_first_run_hook() { :; }
  write_managed_files_report() { :; }
  run_cmd_as_user() {
    local user="$1"
    shift
    HOME="$TARGET_HOME" USER="$user" LOGNAME="$user" "$@"
  }

  module_80_post_actions
  [[ -f "$TARGET_HOME/.config/noctalia/settings.json" ]]
  grep -F '"terminalCommand": "ghostty -e"' "$TARGET_HOME/.config/noctalia/settings.json" >/dev/null
  grep -F '"directory": "'"$TARGET_HOME"'/Wallpapers"' "$TARGET_HOME/.config/noctalia/settings.json" >/dev/null
  grep -F '"id": "zenBrowser"' "$TARGET_HOME/.config/noctalia/settings.json" >/dev/null
  grep -F '"enableUserTheming": true' "$TARGET_HOME/.config/noctalia/settings.json" >/dev/null

  DRY_RUN=1
  TARGET_USER="${USER}"
  TARGET_HOME="${HOME}"
}

assert_base_plan_for_distro fedora "$PLAN_DIR/packages/dnf.pkgs"
assert_required_services_are_base_packages fedora "$PLAN_DIR/packages/dnf.pkgs"
assert_package_module_installs_base_before_optional fedora dnf code niri noctalia-shell sddm zsh starship zoxide fastfetch gh btop fd-find fzf bat yazi
assert_required_base_package_failure_aborts_base_setup
assert_niri_readiness_failure_aborts_base_setup
assert_login_manager_failure_aborts_base_setup
assert_missing_required_service_retries_package
assert_doctor_fails_when_planned_niri_is_not_ready
assert_dotnet_tools_fail_without_sdk
assert_flatpak_remote_repaired_when_present_but_unusable
assert_flathub_repo_enabled_requires_usable_remote
assert_flathub_setup_uses_official_system_remote
assert_flathub_setup_falls_back_to_direct_gpg_import
assert_flathub_setup_retries_direct_gpg_import_with_clean_root
assert_flatpak_install_aborts_when_remote_remains_unusable
assert_flatpak_install_uses_system_installation
assert_flatpak_install_retries_flathub_after_gpg_import
assert_flatpak_install_readds_flathub_when_gpg_reimport_fails
assert_dotnet_sdk_fails_when_no_channels_found
assert_dotnet_sdk_selects_second_lts_floor_and_newer_channels
assert_fedora_ms_fonts_installs_refresh_helpers
assert_google_chrome_source_imports_key_before_repo_install
assert_terra_source_bootstraps_release_packages_before_importing_key
assert_rpmfusion_source_installs_appstream_metadata
assert_rpmfusion_source_refreshes_appstream_when_repo_already_enabled
assert_claude_desktop_source_imports_key_before_repo_install
assert_default_browser_uses_mime_fallback_when_xdg_settings_fails
assert_homebrew_refreshes_ca_certificates_after_install
assert_bootstrap_tool_failure_aborts_later_prereqs
assert_required_install_verification_reports_missing_native_package
assert_required_base_action_verification_reports_missing_font
assert_first_run_creates_marker_and_removes_hook
assert_post_actions_seed_noctalia_settings_before_first_run

printf 'idempotency ok\n'
