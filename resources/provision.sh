#!/bin/sh

set -exu

setup_path() {
  PATH="/sbin:/usr/sbin:$PATH"
  export PATH
}

# The repository the installer configures is the one for the release, which
# tracks whatever pkgsrc branch is current. When a bulk build for that branch
# is only partly finished, the published package index is missing packages that
# are needed here, and pkgin reports them as unavailable even though the files
# are present. Pointing at a finished branch avoids depending on the state of
# an in-progress build.
# See https://github.com/cross-platform-actions/action/issues/158.
configure_package_repository() {
  [ -n "$PACKAGE_REPOSITORY" ] || return 0

  mkdir -p /usr/pkg/etc/pkgin
  echo "$PACKAGE_REPOSITORY" > /usr/pkg/etc/pkgin/repositories.conf
  pkgin -y update
}

install_extra_packages() {
  # On a port whose official mirrors carry no prebuilt pkgsrc binaries, the
  # sysinst-time "Enable installation of binary packages" step is skipped, so
  # pkgin never gets installed. Skip the package install cleanly in that case.
  if ! command -v pkgin >/dev/null 2>&1; then
    echo "pkgin not available on this port; skipping extra package install"
    return 0
  fi

  pkgin -y install bash curl rsync sudo
}

setup_sudo() {
  # sudo comes from pkgsrc; if pkgin wasn't usable above, sudo isn't on
  # this image and there's no sudoers.d to write into. Skip cleanly so the
  # provisioner still finishes.
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo not installed on this port; skipping sudoers setup"
    return 0
  fi

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

# The action runs QEMU with `-display none -serial file:<log>` and prints that
# log when a job fails. On the platforms where the boot loader and the kernel
# write to the VGA framebuffer instead of the serial port, the log stays empty
# and there's no way to tell why a VM failed to boot. Point the console at the
# serial port so the boot output ends up in the log.
# See https://github.com/cross-platform-actions/action/issues/158.
configure_boot_console() {
  [ -n "$BOOT_CONSOLE" ] || return 0

  if grep -q '^consdev=' /boot.cfg; then
    sed -i -E "s/^consdev=.+/consdev=$BOOT_CONSOLE/" /boot.cfg
  else
    echo "consdev=$BOOT_CONSOLE" >> /boot.cfg
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

setup_path

# Configuration that only touches the file system, before anything that needs
# the network. Nothing here depends on the packages, so it shouldn't be gated
# behind a step that can fail because of a mirror.
configure_boot_flags
configure_boot_console
configure_boot_scripts
set_hostname

configure_package_repository
install_extra_packages
setup_sudo
