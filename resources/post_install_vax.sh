#!/bin/sh

# VAX-only post-install script.
#
# On NetBSD/VAX we deliberately do not boot the installed system from disk
# inside the same SIMH process that ran the install — the KA655 SSC self-
# test is non-deterministic across in-process boot cycles, so any attempt
# to reboot and run the standard SSH provisioners is unreliable. Instead
# we do all provisioning here, from the installer's /bin/sh with the
# target system mounted at /mnt, and then halt (not reboot). The disk
# image is the artifact; when the consumer launches it in a fresh SIMH
# process the firmware self-test passes and NetBSD boots normally.
#
# What we do that the SSH-based provisioners would otherwise do:
#   - Configure sshd to allow password login (PermitRootLogin, password
#     auth). The CI harness logs in as the secondary user with the
#     password set during install (var_files/common.pkrvars.hcl), so we
#     do not inject keys via the resources disk the way the other ports
#     do. Empty-password ssh isn't an option here: NetBSD's sshd rejects
#     it even with PermitEmptyPasswords.
#   - Enable sshd at boot
#   - Set boot loader timeout to 0
#   - Set the hostname
#   - Minimize the disk image (zero unused blocks so zstd compresses it well)
#
# What we also do, matching the QEMU provisioners -- the official NetBSD
# mirrors carry no vax binaries, so the packages come from the
# cross-platform-actions netbsd-pkg-repo release, which build.sh mirrors onto
# packer's HTTP server:
#   - Install bash, curl, pkgin, rsync, sudo into the target
#   - Point the shipped pkgin at the release so the consumer can install more
#   - sudoers.d NOPASSWD for the secondary user

set -eux
set -o pipefail

HOSTNAME="${HOSTNAME:-runnervmg1sw1.local}"
SECONDARY_USER="${SECONDARY_USER:-runner}"

dkctl "${DISK_NAME:-sd0}" makewedges
mount "$DISK_DEVICE" /mnt

# Install the SSH host keys that rc.d/sshd would otherwise generate on
# the consumer's first boot — RSA-3072 generation takes ~20 minutes at
# the emulated VAX's ~1 MIPS, all spent before sshd accepts
# connections. build.sh generates the keys on the build host and this
# fetches them over packer's HTTP server (the same channel that
# delivered this script). The keys are shared by every VM booted from
# the published image, which is fine for its purpose: throwaway CI
# guests reached with StrictHostKeyChecking=no.
install_ssh_host_keys() {
  for key_type in rsa ecdsa ed25519; do
    key="ssh_host_${key_type}_key"
    ftp -o "/mnt/etc/ssh/$key" "http://${HTTP_SERVER}/ssh_host_keys/$key"
    ftp -o "/mnt/etc/ssh/$key.pub" "http://${HTTP_SERVER}/ssh_host_keys/$key.pub"
    chmod 600 "/mnt/etc/ssh/$key"
    chmod 644 "/mnt/etc/ssh/$key.pub"
  done
}

configure_ssh() {
  cat <<EOF >> /mnt/etc/ssh/sshd_config
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UseDNS no
AcceptEnv *
EOF
}

enable_sshd_at_boot() {
  echo 'sshd=YES' >> /mnt/etc/rc.conf
}

configure_boot_flags() {
  if [ -f /mnt/boot.cfg ]; then
    sed -i -E 's/timeout=.+/timeout=0/' /mnt/boot.cfg
  else
    echo 'timeout=0' > /mnt/boot.cfg
  fi
}

set_hostname() {
  echo "hostname=${HOSTNAME}" >> /mnt/etc/rc.conf
}

install_packages() {
  # build.sh mirrored the netbsd-pkg-repo release (plus a MANIFEST listing the
  # .tgz files) onto packer's HTTP server. Fetch every package into the target
  # with the installer's ftp -- the same plain-HTTP fetch that already delivered
  # this script (an IP, so no DNS and no TLS on the ~1 MIPS VAX) -- then install
  # from those LOCAL files inside chroot with PKG_PATH pointing at the directory.
  #
  # Why not pkg_add straight from the HTTP mirror: pkg_add's HTTP directory glob
  # (used to expand a bare name and resolve dependencies) works on a booted
  # system but fails inside the sysinst installer's chroot with "Invalid URL
  # scheme". Installing from a local directory uses filesystem globbing instead
  # -- pkgsrc's original, chroot-safe install mode -- sidestepping that entirely.
  mirror="http://${HTTP_SERVER}/vax_packages/All"
  dest=/mnt/tmp/vax_packages
  mkdir -p "$dest"
  ftp -o "$dest/MANIFEST" "$mirror/MANIFEST"
  while read -r f; do
    [ -n "$f" ] || continue
    ftp -o "$dest/$f" "$mirror/$f"
  done < "$dest/MANIFEST"

  # /tmp/vax_packages is the chroot-relative path of $dest (/mnt/tmp/...).
  # sh -c so the PKG_PATH assignment applies to pkg_add inside the chroot.
  chroot /mnt /bin/sh -c \
    'PKG_PATH=/tmp/vax_packages /usr/sbin/pkg_add -v bash curl pkgin rsync sudo'

  rm -rf "$dest"

  # Point the shipped pkgin at the real release so the consumer can install
  # more packages on the running image (over TLS, but only when they choose to).
  mkdir -p /mnt/usr/pkg/etc/pkgin
  echo "${PKG_RELEASE_URL}" > /mnt/usr/pkg/etc/pkgin/repositories.conf
}

setup_sudo() {
  # Passwordless sudo for the CI user, same as the QEMU ports' provision.sh.
  mkdir -p /mnt/usr/pkg/etc/sudoers.d
  cat <<EOF > "/mnt/usr/pkg/etc/sudoers.d/${SECONDARY_USER}"
Defaults:${SECONDARY_USER} !requiretty
${SECONDARY_USER} ALL=(ALL) NOPASSWD: ALL
EOF
  chmod 440 "/mnt/usr/pkg/etc/sudoers.d/${SECONDARY_USER}"
}

minimize_disk() {
  # Zero the free blocks so the RAW image's unused space is a long run
  # of zeros that zstd (run by build.sh) compresses to almost nothing.
  dd if=/dev/zero of=/mnt/EMPTY bs=1048576 || :
  rm -f /mnt/EMPTY
}

install_ssh_host_keys
configure_ssh
enable_sshd_at_boot
configure_boot_flags
set_hostname
install_packages
setup_sudo
minimize_disk
# The boot_command waits for this marker before sending `halt -p`. set -e aborts
# the script before here if any step failed, so a failed run trips a
# boot_step_timeout instead of halting as though it had succeeded.
echo VAXBUILD_POST_INSTALL_DONE

# Unmount and sync so all metadata is flushed before we halt the
# installer. We can't rely on the kernel doing this cleanly at HALT.
umount /mnt
sync
sync
