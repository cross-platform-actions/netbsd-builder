#!/bin/sh

set -eux
set -o pipefail

configure_ssh() {
  tee -a /mnt/etc/ssh/sshd_config <<EOF
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UseDNS no
AcceptEnv *
EOF
}

mount /dev/dk0 /mnt
configure_ssh
