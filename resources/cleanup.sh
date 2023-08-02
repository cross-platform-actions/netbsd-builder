#!/bin/sh

set -exu

setup_path() {
  PATH="/sbin:/usr/sbin:$PATH"
  export PATH
}

minimize_disk() {
  for dir in $(mount | awk '{ print $3 }'); do
    dd if=/dev/zero of="$dir/EMPTY" bs=1048576 || :
    rm -f "$dir/EMPTY"
  done
}

minimize_swap() {
  swap_device=$(swapctl -l | awk '!/^Device/ { print $1 }')
  swapctl -d "$swap_device"
  dd if=/dev/zero of="$swap_device" bs=1048576 || :
}

setup_path
minimize_disk
minimize_swap
