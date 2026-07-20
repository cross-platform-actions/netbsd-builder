machine_type             = "sun4u"
cpu_type                 = "TI-UltraSparc-IIi"
cpus                     = 1
memory                   = 512
firmware                 = "openbios-sparc64"
post_install_disk_device = "/dev/dk0"
disk_name                = "wd0"
disk_interface           = "ide"
net_device               = "sunhme"

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

// sparc64 under TCG emulation is slower — increase wait times
boot_wait    = "2m"
step_wait    = "15"
install_wait = "30m"
pkgin_wait   = "10m"
network_wait = "60"

// OpenBIOS + kernel boot under TCG completes in well under 2 min;
// the wait gives a comfortable margin before keystrokes start.
initial_boot_steps = [
  ["<wait2m>", "Wait for OpenBIOS boot and NetBSD kernel to load"]
]

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

// reboot_steps for sparc64: instead of rebooting, provision inline via chroot.
// Note: reboot_steps start from the Utility menu (after post_install.sh ran).
// cleanup.sh is skipped because zeroing a 12GB disk under TCG is too slow.
reboot_steps = [
  ["a<enter><wait15s>", "Run /bin/sh from Utility menu"],
  // Download and run provision.sh in chroot
  ["ftp -o /mnt/tmp/provision.sh http://{{ .HTTPIP }}:{{ .HTTPPort }}/resources/provision.sh<enter><wait15s>", "Download provision.sh"],
  // pkgin inside the chroot needs working DNS to download packages from the
  // mirror. sysinst configured DNS in the installer's /etc/resolv.conf, but
  // the installed system's /mnt/etc/resolv.conf may be empty, so copy it in.
  ["cp /etc/resolv.conf /mnt/etc/resolv.conf<enter><wait5s>", "Copy resolv.conf into chroot for DNS"],
  ["chroot /mnt sh -c 'SECONDARY_USER=runner sh /tmp/provision.sh'<enter><wait30m>", "Run provision.sh in chroot (includes pkgin install)"],
  // Sync filesystems, then try to make QEMU exit cleanly. Two attempts:
  //   1. `quit` to QEMU's HMP monitor at 10.0.2.2:4444 (10.0.2.2 is the
  //      host as seen via QEMU's user-mode net). nc isn't in the sparc64
  //      installer ramdisk, so we run it via `chroot /mnt` against the
  //      installed system's /usr/bin/nc.
  //   2. If that fails, halt -p (mirrors openbsd-sparc64). Either path
  //      ends with QEMU exiting and Packer flushing the qcow2.
  ["sync; sync; chroot /mnt sh -c 'printf \"quit\\n\" | nc -w2 10.0.2.2 4444'; halt -p<enter><wait30s>", "Sync, quit QEMU via monitor, halt -p as fallback"],
]

qemuargs = [
  ["-boot", "d"],
  ["-monitor", "tcp:0.0.0.0:4444,server,nowait"],
  ["-serial", "file:serial.log"],
  // Place the sunhme NIC on pciB. busA and the root bus have masked slots,
  // and the on-board PCI slot's network FCode evaluates at boot time and
  // dies on `set-symbol-lookup` (unimplemented OF service) before the
  // firmware tries the CD-ROM. pciB (slots 0–3) is the only safe spot.
  ["-device", "sunhme,bus=pciB,netdev=user.0"],
  // Route OS keyboard input through the keyboard device so Packer's VNC
  // keystrokes reach the kernel. We deliberately do *not* set
  // `output-device=screen` — that combination wedges OpenBIOS in QEMU
  // 10.x. Output stays on serial (ttya), which is what serial.log
  // captures from `-serial file:serial.log`.
  ["-prom-env", "input-device=keyboard"],
]
