#!/bin/sh

set -exu

setup_path() {
  PATH="/sbin:/usr/sbin:$PATH"
  export PATH
}

# NetBSD 11 panics when a CPU hasn't checked in with the heartbeat watchdog for
# a few seconds:
#
#     panic: cpu1[118 ioflush]: heart stopped beating
#
# An emulated CPU is regularly starved for that long, under heavy I/O or when
# the host is busy, and the watchdog has no way to tell that apart from a
# genuinely wedged CPU. The guests here are emulated throughout, so turn it
# off. The sysctl only exists from NetBSD 11 onwards.
disable_heartbeat() {
  sysctl -n kern.heartbeat.max_period > /dev/null 2>&1 || return 0

  sysctl -w kern.heartbeat.max_period=0
  echo 'kern.heartbeat.max_period=0' >> /etc/sysctl.conf
}

# For an installation performed by sysinst this is done by
# `resources/post_install.sh`, before the first boot. A pre-built image boots
# with the stock configuration, which lets nobody in over SSH.
configure_ssh() {
  grep -q '^PermitRootLogin yes' /etc/ssh/sshd_config && return 0

  cat <<EOF >> /etc/ssh/sshd_config
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UseDNS no
AcceptEnv *
EOF

  /etc/rc.d/sshd restart
}

# The secondary user is created by sysinst, or by creds_msdos(8) for a
# pre-built image, which doesn't create the home directory.
setup_secondary_user() {
  home="/home/$SECONDARY_USER"
  [ -d "$home" ] && return 0

  mkdir -p "$home"
  chown "$SECONDARY_USER" "$home"
}

# sysinst installs pkgin as part of the installation. A pre-built image, which
# is not installed through sysinst, needs it bootstrapped first. A port whose
# official mirrors carry no prebuilt pkgsrc binaries has nothing to bootstrap
# from, which install_extra_packages handles.
install_pkgin() {
  command -v pkgin > /dev/null 2>&1 && return 0

  # The repository of the port has to be known here: `pkg_add` has no
  # configuration to read it from yet, that's what configure_package_repository
  # sets up once pkgin exists.
  [ -n "$PACKAGE_REPOSITORY" ] || return 0

  PKG_PATH="$PACKAGE_REPOSITORY" pkg_add -U pkgin ||
    echo "failed to bootstrap pkgin from $PACKAGE_REPOSITORY"
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
  install_pkgin

  # On a port whose official mirrors carry no prebuilt pkgsrc binaries, the
  # sysinst-time "Enable installation of binary packages" step is skipped and
  # the bootstrap above has nothing to fetch, so pkgin never gets installed.
  # Skip the package install cleanly in that case.
  if ! command -v pkgin >/dev/null 2>&1; then
    echo "pkgin not available on this port; skipping extra package install"
    return 0
  fi

  configure_package_repository
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
disable_heartbeat
configure_ssh
setup_secondary_user

# Configuration that only touches the file system, before anything that needs
# the network. Nothing here depends on the packages, so it shouldn't be gated
# behind a step that can fail because of a mirror.
configure_boot_flags
configure_boot_console
configure_boot_scripts
set_hostname

install_extra_packages
setup_sudo
