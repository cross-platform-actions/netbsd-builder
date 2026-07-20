#!/bin/sh

set -exu

setup_path() {
  # /usr/pkg/bin and /usr/pkg/sbin are needed for pkgin/pkg_add. When this
  # script runs inside the sysinst chroot (sparc64), the inherited PATH does
  # not include them, so `pkgin` would not be found and, under `set -e`, the
  # whole script would abort before configuring rc.local, sudo, etc.
  PATH="/sbin:/usr/sbin:/usr/pkg/bin:/usr/pkg/sbin:$PATH"
  export PATH
}

install_extra_packages() {
  pkgin -y install bash curl rsync sudo
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
  if [ -f /boot.cfg ]; then
    sed -i -E 's/timeout=.+/timeout=0/' /boot.cfg
  else
    echo 'timeout=0' > /boot.cfg
  fi
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

set_hostname() {
  echo 'hostname=runnervmg1sw1.local' >> /etc/rc.conf
}

# Bring up networking on boot. sysinst's network autoconfiguration does not
# persist a DHCP config to the installed rc.conf on every install path
# (notably sparc64), which leaves the VM with no address and sshd
# unreachable. Only add one when no network config exists, so images that
# are already configured are left untouched.
configure_network() {
  if ! grep -qE '^(dhcpcd=|ip4mode=|ifconfig_)' /etc/rc.conf; then
    echo 'dhcpcd=YES' >> /etc/rc.conf
  fi
}

setup_path
install_extra_packages
setup_sudo
configure_boot_flags
configure_boot_scripts
set_hostname
configure_network
