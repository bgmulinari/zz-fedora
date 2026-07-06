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

install -d -o "$target_user" -g "$target_group" -m 0755 \
  "$target_home/.local/state" \
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

cd "$target_repo_dir"
./install.sh install --yes --distro fedora --desktop-app-profile full --no-tui --target-user "$target_user"

rm -rf "$repo_dir"
%end
