#!/bin/sh

set -exu

# Where configure_network keeps a copy of the resolver configuration that
# dhcpcd doesn't know about, and configure_boot_scripts restores it from.
RESOLV_BACKUP='/etc/resolv.conf.cpa'

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

# User mode networking hands out the same lease every boot, and rcorder puts
# dhcpcd in front of sshd. Freeze the lease this build was given, read from the
# running system so the image keeps whatever the hypervisor hands out.
configure_network() {
  interface=$(route -n get default | awk '$1 == "interface:" { print $2; exit }')
  gateway=$(route -n get default | awk '$1 == "gateway:" { print $2; exit }')

  # NetBSD's ifconfig prints either "inet 10.0.2.15/24 ..." or, on the older
  # releases, "inet 10.0.2.15 netmask 0xffffff00 ...". Both spellings are valid
  # as ifconfig arguments, so keep whichever this release produced.
  address=$(ifconfig "$interface" inet | awk '$1 == "inet" {
    if ($2 ~ /\//) { print $2; exit }
    for (i = 3; i < NF; i++)
      if ($i == "netmask") { print $2 " netmask " $(i + 1); exit }
    print $2
    exit
  }')

  nameservers=$(awk '$1 == "nameserver" { print }' /etc/resolv.conf)

  # An empty value here would ship an image that never becomes reachable, and
  # the only symptom would be the consumer's SSH timing out half an hour later.
  # Fail the build while the reason is still on screen.
  [ -n "$interface" ] && [ -n "$gateway" ] && [ -n "$address" ]
  [ -n "$nameservers" ]

  # rc.conf rather than /etc/ifconfig.<if>: the variable wins over the file, and
  # appending overrides what the installer set. Both settings are needed --
  # `dhcpcd=NO` disables the service, but /etc/rc.d/network runs dhcpcd itself
  # for an interface still configured as `dhcp`, precisely when it is disabled.
  rm -f "/etc/ifconfig.$interface"

  # /etc/rc.d/network ends with `ifconfig $ifconfig_wait_dad_flags`, defaulting
  # to `-w 15 -W 5`. The `-W 5` waits for the `detached` flag to clear, which
  # nothing can satisfy: the consumer runs the guest with IPv6 off, so no router
  # is ever advertised. That was 6 of the 7 seconds rc took. An empty value
  # makes the wait a no-op; `-w 1` would keep it bounded instead.
  cat <<EOF >> /etc/rc.conf
ifconfig_$interface="$address"
defaultroute="$gateway"
dhcpcd=NO
ifconfig_wait_dad_flags=""
EOF

  echo "$nameservers" > /etc/resolv.conf

  # dhcpcd is disabled from the next boot on, but it's still running while this
  # image is built, and stopping it during the final poweroff restores the
  # pre-DHCP /etc/resolv.conf. Keep a copy it doesn't know about, which
  # configure_boot_scripts restores at boot if that happened.
  cp /etc/resolv.conf "$RESOLV_BACKUP"
}

# ntpdate's rc.d script runs it inline, so the boot waits for network round
# trips to correct an offset that is already ~0: QEMU seeds the emulated RTC
# from the host clock. ntpd stays -- a daemon costs nothing on the path to
# sshd, and -g steps a large initial offset the way ntpdate would have.
configure_time_sync() {
  cat <<EOF >> /etc/rc.conf
ntpdate=NO
ntpd=YES
ntpd_flags="-g"
EOF
}

# Let the secondary user log in over SSH with no credential, the way the VAX
# image does (resources/post_install_vax.sh). Three things have to line up, and
# the login fails if any one is missing:
#
#   1. PermitEmptyPasswords, or sshd passes PAM_DISALLOW_NULL_AUTHTOK
#      (post_install.sh).
#   2. `nullok` on pam_unix's auth line, or it substitutes "*" for the empty
#      hash.
#   3. An actually empty password field; sysinst set one during the install.
#
# Only the secondary user is passwordless; root keeps its install password. The
# image is a throwaway CI guest, reachable only through the consumer's own port
# forward.
setup_passwordless_login() {
  sed -i -E '/^auth[[:space:]]+required[[:space:]]+pam_unix\.so/ s/$/ nullok/' \
    /etc/pam.d/sshd

  sed -i -E "s/^(${SECONDARY_USER}):[^:]*:/\1::/" /etc/master.passwd
  pwd_mkdb -p /etc/master.passwd

  # A substitution that matches nothing leaves sed successful, so assert the
  # result instead of trusting it.
  grep -q '^auth.*pam_unix\.so.*nullok' /etc/pam.d/sshd
  grep -q "^${SECONDARY_USER}::" /etc/master.passwd
}

# Stamp each rc.d script as it starts, so the time between init and sshd can be
# attributed to individual scripts. One second resolution: NetBSD's date(1) has
# no sub-second conversion. The line goes in front of the cmd-name metadata,
# never between run_rc_script and the cmd-status line reporting its $?.
configure_boot_timestamps() {
  [ "${BOOT_TIMESTAMPS:-}" = 'true' ] || return 0

  awk '
    /print_rc_metadata "cmd-name:\$_rc_elem"/ {
      print "\t\tprint_rc_normal \"cpa-boot-timestamp $(date +%s) $_rc_elem\""
      patched = 1
    }
    { print }
    END { if (!patched) exit 1 }
  ' /etc/rc > /tmp/rc.timestamps

  # Redirect into the existing file rather than moving over it, to keep the
  # mode and ownership of /etc/rc.
  cat /tmp/rc.timestamps > /etc/rc
  rm -f /tmp/rc.timestamps
}

# The resources disk and the key it carries are still how the action logs in.
# Once it stops delivering one (the image now accepts a passwordless login, see
# setup_passwordless_login) both this hook and the msdosfs dependency it brings
# can go away.
configure_boot_scripts() {
  cat <<EOF >> /etc/rc.local
RESOURCES_MOUNT_PATH='/mnt/resources'
RESOLV_BACKUP='$RESOLV_BACKUP'

restore_resolv_conf() {
  [ -s /etc/resolv.conf ] || cp "\$RESOLV_BACKUP" /etc/resolv.conf
}

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

restore_resolv_conf
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
configure_boot_timestamps
configure_network
configure_time_sync
setup_passwordless_login
configure_boot_scripts
set_hostname

configure_package_repository
install_extra_packages
setup_sudo
