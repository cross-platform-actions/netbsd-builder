machine_type = "virt"
cpu_type = "cortex-a57"
firmware = "edk2-aarch64-code.fd"
post_install_disk_device = "/dev/dk1"

architecture = {
  name = "arm64"
  image = "evbarm-aarch64"
  qemu = "aarch64"
}

keyboard_layout_steps = []
correct_geometry_steps = []
bootblock_selection_steps = []
