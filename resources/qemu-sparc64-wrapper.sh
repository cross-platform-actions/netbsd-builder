#!/bin/bash
# Packer's qemu builder hardcodes two things that don't suit sparc64
# under OpenBIOS:
#
# 1. `-device <MODEL>,netdev=user.0` paired with `-netdev user,id=user.0,...`
#    for networking. On some sparc64 setups the resulting PCI placement
#    lands the NIC on a slot OpenBIOS doesn't publish as the on-board
#    network alias, and packets never escape. The legacy form
#    `-net nic,model=<MODEL> -net user,hostfwd=...` attaches to the
#    on-board slot the firmware already knows.
#
#    Only Packer's *bare* `-device <MODEL>,netdev=user.0` (no other suffix)
#    is rewritten — if the caller wrote out a deliberate placement like
#    `-device sunhme,bus=pciB,netdev=user.0`, that's a user choice and is
#    left alone (NetBSD's CD-boot path needs the explicit pciB placement).
#    Packer passes -netdev *before* -device in argv, so we do two passes:
#    scan first to detect an explicit -device, then rewrite on the second.
#
# 2. `-drive file=<ISO>,media=cdrom` for the install ISO, with no `index=`,
#    which auto-attaches the CD to ide.0.1. OpenBIOS sun4u's `cdrom` alias
#    points at ide.1.0 (secondary-master), so booting from the CD via the
#    `cdrom` alias finds nothing. Adding `index=2` forces the auto-IDE
#    allocator to put the CD at ide.1.0 — matching what plain `qemu …
#    -cdrom <iso>` does, which is the form known to actually boot
#    NetBSD/sparc64 install CDs on QEMU 10.x.
set -e

REAL_QEMU=${CPA_REAL_QEMU:-qemu-system-sparc64}

# Pass 1: detect whether the caller passed an explicit `-device <X>,...,
# netdev=user.0` (something other than the bare `<X>,netdev=user.0` form).
saw_explicit_net=0
i=1
while [ $i -le $# ]; do
  if [ "${!i}" = "-device" ]; then
    j=$((i + 1))
    if [ $j -le $# ]; then
      val="${!j}"
      if [[ "$val" == *",netdev=user.0"* ]] && \
         ! [[ "$val" =~ ^[^,]+,netdev=user\.0$ ]]; then
        saw_explicit_net=1
      fi
    fi
  fi
  i=$((i + 1))
done

# Pass 2: rewrite if appropriate, copy through otherwise.
args=()
nic_model=""
hostfwd=""

while [ $# -gt 0 ]; do
  case "$1" in
    -device)
      if [ "$saw_explicit_net" = 0 ] && [ $# -ge 2 ] && \
         [[ "$2" =~ ^[^,]+,netdev=user\.0$ ]]; then
        nic_model=${2%%,*}
        shift 2
        continue
      fi
      ;;
    -netdev)
      if [ "$saw_explicit_net" = 0 ] && [ $# -ge 2 ] && [[ "$2" == user,* ]]; then
        case "$2" in
          *hostfwd=*)
            hostfwd=${2##*hostfwd=}
            hostfwd=${hostfwd%%,*}
            ;;
        esac
        shift 2
        continue
      fi
      ;;
    -drive)
      # Repin Packer's bare `media=cdrom` -drive to ide.1.0 by adding
      # `index=2`. Skip if the caller already specified an index= or used
      # a non-IDE interface — those are intentional placements.
      if [ $# -ge 2 ] && [[ "$2" == *",media=cdrom"* ]] && \
         [[ "$2" != *",index="* ]] && \
         [[ "$2" != *"if=none"* ]] && [[ "$2" != *"if=virtio"* ]] && \
         [[ "$2" != *"if=scsi"* ]]; then
        args+=("-drive" "$2,index=2")
        shift 2
        continue
      fi
      ;;
  esac
  args+=("$1")
  shift
done

if [ -n "$nic_model" ]; then
  if [ -n "$hostfwd" ]; then
    args+=("-net" "nic,model=$nic_model" "-net" "user,hostfwd=$hostfwd")
  else
    args+=("-net" "nic,model=$nic_model" "-net" "user")
  fi
fi

exec "$REAL_QEMU" "${args[@]}"
