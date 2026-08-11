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
  # A pre-built image has no swap configured, in which case swapctl prints "no
  # swap devices configured" instead of a table, so match device paths rather
  # than everything that isn't the header.
  swap_device=$(swapctl -l 2> /dev/null | awk '/^\// { print $1; exit }')

  if [ -z "$swap_device" ]; then
    echo 'no swap device configured; skipping'
    return 0
  fi

  swapctl -d "$swap_device"
  dd if=/dev/zero of="/dev/r${swap_device#/dev/}" bs=1048576 || :
}

# The VM is stopped by packer when the machine cannot power itself off. Leave
# the file systems clean, so that the image doesn't have to be checked on the
# next boot.
unmount_file_systems() {
  [ "${UNMOUNT_FILE_SYSTEMS:-false}" = 'true' ] || return 0

  sync
  sync

  # Best effort: the remount fails when something still holds the file system
  # busy, and the sync above is what actually makes the image safe to stop.
  mount -u -r / || :
}

setup_path
minimize_disk
minimize_swap
unmount_file_systems
