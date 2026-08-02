#!/bin/sh

set -eux
set -o pipefail

configure_ssh() {
  cat <<EOF >> /mnt/etc/ssh/sshd_config
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UseDNS no
AcceptEnv *
EOF
}

# Belt-and-suspenders: ensure sshd is enabled at boot regardless of whether
# the sysinst configmenu toggle was applied successfully. rc.conf evaluates
# later assignments last, so appending here wins.
enable_sshd_at_boot() {
  echo 'sshd=YES' >> /mnt/etc/rc.conf
}

dkctl "${DISK_NAME:-sd0}" makewedges
mount "$DISK_DEVICE" /mnt
configure_ssh
enable_sshd_at_boot
