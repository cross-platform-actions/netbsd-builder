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

# Zero the swap wedge through its raw (character) device rather than the
# buffered block device. swapctl -d has just removed the guest's only
# swap, so the ~4 GB of dirty pages a block-device write parks in the
# buffer cache have nowhere to be paged out to -- on a guest whose RAM is
# the same size as its swap wedge that wedges the kernel, and the build
# dies with packer's "Script disconnected unexpectedly". The raw device
# bypasses the buffer cache entirely. dd still ends with a benign error
# at end-of-device, which `|| :` swallows.
minimize_swap() {
  swap_device=$(swapctl -l | awk '!/^Device/ { print $1 }')
  swapctl -d "$swap_device"
  dd if=/dev/zero of="/dev/r${swap_device#/dev/}" bs=1048576 || :
}

setup_path
minimize_disk
minimize_swap
