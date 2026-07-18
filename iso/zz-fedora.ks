# Online Fedora installer profile for zz-fedora.
#
# Build with iso/scripts/build-fedora-installer-iso.sh so this checkout and the
# Anaconda add-on product image are available during installation. Storage,
# locale, keyboard layout, timezone, hostname, root password, user creation,
# and optional ZZ Fedora choices remain in the Anaconda UI.

network --bootproto=dhcp --activate

firstboot --disable
selinux --enforcing

url --metalink="https://mirrors.fedoraproject.org/metalink?repo=fedora-@FEDORA_RELEASE@&arch=@FEDORA_ARCH@"
# Re-enable Anaconda's built-in Fedora updates repository. Do not redefine it
# by URL: Anaconda disables system repositories while loading an explicit URL
# source, and reconfiguring the existing repo does not enable it again.
repo --name="updates"

bootloader --location=mbr
services --enabled=NetworkManager

%packages
@core
sudo
ca-certificates
curl
dnf5-plugins
%end
