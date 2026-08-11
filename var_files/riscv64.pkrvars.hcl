machine_type = "virt"
cpu_type = "rv64"

// RISC-V boots through QEMU's built-in OpenSBI firmware, with the kernel
// loaded directly by QEMU. There's no separate firmware file.
firmware = ""
kernel_command_line = "root=dk1"

// NetBSD publishes no installation media for the riscv port, only a pre-built
// disk image.
disk_image = true
post_install_disk_device = "/dev/dk1"

// The RISC-V kernel only attaches virtio devices through the MMIO transport,
// it leaves the ones on the PCI bus unconfigured.
net_device = "virtio-net-device"

// Without an entropy source the first boot generates the SSH host keys anyway
// and only warns that they may be predictable, so this is not optional. It's
// the MMIO transport of the same device, for the same reason as the two above.
extra_qemuargs = [
  ["-device", "virtio-rng-device"]
]

// The image boots and configures itself, under emulation, before SSH becomes
// available. Long enough for that, short enough to not keep a broken build
// running for hours.
ssh_timeout = "45m"

// Running the shutdown sequence under emulation takes longer than the five
// minutes packer waits by default.
shutdown_timeout = "20m"

architecture = {
  name = "riscv64"
  image = "riscv-riscv64"
  qemu = "riscv64"
}

keyboard_layout_steps = []
correct_geometry_steps = []
bootblock_selection_steps = []
