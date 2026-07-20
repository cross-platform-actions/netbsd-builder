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

dkctl "${DISK_NAME:-sd0}" makewedges
mount "$DISK_DEVICE" /mnt
configure_ssh
