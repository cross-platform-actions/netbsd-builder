machine_type = "virt,highmem=off" // highmem=off if reqiured for enabling hardware acceleration on Apple Silicon
cpu_type = "cortex-a57"
firmware = "edk2-aarch64-code.fd"
post_install_disk_device = "/dev/dk1"
memory = 3072 // max memory when hardware acceleration on Apple Silicon is enabled

architecture = {
  name = "arm64"
  image = "evbarm-aarch64"
  qemu = "aarch64"
}

keyboard_layout_steps = []
correct_geometry_steps = []
bootblock_selection_steps = []
