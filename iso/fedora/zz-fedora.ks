# Online Fedora installer profile for zz-linux-setup.
#
# Build with scripts/build-fedora-installer-iso.sh so this checkout and the
# Anaconda add-on product image are available during installation. Storage,
# locale, keyboard layout, timezone, hostname, root password, user creation,
# and optional ZZ Linux Setup choices remain in the Anaconda UI.

network --bootproto=dhcp --activate

firstboot --disable
selinux --enforcing

url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-@FEDORA_RELEASE@&arch=@FEDORA_ARCH@"
repo --name="updates" --metalink="https://mirrors.fedoraproject.org/metalink?repo=updates-released-f@FEDORA_RELEASE@&arch=@FEDORA_ARCH@" --install

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
