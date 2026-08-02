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
# What we skip that the QEMU provisioners do:
#   - pkgin install bash curl rsync sudo  (NetBSD has no prebuilt VAX
#     pkgsrc binaries, so pkgin can't be installed)
#   - sudoers.d for the secondary user  (no sudo without pkgin)

set -eux
set -o pipefail

HOSTNAME="${HOSTNAME:-runnervmg1sw1.local}"

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
minimize_disk

# Unmount and sync so all metadata is flushed before we halt the
# installer. We can't rely on the kernel doing this cleanly at HALT.
umount /mnt
sync
sync
