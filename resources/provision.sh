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

# Let the secondary user log in over SSH with no credential at all. Three things
# have to line up, and the login fails if any one of them is missing:
#
#   1. sshd passes PAM_DISALLOW_NULL_AUTHTOK to pam_authenticate() unless
#      PermitEmptyPasswords is set.
#   2. pam_unix accepts an empty hash only when that flag is clear *and*
#      `nullok` is set on its auth line, otherwise it substitutes "*" and the
#      login can never succeed. NetBSD's own /etc/pam.d/su already relies on the
#      same option.
#   3. The password field has to actually be empty. creds_msdos(8) set one when
#      it created the user, so clear it and rebuild the password databases.
#
# The result is prompt-free rather than merely password-free: pam_unix returns
# success without ever calling the conversation function, so sshd's
# keyboard-interactive method sends zero prompts and the client authenticates
# without supplying any input. That also means the SSH session this runs in, and
# any reconnect packer makes with the password it was given, keep working.
#
# Only the secondary user is passwordless; root keeps its password, which is what
# the provisioners escalate with. The image is a throwaway CI guest reachable
# only through the consumer's own local port forward.
setup_passwordless_login() {
  [ "${PASSWORDLESS_LOGIN:-false}" = 'true' ] || return 0

  echo 'PermitEmptyPasswords yes' >> /etc/ssh/sshd_config

  sed -i -E '/^auth[[:space:]]+required[[:space:]]+pam_unix\.so/ s/$/ nullok/' \
    /etc/pam.d/sshd

  sed -i -E "s/^(${SECONDARY_USER}):[^:]*:/\1::/" /etc/master.passwd
  pwd_mkdb -p /etc/master.passwd

  # A substitution that matches nothing leaves sed successful, and the only
  # other symptom is SSH timing out against a finished image an hour later.
  # Fail the build here instead, where the reason is still on screen.
  grep -q '^PermitEmptyPasswords yes' /etc/ssh/sshd_config
  grep -q '^auth.*pam_unix\.so.*nullok' /etc/pam.d/sshd
  grep -q "^${SECONDARY_USER}::" /etc/master.passwd

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
setup_passwordless_login

# Configuration that only touches the file system, before anything that needs
# the network. Nothing here depends on the packages, so it shouldn't be gated
# behind a step that can fail because of a mirror.
configure_boot_flags
configure_boot_console
configure_boot_scripts
set_hostname

install_extra_packages
setup_sudo
