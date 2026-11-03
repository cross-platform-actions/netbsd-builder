machine_type             = "sun4u"
cpu_type                 = "TI-UltraSparc-IIi"
cpus                     = 1
memory                   = 2048 // 512 is not enough for pkgin to resolve dependencies
firmware                 = "openbios-sparc64"
post_install_disk_device = "/dev/sd0a" // disklabel, not GPT, so makewedges creates no dk devices
disk_name                = "sd0"
net_device               = "sunhme"

// Not IDE: upstream QEMU's sun4u PCI bridge (sabre) drops the IDE controller's
// interrupt when another PCI device raises one before the guest acknowledges
// it, and the guest hangs for good partway through downloading packages. The
// QEMU the images run on is patched, but the one building them may not be.
// Not virtio either: NetBSD 10.1 fails to negotiate its features. The install
// CD stays on IDE, where OpenBIOS's `cdrom` alias points.
disk_interface = "scsi"

architecture = {
  name  = "sparc64"
  image = "sparc64"
  qemu  = "sparc64"
}

// The wrapper does two things sparc64 needs that Packer's qemu builder
// doesn't expose as options:
//   1. Repins Packer's auto-attached `-drive ...,media=cdrom` with
//      `index=2`, putting the CD at ide.1.0 — the slot OpenBIOS's
//      `cdrom` OFW alias points to. Without this, the CD lands at
//      ide.0.1 and isn't bootable through any tested alias.
//   2. As an escape hatch for other sparc64 setups, rewrites Packer's
//      bare `-device <MODEL>,netdev=user.0` into the legacy
//      `-net nic,model=<MODEL>` form. We don't trigger that path here
//      because the explicit `-device sunhme,bus=pciB,netdev=user.0`
//      below opts out of Packer's auto-inject (which the wrapper
//      detects and leaves alone).
qemu_binary = "./resources/qemu-sparc64-wrapper.sh"

// sparc64 is always emulated, so the defaults (tuned for accelerated
// x86-64/arm64) are far too short. These are fixed sleeps, not polls: too
// short silently desyncs the boot_steps and corrupts the install.
boot_wait    = "2m"
step_wait    = "15"
install_wait = "45m"
network_wait = "60"

// pkg_add is still running well past the 2m the default allows.
pkgin_install_steps = [
  ["x<enter><wait10m>", "Install pkgin and update package summary"],
  ["<enter><wait15s>", "Hit enter to continue"]
]

// boot_wait covers the boot; sparc64 has no boot-loader menu to answer.
initial_boot_steps = []

// sparc64 sysinst skips the keyboard layout menu — language selection
// goes directly to the main install menu. Verified by stepping through
// the install interactively with VNC screenshots; if Packer types a
// keystroke here it lands on the main menu instead, which throws every
// subsequent boot_step out of phase and corrupts the install.
keyboard_layout_steps = []

// sparc64 uses disklabel by default; there is no partition type selection step
partition_type_steps = []

// sparc64 does not show a geometry confirmation step
correct_geometry_steps = []

// sparc64 does not show a bootblock selection step
bootblock_selection_steps = []

// sparc64 uses communicator=none because:
// 1. OpenBIOS in QEMU sun4u panics on OF_boot when the kernel reboots,
//    so we cannot boot the installed system back up to run SSH.
// 2. SSH handshake under TCG would exceed Packer's timeout anyway.
// All provisioning is done inline via boot_steps + chroot into /mnt.
communicator_type = "none"

// halt -p on sparc64 may hang on OF_exit (same OF_* family as the OF_boot
// panic that breaks reboot). We try a clean QEMU monitor `quit` first and
// fall back to halt -p. Generous timeout in case the fallback path is the
// one that actually exits QEMU.
shutdown_timeout = "1h"

// Instead of rebooting, quit QEMU: the template has already provisioned the
// installed system from the installer's shell, since there is no communicator.
// cleanup.sh is skipped because zeroing a 12GB disk under TCG is too slow.
reboot_steps = [
  // The image is built on SCSI but boots from IDE. ROOT.x names a partition
  // of whichever disk the kernel booted from.
  ["chroot /mnt sed -i -E 's#^/dev/sd0([a-p])#ROOT.\\1#' /etc/fstab<enter><wait15s>", "Name the root disk in fstab independently of its interface"],
  // Sync, then make QEMU exit by sending `quit` to its HMP monitor at
  // 10.0.2.2:4444 (the host, as seen via QEMU's user-mode net). nc isn't in
  // the installer ramdisk, so run it via `chroot /mnt`. Retried so a slow
  // SLIRP connect under TCG can't strand QEMU. halt -p is a last resort;
  // sun4u is expected to hang in OF_exit.
  //
  // No wait after this step: packer only expects QEMU to exit once it is
  // waiting for the shutdown, and fails the build if QEMU exits while a boot
  // step is still running. The sleep gives packer time to get there.
  ["sleep 10; sync; sync; chroot /mnt sh -c 'for i in $(seq 1 10); do printf \"quit\\n\" | nc -w10 10.0.2.2 4444 && break; sleep 3; done'; halt -p<enter>", "Sync, quit QEMU via monitor (retry), halt -p fallback"],
]

qemuargs = [
  ["-boot", "d"],
  // Place the sunhme NIC on pciB. busA and the root bus have masked slots,
  // and the on-board PCI slot's network FCode evaluates at boot time and
  // dies on `set-symbol-lookup` (unimplemented OF service) before the
  // firmware tries the CD-ROM. pciB (slots 0–3) is the only safe spot.
  ["-device", "sunhme,bus=pciB,netdev=user.0"],
  // Replaces Packer's own -netdev, which leaves IPv6 on. slirp then hands the
  // guest an IPv6 route that leads nowhere, and every download first waits out
  // each of the mirror's IPv6 addresses, minutes apiece under emulation.
  ["-netdev", "user,id=user.0,ipv6=off"],
  // Route OS keyboard input through the keyboard device so Packer's VNC
  // keystrokes reach the kernel. We deliberately do *not* set
  // `output-device=screen` — that combination wedges OpenBIOS in QEMU
  // 10.x. Even so, only OpenBIOS's own output reaches ttya and the console
  // log: NetBSD's kernel, the installer and the shell all appear on the
  // framebuffer.
  ["-prom-env", "input-device=keyboard"],
]
