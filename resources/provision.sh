#!/bin/sh

set -exu

setup_path() {
  PATH="/sbin:/usr/sbin:$PATH"
  export PATH
}

setup_binary_packages() {
  arch="$(uname -m)"
  version="$(uname -r)"
  PKG_PATH="https://cdn.NetBSD.org/pub/pkgsrc/packages/NetBSD/$arch/$version/All"
  export PKG_PATH
  echo "PKG_PATH='$PKG_PATH'" >> /etc/profile
  echo "export PKG_PATH" >> /etc/profile
}

install_extra_packages() {
  pkg_add -v bash curl pkgin rsync sudo
}

setup_sudo() {
  mkdir -p /usr/pkg/etc/sudoers.d
  cat <<EOF > "/usr/pkg/etc/sudoers.d/$SECONDARY_USER"
Defaults:$SECONDARY_USER !requiretty
$SECONDARY_USER ALL=(ALL) NOPASSWD: ALL
EOF

  chmod 440 "/usr/pkg/etc/sudoers.d/$SECONDARY_USER"
}

configure_boot_flags() {
  sed -i -E 's/timeout=.+/timeout=0/' /boot.cfg
}

configure_boot_scripts() {
  cat <<EOF >> /etc/rc.local
RESOURCES_MOUNT_PATH='/mnt/resources'

mount_resources_disk() {
  # get the last disk
  disk="/dev/\$(sysctl -n hw.disknames | grep -o '[^ ]*$')"

  if [ -n "\$disk" ]; then
    mkdir -p "\$RESOURCES_MOUNT_PATH"
    mount_msdos "\$disk" "\$RESOURCES_MOUNT_PATH"
  fi
}

install_authorized_keys() {
  if [ -s "\$RESOURCES_MOUNT_PATH/KEYS" ]; then
    mkdir -p "/home/$SECONDARY_USER/.ssh"
    cp "\$RESOURCES_MOUNT_PATH/KEYS" "/home/$SECONDARY_USER/.ssh/authorized_keys"
    chown "$SECONDARY_USER" "/home/$SECONDARY_USER/.ssh/authorized_keys"
    chmod 600 "/home/$SECONDARY_USER/.ssh/authorized_keys"
  fi
}

mount_resources_disk
install_authorized_keys
EOF
}

minimize_disk() {
  for dir in $(mount | awk '{ print $3 }'); do
    dd if=/dev/zero of="$dir/EMPTY" bs=1048576 || :
    rm -f "$dir/EMPTY"
  done
}

minimize_swap() {
  swap_device=$(swapctl -l | awk '!/^Device/ { print $1 }')
  swapctl -d "$swap_device"
  dd if=/dev/zero of="$swap_device" bs=1048576 || :
}

setup_path
setup_binary_packages
install_extra_packages
setup_sudo
configure_boot_flags
configure_boot_scripts

minimize_disk
minimize_swap
