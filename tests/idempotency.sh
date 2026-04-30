#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/zz-linux-setup-idempotency.XXXXXX)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export XDG_STATE_HOME="$TEST_ROOT/state"
export XDG_CACHE_HOME="$TEST_ROOT/cache"
export XDG_CONFIG_HOME="$TEST_ROOT/config"

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
add_category_selection "browser" "firefox,firefox,zen-copr"
add_category_selection "dev" "vscode,neovim"
add_category_selection "shell" "starship,starship,yazi"
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
[[ "$(sort -u "$PLAN_DIR/services/system-enable-now.list" | wc -l | tr -d ' ')" -eq "$(wc -l <"$PLAN_DIR/services/system-enable-now.list" | tr -d ' ')" ]]
[[ "$(sort -u "$PLAN_DIR/stow/packages.list" | wc -l | tr -d ' ')" -eq "$(wc -l <"$PLAN_DIR/stow/packages.list" | tr -d ' ')" ]]
[[ "$(grep -Fc 'brew:codex' "$PLAN_DIR/actions/actions.list")" -eq 1 ]]
[[ "$(grep -Fc 'dotnet-sdk' "$PLAN_DIR/actions/actions.list")" -eq 1 ]]
[[ "$(grep -Fc 'dotnet-tools' "$PLAN_DIR/actions/actions.list")" -eq 1 ]]
grep -Fx 'shell' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'nvim' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'noctalia' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'vscode' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'wallpapers' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'shell-starship' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'shell-yazi' "$PLAN_DIR/stow/packages.list" >/dev/null
grep -Fx 'nautilus' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'fontconfig' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
! grep -Fx 'gnome-themes-extra' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'google-noto-sans-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'google-noto-sans-cjk-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'google-noto-color-emoji-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'fontawesome-6-free-fonts' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'yaru-icon-theme' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx 'sddm' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null
grep -Fx '~/.config/niri/config.kdl' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/niri/noctalia.kdl' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/nvim/plugin/noctalia.lua' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/plugins.json' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/user-templates.toml' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/templates/icon-theme-accent' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/noctalia/templates/zsh-syntax-highlighting.zsh' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.config/Code/User/settings.json' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.local/bin/noctalia-sync-icon-theme' "$PLAN_DIR/files/managed-files.list" >/dev/null
grep -Fx '~/.local/share/wallpapers/SilentPeaks.jpg' "$PLAN_DIR/files/managed-files.list" >/dev/null

settings_home="$TEST_ROOT/settings-home"
mkdir -p "$settings_home/.config/noctalia"
TARGET_HOME="$settings_home"
DRY_RUN=0
update_noctalia_settings
grep -F '"terminalCommand": "ghostty -e"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "ghostty"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "pywalfox"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "starship"' "$settings_home/.config/noctalia/settings.json" >/dev/null
grep -F '"id": "yazi"' "$settings_home/.config/noctalia/settings.json" >/dev/null
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
printf '{}\n' >"$TARGET_HOME/.config/noctalia/settings.json"
printf 'templates\n' >"$TARGET_HOME/.config/noctalia/user-templates.toml"
printf 'starship\n' >"$TARGET_HOME/.config/starship.toml"
stow_prepare_known_conflicts niri noctalia
[[ ! -e "$TARGET_HOME/.config/niri" ]]
[[ -f "$TARGET_HOME/.config/noctalia/settings.json" ]]
[[ ! -e "$TARGET_HOME/.config/noctalia/user-templates.toml" ]]
find "$STATE_DIR/backups" -path '*/home/.config/niri/config.kdl' -type f -print -quit | grep -q .
find "$STATE_DIR/backups" -path '*/home/.config/noctalia/user-templates.toml' -type f -print -quit | grep -q .

mkdir -p "$TARGET_HOME/.local/share/wallpapers"
printf 'wallpaper\n' >"$TARGET_HOME/.local/share/wallpapers/SilentPeaks.jpg"
stow_prepare_package_conflicts wallpapers
[[ -d "$TARGET_HOME/.local" ]]
[[ -d "$TARGET_HOME/.local/share" ]]
[[ ! -e "$TARGET_HOME/.local/share/wallpapers/SilentPeaks.jpg" ]]
find "$STATE_DIR/backups" -path '*/home/.local/share/wallpapers/SilentPeaks.jpg' -type f -print -quit | grep -q .

install_starship_config
[[ -f "$TARGET_HOME/.config/starship.toml" ]]
grep -F 'palette = "noctalia"' "$TARGET_HOME/.config/starship.toml" >/dev/null
find "$STATE_DIR/backups" -path '*/home/.config/starship.toml' -type f -print -quit | grep -q .

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
  grep -Fx 'noctalia-shell' "$PLAN_DIR/packages/dnf.pkgs" >/dev/null 2>&1 || grep -Fx 'noctalia-shell' "$PLAN_DIR/packages/aur.pkgs" >/dev/null
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
  module_32_optional_packages

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

  grep -F 'install:dnf:niri' <<<"$output" >/dev/null
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
    remote_fixed=0
    flatpak() {
      case "$1" in
        remotes)
          printf 'flathub\n'
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
      printf 'cmd:%s\n' "$*"
      if [[ "$*" == "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" ]]; then
        remote_fixed=1
      fi
    }
    DRY_RUN=0
    flatpak_remote_add_if_missing flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  } 2>&1)"

  grep -F "Flatpak remote 'flathub' is present but unusable" <<<"$output" >/dev/null
  grep -F "cmd:flatpak remote-delete --force flathub" <<<"$output" >/dev/null
  grep -F "cmd:flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" <<<"$output" >/dev/null
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
assert_dotnet_sdk_fails_when_no_channels_found

assert_base_plan_for_distro arch "$PLAN_DIR/packages/pacman.pkgs"
assert_required_services_are_base_packages arch "$PLAN_DIR/packages/pacman.pkgs"
assert_package_module_installs_base_before_optional arch pacman visual-studio-code-bin niri noctalia-shell sddm zsh starship zoxide fastfetch github-cli btop fd fzf bat yazi

printf 'idempotency ok\n'
