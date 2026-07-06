# Online Fedora installer profile for zz-linux-setup.
#
# Build with scripts/build-fedora-installer-iso.sh so this checkout is
# available at /run/install/repo/zz-linux-setup during installation. Storage,
# locale, keyboard layout, timezone, hostname, root password, and user creation
# are intentionally left to the Anaconda UI.

network --bootproto=dhcp --activate

firstboot --disable
selinux --enforcing

url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch"
repo --name="updates" --metalink="https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch" --install

bootloader --location=mbr
services --enabled=NetworkManager

%packages
@core
sudo
ca-certificates
curl
git
gum
bats
dnf-plugins-core
dnf5-plugins
rsync
%end

%post --nochroot --interpreter=/usr/bin/bash --erroronfail --log=/mnt/sysimage/root/zz-linux-setup-copy.log
set -Eeuo pipefail

install -d -m 0755 /mnt/sysimage/opt
rm -rf /mnt/sysimage/opt/zz-linux-setup
cp -a /run/install/repo/zz-linux-setup /mnt/sysimage/opt/zz-linux-setup
%end

%post --interpreter=/usr/bin/bash --erroronfail --log=/root/zz-linux-setup-kickstart.log
set -Eeuo pipefail

repo_dir=/opt/zz-linux-setup
target_user=$(
  awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ "^/home/" && $7 !~ /(nologin|false)$/ { print $1; exit }' /etc/passwd
)

if [[ -z "$target_user" ]]; then
  echo "No installer-created regular user was found. Create a regular user in Anaconda before starting installation." >&2
  exit 1
fi

target_home=$(getent passwd "$target_user" | cut -d: -f6)
target_group=$(id -gn "$target_user")
target_repo_dir="$target_home/zz-linux-setup"

install -d -m 0755 "$target_home"
rm -rf "$target_repo_dir"
cp -a "$repo_dir" "$target_repo_dir"
chown -R "$target_user:$target_group" "$target_repo_dir"

install -d -m 0755 \
  "$target_home/.local" \
  "$target_home/.local/state" \
  "$target_home/.local/share" \
  "$target_home/.cache" \
  "$target_home/.config"
chown -R "$target_user:$target_group" \
  "$target_home/.local" \
  "$target_home/.cache" \
  "$target_home/.config"

export STATE_DIR="$target_home/.local/state/zz-linux-setup"
export CACHE_DIR="$target_home/.cache/zz-linux-setup"
export CONFIG_DIR="$target_home/.config/zz-linux-setup"
export LOG_DIR="$STATE_DIR/logs"
export STATE_OWNER_USER="$target_user"
export TARGET_USER="$target_user"
export DESKTOP_APP_PROFILE=full
export ZZ_INSTALLER_DEFER_START_SERVICES=1
export ZZ_INSTALLER_POST_TIMEOUT_SECONDS="${ZZ_INSTALLER_POST_TIMEOUT_SECONDS:-14400}"
export ZZ_COMMAND_TIMEOUT_SECONDS="${ZZ_COMMAND_TIMEOUT_SECONDS:-3600}"
export ZZ_COMMAND_TIMEOUT_KILL_AFTER="${ZZ_COMMAND_TIMEOUT_KILL_AFTER:-60s}"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP DESKTOP_SESSION
if [[ -r /etc/locale.conf ]]; then
  source /etc/locale.conf
fi
case "${LANG:-}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
  *) LANG=C.UTF-8 ;;
esac
case "${LC_ALL:-}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
  *) LC_ALL="$LANG" ;;
esac
export LANG LC_ALL

cd "$target_repo_dir"
printf '[zz-linux-setup] Starting bootstrap for %s. Detailed log: %s\n' "$target_user" "$LOG_DIR/latest.log" | tee /dev/console || true
set +e
timeout --foreground --kill-after=60s "$ZZ_INSTALLER_POST_TIMEOUT_SECONDS" \
  ./install.sh install --yes --distro fedora --desktop-app-profile full --no-tui --target-user "$target_user"
install_status=$?
set -e
if [[ "$install_status" -ne 0 ]]; then
  printf '[zz-linux-setup] Bootstrap failed with exit code %s. Check /root/zz-linux-setup-kickstart.log and %s.\n' "$install_status" "$LOG_DIR/latest.log" | tee /dev/console || true
  exit "$install_status"
fi
printf '[zz-linux-setup] Bootstrap completed for %s.\n' "$target_user" | tee /dev/console || true

rm -rf "$repo_dir"
%end
